---
name: DAC verification report
about: Confirm a USB DAC works (or doesn't) with the decent USB Audio driver
title: "[DAC] <Vendor> <Model> on <Phone> Android <ver>"
labels: ["dac-verification"]
---

## Hardware

- **Phone / DAP model:**
- **Android version (and API level):**
- **DAC vendor and model:**
- **Connection:** (USB-C direct / USB-C hub / USB-A adapter / OTG cable + powered hub / etc.)

## Result

- [ ] Bit-perfect confirmed
- [ ] Audio plays but possibly resampled
- [ ] No audio at all
- [ ] App crash / driver error

## Source

Which combination of the libraries are you using?

- [ ] `decent-usb-audio-driver` only
- [ ] `decent-usb-audio-driver` + `decent-usb-audio-wrapper-media3`
- [ ] All three (`+ decent-media3-decoder-flac`)

App version (commit hash if built from source): 

## Bit-perfect proof (if claiming bit-perfect)

Please paste the relevant lines from logcat showing:

- `UsbAudioDevice: Found USB audio device: <Vendor> <Model> (vendor=0x..., product=0x...)`
- `UsbAudioDevice: Auto-detected: clockSourceId=0x.., bestAlt=N, bestBits=NN`
- `UsbAudioDevice: setSampleRate(<rate> Hz): SUCCESS`
- `UsbAudioDevice: readClockValid: ... valid=1`
- `UsbAudioOutput: Start: rate=<rate> ch=2 bits=NN ring=80`
- `UsbAudioOutput: WriteRaw: ... inputBits=NN fpmf=<value>` (showing the source bit depth and the DAC feedback rate)

Optional but very helpful:

- Output of `adb shell dumpsys audio | grep -i usb` (should show **no** USB activity in AudioFlinger)
- Output of `adb shell ls /proc/asound/` (the kernel `snd-usb-audio` should **not** have created a card for the DAC)
- Raw USB descriptors: `adb shell lsusb -v -d <vid>:<pid>` (or attach as a file)

## Source rates tested

Which sample rates did you test, and what feedback rate did the DAC report?

| Source rate | DAC feedback rate (Hz) | Bit-perfect? |
|-------------|------------------------|--------------|
| 44.1 kHz    |                        |              |
| 48 kHz      |                        |              |
| 96 kHz      |                        |              |
| 192 kHz     |                        |              |
| 384 kHz     |                        |              |

## Anything weird?

Anything you noticed — startup glitches, pops, rate changes failing, etc. Logs welcome.
