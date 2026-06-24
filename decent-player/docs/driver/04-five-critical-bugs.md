# 04 — The Five Critical Bugs That Blocked Bit-Perfect Audio

Each of these bugs individually caused complete silence. All five had to be fixed for audio to work.

---

## Bug 1: Wrong Clock Source Entity ID

**Symptom:** SET_CUR returns success (ret=4), GET_CUR confirms desired rate, but DAC hardware stays at 384kHz. Feedback endpoint reports 384kHz.

**Root cause:** The Cayin RU7 firmware accepts SET_CUR/GET_CUR control transfers to ANY entity ID without returning STALL. Entity ID `0x0B` (found by brute-force) was a ghost — the transfer completed but targeted a non-existent entity. Only entity `0x05` (the actual CLOCK_SOURCE declared in the USB descriptor) controls the clock PLL.

**How discovered:** Read raw USB descriptors on iBasso DX340:
```bash
od -A x -t x1 /sys/bus/usb/devices/1-1/descriptors
```
Parsed the AudioControl interface and found:
```
Clock Source Descriptor (offset 0x38):
  bDescriptorSubtype = 0x0A (CLOCK_SOURCE)
  bClockID = 0x05
```

**Fix:** Parse `UsbDeviceConnection.getRawDescriptors()` at runtime to find the CLOCK_SOURCE descriptor and extract `bClockID`. No more brute-force guessing.

**Lesson:** Never trust a USB control transfer returning success. Verify the actual hardware state via an independent mechanism (feedback endpoint).

---

## Bug 2: Missing `USBDEVFS_URB_ISO_ASAP` Flag

**Symptom:** URBs return status=0, all bytes "transferred", but zero data on the USB bus. Feedback endpoint doesn't respond. DAC shows no sample rate.

**Root cause:** The URB struct was allocated with `calloc()` (all zeros), so `urb->flags = 0`. Without `USBDEVFS_URB_ISO_ASAP` (0x02), the kernel uses `urb->start_frame` for scheduling. Since `start_frame = 0` (also zeroed), the kernel schedules packets at frame 0 — which is in the past. The xHCI host controller silently drops all packets.

The kernel reports status=0 because the URB was "processed" (scheduled and completed from the kernel's perspective), but the packets were never physically transmitted.

**How discovered:** Research into Linux kernel `drivers/usb/core/devio.c` and `libusb` source code. `libusb` always sets `USBFS_URB_ISO_ASAP` in `submit_iso_transfer()`.

**Fix:** One line:
```c
urb->flags = USBDEVFS_URB_ISO_ASAP;  // 0x02
```

**Lesson:** For isochronous transfers, `USBDEVFS_URB_ISO_ASAP` is not optional. The kernel documentation doesn't emphasize this enough.

---

## Bug 3: Java vs Native `setInterface()` for ISO Bandwidth

**Symptom:** All previous bugs fixed. URBs submitted with ISO_ASAP. Feedback endpoint responds (clock correct). But still zero sound.

**Root cause:** Native `USBDEVFS_SETINTERFACE` ioctl selects the alt setting but does NOT allocate isochronous bandwidth in the xHCI host controller's scheduler. The Java `UsbDeviceConnection.setInterface()` calls the same ioctl but through a different kernel path that DOES allocate bandwidth.

**How discovered:** On iBasso DX340, read `/sys/kernel/debug/usb/devices`:
```
With native setInterface:  B: Alloc=0/800 us (0%), #Int=0, #Iso=0
With Java setInterface:    B: Alloc=0/800 us (0%), #Int=0, #Iso=8
```

`#Iso=0` means the xHCI scheduler has no isochronous transfers allocated, even though URBs are being submitted and "accepted."

**Fix:** Use Java `UsbDeviceConnection.setInterface()` for the final alt setting activation:
```kotlin
usbAudioManager.setAltSetting(altSetting)  // Java API — allocates ISO bandwidth
```
Use native ioctl only for alt=0 (zero-bandwidth, no ISO needed).

**Lesson:** On Android, the Java USB API and native usbdevfs ioctls are NOT equivalent for isochronous transfers. Java setInterface() goes through additional kernel setup paths.

---

## Bug 4: Single URB Pipeline (#Iso=1 vs #Iso=74)

**Symptom:** All previous bugs fixed. ISO bandwidth allocated (#Iso>0). Feedback confirms correct rate. Data is real (non-zero PCM). But still zero sound.

**Root cause:** Our code used blocking submit-reap: `submit URB → REAPURB (block) → submit next`. This keeps exactly 1 URB in flight (#Iso=1). The xHCI host controller needs multiple URBs queued to maintain continuous isochronous streaming. With 1 URB, there are gaps between each microframe where no data is scheduled. The DAC receives intermittent data and doesn't produce audio.

Bit-perfect USB audio requires multiple URBs in flight (#Iso>=8).

**How discovered:** Compared `#Iso` values between our driver and a reference bit-perfect app on iBasso DX340:
```
Our driver (no sound):  #Iso=1
Optimal (works):     #Iso=74
```

**Fix:** Pre-submit 8 silence URBs at stream start (fire-and-forget). Then each `write()` submits a new URB and reaps an old one, maintaining a pipeline of 8.

```c
// In nativeUsbAudioStart: pre-fill pipeline
for (int u = 0; u < USB_AUDIO_NUM_URBS; u++) {
    submitIsoUrb(fd, endpoint, silenceBuf, packetSizes, numPackets);
    ctx->urbsInFlight++;
}

// In nativeUsbAudioWrite: maintain pipeline
if (ctx->urbsInFlight >= USB_AUDIO_NUM_URBS) {
    reapOneUrb(ctx->fd);  // free oldest
    ctx->urbsInFlight--;
}
submitIsoUrb(fd, endpoint, dataBuf, packetSizes, numPackets);
ctx->urbsInFlight++;
```

**Lesson:** Isochronous USB streaming is fundamentally a pipeline architecture. Single-URB patterns WILL produce silence, even if every individual transfer succeeds.

---

## Bug 5: snd-usb-audio Kernel Driver Race Condition

**Symptom:** On Samsung S26 Ultra, the kernel `snd-usb-audio` module binds to the USB device ~3ms before our `USB_DEVICE_ATTACHED` handler runs. It configures the DAC to 384kHz (Samsung UHQA default). Our subsequent `claimInterface(force=true)` detaches the kernel driver, but the DAC's clock PLL is already set to 384kHz.

**Root cause:** The kernel USB subsystem binds drivers immediately on device detection (in the USB interrupt handler). Android's `USB_DEVICE_ATTACHED` intent is sent later, after the kernel has already probed and configured the device.

**Mitigation (not a full fix):** 
1. Claim interfaces ASAP in the `USB_DEVICE_ATTACHED` handler
2. With the correct Clock Source ID (Bug 1 fix), our SET_CUR successfully changes the clock even after the kernel configured it — because we now target the correct entity
3. The `USBDEVFS_RESET` + immediate native claim approach reduces the race window

**On iBasso DX340:** The race is less severe because the device doesn't have Samsung's UHQA upsampling.

**Lesson:** On Android, it's impossible to completely prevent `snd-usb-audio` from binding first without root. The mitigation is to properly reconfigure the device AFTER claiming it. This works as long as the correct Clock Source ID is used (Bug 1).
