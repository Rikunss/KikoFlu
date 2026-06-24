# 01 — Executive Summary: Bit-Perfect USB Audio Driver for Android

**Project:** decent-player — open-source bit-perfect USB audio for Android.
**Scope:** This document covers the **driver and integration libraries** in `libs/`. The standalone player application is future work; today's deliverable is the libraries any Media3-based Android app can consume.

## What was built

A native USB Audio Class 2.0 driver that sends PCM audio data directly from the app to a USB DAC via Linux `usbdevfs` isochronous transfers. The driver:

- **Bypasses AudioFlinger completely** — no mixer, no resampler, no volume scaling
- **Sends PCM bit-for-bit** as decoded by ExoPlayer / Media3
- **Supports any sample rate** the DAC advertises (44.1, 48, 88.2, 96, 176.4, 192, 352.8, 384 kHz)
- **Auto-detects** Clock Source ID and optimal bit depth from USB descriptors
- **Works without root** on stock Android 10+ devices
- **Generic** — no hard-coding for any specific DAC

## Verified on

| Device | Android | DAC | Status |
|--------|---------|-----|--------|
| Samsung Galaxy S26 Ultra | 16 (API 36) | Cayin RU7 | Bit-perfect confirmed |
| iBasso DX340 | 13 (API 33) | Cayin RU7 | Bit-perfect confirmed |

## What "bit-perfect" means here

When the driver is active:

- The kernel **`snd-usb-audio` driver is detached** (confirmed via `/sys/bus/usb/devices/*/driver` → `usbfs`)
- **No ALSA card** exists for the USB device (confirmed via `/proc/asound/cards`)
- **AudioFlinger has zero USB output threads** (confirmed via `dumpsys media.audio_flinger`)
- **Qualcomm PAL has zero USB activity** on Snapdragon devices (confirmed via logcat)
- The DAC's **feedback endpoint confirms the correct clock rate** (e.g., 44101.6 Hz for a 44.1 kHz source — the residual is the DAC crystal's tolerance, not resampling)
- **PCM data flows directly** from the ExoPlayer / Media3 extractor → integer or float conversion → isochronous USB packets → DAC hardware

See [`07-verification-and-diagnostics.md`](07-verification-and-diagnostics.md) for the full proof procedure.

## Prior art

Before this work, no open-source bit-perfect USB Audio Class 2.0 driver existed for Android. The Google Media3 / ExoPlayer team has had an [open issue (#415)](https://github.com/androidx/media/issues/415) since 2023 requesting exactly this feature. Closed-source approaches typically rely on `dlsym` hooks or partial AudioFlinger bypass; this project is a clean-room implementation that talks to the kernel's `usbdevfs` directly via isochronous transfers, with no AudioFlinger involvement at all.

## Key technical breakthroughs (in order of discovery)

1. **Clock Source Entity ID parsing** — the UAC2 Clock Source ID must be read from the USB descriptors of the device, not guessed.
2. **`USBDEVFS_URB_ISO_ASAP` flag** — without it the xHCI host controller silently drops all isochronous packets.
3. **Java `setInterface()` for ISO bandwidth** — the native `USBDEVFS_SETINTERFACE` ioctl does **not** allocate isochronous bandwidth in the xHCI scheduler; the Android Java `UsbDeviceConnection.setInterface()` call does.
4. **Pipeline of 80 URBs** — the xHCI host controller needs many URBs in flight simultaneously; a small pipeline produces silence on commodity Android SoCs.
5. **32-bit PCM (alt=3) as default** — 32-bit is the standard transport size regardless of source bit depth; some DACs do not output audio on 16-bit alt settings.

The full investigation is captured in [`02-investigation-journey.md`](02-investigation-journey.md). Each of the bugs that produced silence — and how each was fixed — is recorded in [`04-five-critical-bugs.md`](04-five-critical-bugs.md).

## Architecture (high level)

```
ExoPlayer / Media3 decodes file → PCM (int or float, depending on path)
    ↓
UsbAudioSink (libs/decent-usb-audio-wrapper-media3)
    intercepts handleBuffer() before the delegate AudioTrack
    ↓
UsbAudioStream / NativeAudioEngine (libs/decent-usb-audio-driver, JNI)
    ↓
usb-audio-output.cpp (isochronous transfers via usbdevfs ioctl)
    ↓
/dev/bus/usb/XXX/YYY → USB DAC (bit-perfect)
```

The delegate `DefaultAudioSink` is kept alive (muted, routed to speaker) so that ExoPlayer's clock and state machine remain functional, but no audio data flows through it. See [`03-technical-architecture.md`](03-technical-architecture.md) for the detailed data path and [`docs/libs/ARCHITECTURE.md`](../libs/ARCHITECTURE.md) for the developer-facing pipeline diagram.

---

**Where to next**

- For integration into a Media3 app → [`docs/libs/GETTING_STARTED.md`](../libs/GETTING_STARTED.md)
- For the deep technical write-up of how each part works → [`03-technical-architecture.md`](03-technical-architecture.md)
- For the bug history that got us here → [`04-five-critical-bugs.md`](04-five-critical-bugs.md)
