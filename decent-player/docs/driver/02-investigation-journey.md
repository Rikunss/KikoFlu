# 02 — Investigation Journey: How We Got to Bit-Perfect

This document chronicles every step, dead end, and breakthrough in the order they happened on the night of 2026-04-03.

## Phase 1: HAL Diagnostic (Success)

**Goal:** Check if Samsung S26 Ultra supports `MIXER_BEHAVIOR_BIT_PERFECT` via Android 14+ API.

**Approach:** Created `UsbAudioDiagnosticDialog` that calls `AudioManager.getSupportedMixerAttributes()`.

**Result:** 
- `MIXER_BEHAVIOR_BIT_PERFECT` = **NOT SUPPORTED** on Samsung S26 Ultra
- All formats reported as `[DEFAULT]` only
- **44100 Hz not even listed** in supported rates (only 48kHz+)
- This explained why Adele (44.1kHz) was resampled to 48kHz

**Conclusion:** Official Android API path is dead. Need alternative approach.

## Phase 2: Research Alternatives

**Investigated:**
1. `setPreferredMixerAttributes()` with `MIXER_BEHAVIOR_DEFAULT` — partial win, not bit-perfect
2. `AUDIO_OUTPUT_FLAG_DIRECT` via `dlsym` — Samsung has no DIRECT profile for USB
3. Root-based audio policy modification — not viable for distribution
4. **Direct USB driver via `UsbManager`** — direct USB approach

**USB protocol analysis (via `dumpsys` during direct USB audio playback):**
- The app had **zero AudioTracks** in AudioFlinger for USB output
- The app had **USB device permission** via `UsbManager`
- USB device driver shows `usbfs` (not `snd-usb-audio`)
- A ghost AudioTrack on the **speaker** was used for MediaSession
- Confirmed: direct USB approach bypasses Android audio stack entirely

**Decision:** Implement direct USB audio driver via `UsbManager` + isochronous transfers.

## Phase 3: Initial Implementation

**Built:**
- `usb-audio-output.cpp` — native isochronous transfer via `USBDEVFS_SUBMITURB`
- `UsbAudioOutputProcessor.kt` — JNI wrapper
- `UsbAudioManager.kt` — USB device management
- Integration in `AaudioAudioSink.kt` — new code path before AAudio

**First test:** URBs accepted (status=0), all bytes "transferred" — but **zero sound**.

## Phase 4: The Permission Bug

**Problem:** Android never showed USB permission dialog when toggle was activated.
**Root cause:** `PendingIntent` with `FLAG_MUTABLE` and implicit intent → crash on Android 14+.
**Fix:** Added `setPackage()` to make intent explicit.

## Phase 5: The AudioFlinger Fight

**Problem:** Even with our driver active, Qualcomm PAL kept opening the USB device at 48kHz.
**Root cause:** `super.configure()` in ExoPlayer created an AudioTrack routed to USB via AudioFlinger.
**Investigation:** PAL logs showed `USB_AUDIO-RX rate 48000` repeatedly.

**Attempts:**
1. Configure delegate with 8kHz mono → PAL still opened USB
2. `setPreferredDevice(speaker)` on delegate → PAL still opened USB
3. Skip `super.configure()` entirely → ExoPlayer stuck in BUFFERING
4. Call `super.configure()` after USB claim → worked partially

**Final fix:** Call `super.configure()` normally but:
- Mute delegate (volume=0)
- Route delegate to speaker via `setPreferredDevice()`
- Do NOT call `super.handleBuffer()` was tried but broke ExoPlayer clock
- Final: call `super.handleBuffer()` but with delegate muted + speaker-routed

## Phase 6: The Clock Source Bug (CRITICAL)

**Problem:** SET_CUR sample rate returned success, GET_CUR confirmed 44100Hz, but feedback endpoint reported 384kHz. DAC never changed clock.

**Investigation:**
- Our code tried clock source IDs by brute force
- ID `0x0B` returned `ret=4` (success) from `controlTransfer`
- GET_CUR to `0x0B` returned 44100Hz
- But feedback endpoint consistently reported 384kHz

**Breakthrough:** Accessed USB descriptors on iBasso DX340 (rooted device):
```
od -A x -t x1 /sys/bus/usb/devices/1-1/descriptors
```

Parsed the AudioControl descriptor and found:
```
Clock Source Descriptor:
  bDescriptorSubtype = 0x0A (CLOCK_SOURCE)
  bClockID = 0x05    ← THE REAL ID
```

**Root cause:** The Cayin RU7 accepts SET_CUR/GET_CUR to ANY entity ID without STALL error. ID `0x0B` was a "ghost" — the transfer completed but the wrong entity was targeted. Only entity `0x05` actually controls the clock PLL.

**Fix:** Changed clock source ID from `0x0B` to `0x05`. Later generalized by parsing USB descriptors automatically.

## Phase 7: The ISO_ASAP Flag (CRITICAL)

**Problem:** URBs returned status=0 with all bytes "transferred" but no sound.

**Investigation:** Research into Linux kernel `devio.c` revealed that without `USBDEVFS_URB_ISO_ASAP` (0x02) flag, the kernel schedules isochronous packets at frame 0 (in the past). The xHCI host controller accepts the URB but silently drops all packets.

**Key insight:** `libusb` ALWAYS sets this flag. Our code used `calloc` (all zeros) for the URB struct, so `flags = 0`.

**Fix:** Added `urb->flags = USBDEVFS_URB_ISO_ASAP` (one line of code).

**Verification:** After this fix, the feedback endpoint started responding (previously silent), confirming data was actually on the USB bus.

## Phase 8: The ISO Bandwidth Bug (CRITICAL)

**Problem:** Even with ISO_ASAP, feedback working, clock correct — still no sound.

**Investigation on iBasso DX340:**
```
cat /sys/kernel/debug/usb/devices
```
Showed:
```
B: Alloc=0/800 us (0%), #Int=0, #Iso=0    ← OUR DRIVER
B: Alloc=0/800 us (0%), #Int=0, #Iso=74   ← optimal
```

**Root cause:** Native `USBDEVFS_SETINTERFACE` ioctl does NOT allocate isochronous bandwidth in the xHCI host controller. Only the Java `UsbDeviceConnection.setInterface()` properly allocates bandwidth.

**Fix:** Use Java `setInterface()` for the final alt setting activation, not native ioctl.

## Phase 9: The Pipeline Bug (CRITICAL)

**Problem:** With ISO bandwidth allocated, still no sound. `#Iso=1` (our driver) vs `#Iso=74` (optimal).

**Root cause:** Our blocking submit-reap pattern (`submit → REAPURB → submit`) only keeps 1 URB in flight at a time. Between URBs, the xHCI endpoint has no data. The DAC doesn't produce audio with intermittent data.

**Fix:** Pre-fill pipeline with 8 silence URBs at startup (fire and forget), then each `write()` submits a new URB and reaps an old one. Pipeline stays at 8 URBs continuously.

**Verification:** `#Iso=8` with our driver, sound confirmed.

## Phase 10: Generalization

**Problem:** Clock Source ID and alt setting were hardcoded for Cayin RU7.

**Fix:** Parse USB descriptors via `UsbDeviceConnection.getRawDescriptors()`:
- Scan for `CLOCK_SOURCE` descriptor (subtype `0x0A`) → extract `bClockID`
- Scan for `Format Type I` descriptors (subtype `0x02`) → extract `bBitResolution` per alt setting
- Choose the highest bit depth alt setting automatically

**Result:** Zero DAC-specific code. Works with any UAC2 device.

## Timeline

| Time | Event |
|------|-------|
| 00:47 | First diagnostic: no BIT_PERFECT support on S26 Ultra |
| 01:04 | USB protocol analysis: confirmed direct USB approach |
| 01:55 | First USB driver build: URBs accepted, no sound |
| 01:57 | Permission bug fixed |
| 02:00 | AudioFlinger conflict discovered |
| 02:20 | Clock source 0x0B "works" but feedback shows 384kHz |
| 02:35 | USB protocol logs captured on S26 |
| 03:20 | USBDEVFS_RESET attempted (kernel race condition) |
| 16:50 | iBasso DX340 connected — USB descriptors read |
| 16:58 | Clock Source ID = 0x05 discovered! Clock changes to 44.1kHz! |
| 17:05 | ISO_ASAP flag added — feedback endpoint responds |
| 17:21 | ISO bandwidth discovery — #Iso=0 vs #Iso=74 |
| 17:30 | Java setInterface() fix — bandwidth allocated |
| 17:38 | Pipeline of 8 URBs — **FIRST SOUND** (sine wave / grunido) |
| 18:06 | Real audio playing bit-perfect on S26 Ultra |
| 18:18 | Auto-detection generalized — zero DAC-specific code |
