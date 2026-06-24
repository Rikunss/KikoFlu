# 07 — Verification & Diagnostics: Proving Bit-Perfect

## How to Verify the Driver is Active

### Quick Check (one command)
```bash
adb shell "readlink /sys/bus/usb/devices/1-1:1.1/driver"
```
- `usbfs` → OUR DRIVER (bit-perfect)
- `snd-usb-audio` → KERNEL DRIVER (AudioFlinger, resampled)

### Full Verification Script
```bash
echo "=== Driver ==="
adb shell "readlink /sys/bus/usb/devices/1-1:1.1/driver"

echo "=== ISO Bandwidth ==="
adb shell "cat /sys/kernel/debug/usb/devices" 2>/dev/null | grep "#Iso"

echo "=== ALSA (should be empty for USB) ==="
adb shell "cat /proc/asound/cards" | grep -i usb

echo "=== AudioFlinger (should NOT show USB) ==="
adb shell "dumpsys media.audio_flinger" | grep "Output devices:"

echo "=== Our driver logs ==="
adb logcat -d -s UsbAudioOutput | grep "Write:.*inflight" | tail -5
```

### Expected Output When Bit-Perfect
```
Driver:    usbfs
#Iso:      8 (or more)
ALSA:      (no USB cards)
Flinger:   SPEAKER only
Logs:      inflight=8, fb=44101.6Hz (or matching source rate)
```

## Diagnostic Metrics

### Pipeline Health
```bash
# Should show only "8" — any other value indicates pipeline instability
adb logcat -d | grep "inflight=" | awk -F'inflight=' '{print $2}' | awk '{print $1}' | sort | uniq -c
```

### Clock Stability (feedback endpoint)
```bash
# Should show consistent values within ±5 Hz of target rate
adb logcat -d | grep "fb=" | awk -F'fb=' '{print $2}' | awk -F'Hz' '{print $1}' | sort | uniq -c
```

### Frame Delivery Rate
```bash
# Should show ~1.02 sec between reports (1 report per sampleRate frames)
adb logcat -d | grep "Write:.*frames" | awk '{print $2}' | tail -10
```

### Error Check
```bash
# Should return nothing during active playback
adb logcat -d | grep "UsbAudioOutput:" | grep "FAILED"
```

## Samsung S26 Ultra — Full Verification Report (2026-04-03 18:18)

```
Driver binding:       usbfs (our driver)
ISO bandwidth:        #Iso=8 (pipeline active)
ALSA USB card:        none (kernel not controlling)
AudioFlinger output:  SPEAKER only (not USB)
PAL USB activity:     zero
Sample rate:          44100 Hz (SET_CUR confirmed, GET_CUR confirmed)
Feedback:             5.5126-5.5127 frames/mf = 44100.6-44101.6 Hz
Pipeline inflight:    578 samples, 100% at 8 (zero drops)
URB errors:           zero during playback
Frame timing:         ~1.023 sec average (consistent)
Clock drift:          <0.004% (44100.6-44101.6 vs 44100.0)
Stream restarts:      only between tracks (expected)
Auto-detection:       clockSourceId=0x5, bestAlt=3, bestBits=32
```

## Known Limitations

1. **~2 second silence at stream start** — pipeline pre-fill with silence URBs
2. **Pop/click on track change** — DAC PLL relocking when sample rate changes
3. **No gapless playback** — stream is destroyed/recreated between tracks
4. **System volume does not work** — audio bypasses the mixer entirely
5. **DSP/EQ disabled** — bit-perfect means no processing
6. **Only USB output** — speaker/Bluetooth use normal AudioTrack path

## Interpreting the Feedback Endpoint

The feedback value is a 16.16 fixed-point number representing frames per microframe:

```
Raw bytes: 33 83 05 00 (little-endian)
Raw value: 0x00058333
As float:  0x00058333 / 65536.0 = 5.5127
As Hz:     5.5127 × 8000 = 44101.6 Hz
```

Expected values:
| Source Rate | Expected | Acceptable Range |
|-------------|----------|------------------|
| 44100 Hz | 5.5125 | 5.510 — 5.515 |
| 48000 Hz | 6.0000 | 5.998 — 6.002 |
| 88200 Hz | 11.025 | 11.020 — 11.030 |
| 96000 Hz | 12.000 | 11.998 — 12.002 |
| 192000 Hz | 24.000 | 23.998 — 24.002 |
| 384000 Hz | 48.000 | 47.998 — 48.002 |
