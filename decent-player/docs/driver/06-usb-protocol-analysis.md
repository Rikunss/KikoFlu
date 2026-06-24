# 06 — USB Protocol Analysis Findings

All data collected via legitimate system-level observation (`dumpsys`, `sysfs`, `logcat`, xHCI ftrace). No APK decompilation was performed.

## Direct USB Audio Driver Behavior

A direct USB audio driver that bypasses AudioFlinger uses direct isochronous USB transfers. It does NOT use AudioFlinger for USB audio output.

## USB Device Claim

- Registers `USB_DEVICE_ATTACHED` intent filter for `class=1` (Audio)
- When USB DAC is connected, Android offers the app as handler
- The app claims interfaces via `UsbDeviceConnection.claimInterface(force=true)`
- Both AudioControl (iface 0) and AudioStreaming (iface 1) are claimed
- Driver binding changes from `snd-usb-audio` to `usbfs`
- Device permission stored: `device_name=/dev/bus/usb/001/002, uids=<app_uid>`

## Audio Path

- Isochronous data is sent directly via usbdevfs
- ~74 URBs in flight during playback (large pipeline)
- Uses alt setting 3 (32-bit PCM) even for 16-bit source files
- Feedback endpoint is active (clock synchronization)

## Ghost AudioTrack

A direct USB driver creates a "ghost" AudioTrack for MediaSession/notification:
```
AudioTrack: uid <app_uid>, Port ID 556
Format: PCM_16_BIT, 48000 Hz, Stereo
Flags: 0xa00 (FLAG_DEEP_BUFFER + FLAG_MUTE_HAPTIC)
Preferred Device Port ID: 3 (SPEAKER)
PortVol dB: -25 (nearly muted)
```

Key details:
- Routed to **SPEAKER** via `setPreferredDevice()` (NOT USB)
- Volume at -25 dB (nearly silent)
- Used only for system integration (MediaSession, notifications, lockscreen controls)

## AudioFlinger State During Direct USB Playback

```
Output devices: SPEAKER (0x2) — NOT USB
USB output thread: Standby=yes (NOT active)
USB audio patches: RELEASED
```

AudioFlinger has NO active connection to the USB device while the direct USB driver plays.

## Protocol Comparison: Reference vs Our Driver

| Aspect | Reference Observation | DecentPlayer |
|--------|----------------------|-------------|
| Claim method | UsbManager + claimInterface(force) | Same |
| Driver binding | usbfs | Same |
| snd-usb-audio | Detached | Same |
| AudioFlinger | Not used for USB | Same |
| Ghost AudioTrack | Speaker, -25dB | Speaker, muted |
| Alt setting | Always 3 (32-bit) | Auto-detect best (usually 3) |
| URBs in flight | ~74 | 8 |
| Feedback endpoint | Active | Active |
| Clock source | Auto-detected (presumably) | Auto-detected from descriptors |
| ISO_ASAP flag | Yes (inferred from xHCI ftrace) | Yes |
| Bandwidth allocation | Java setInterface (inferred) | Java setInterface |

## Log Patterns

```
AudioTrack: stop(422): called with 7155606 frames delivered
AudioTrack: restoreTrack_l(423): dead IAudioTrack, PCM, creating a new one from setOutputDevice()
```

The `restoreTrack_l: dead IAudioTrack` message appears when transitioning between tracks -- the ghost AudioTrack is recreated for the new MediaSession entry.

## Key Insight: Intent Filter Priority

A direct USB audio app registers for `USB_DEVICE_ATTACHED` in its manifest:
```xml
<activity android:name=".AudioActivity">
    <intent-filter>
        <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
    </intent-filter>
    <meta-data
        android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
        android:resource="@xml/device_filter" />
</activity>
```

Filter: `vendor_id=-1, product_id=-1, class=1` (matches ANY USB Audio device).

When the user selects the app as the default handler for USB audio devices, Android automatically grants permission and launches the app on device connect.
