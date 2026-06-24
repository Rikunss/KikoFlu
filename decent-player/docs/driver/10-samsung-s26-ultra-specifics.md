# 10 — Samsung Galaxy S26 Ultra Specific Notes

## Device Info
- Model: Samsung Galaxy S26 Ultra
- Android: 16 (API 36)
- Chipset: Qualcomm Snapdragon (with Qualcomm PAL audio layer)
- Kernel: Samsung custom with `snd-usb-audio` module

## Samsung Audio Architecture

Samsung adds several proprietary layers on top of Android's audio stack:

```
App AudioTrack
    ↓
AudioFlinger (AOSP)
    ↓
Qualcomm PAL (Platform Audio Layer) ← Samsung/Qualcomm proprietary
    ↓
Samsung Sound Effects (SoundBoosterPlus, SoundBoosterEQ, Dolby_FX, SoundAlivePlus)
    ↓
ALSA (snd-usb-audio for USB)
    ↓
USB DAC
```

When our driver is active, ALL of these layers are bypassed.

## UHQA (Ultra High Quality Audio)

Samsung's "UHQA" feature automatically upscales audio to the highest sample rate the DAC supports:
- Reads the DAC's ALSA capabilities
- Selects the highest supported rate (384kHz for the Cayin RU7)
- Configures `snd-usb-audio` at this rate
- All audio is resampled to 384kHz by the Samsung audio HAL

This is why the DAC showed 384kHz before our driver took over.

## Audio Policy Configuration

Samsung's USB audio policy (`/vendor/etc/audio/sku_alor/audio_policy_configuration.xml`):

```xml
<module name="usb" halVersion="2.0">
    <mixPorts>
        <mixPort name="usb_accessory output" role="source">
            <!-- NO AUDIO_OUTPUT_FLAG_DIRECT -->
            <!-- NO AUDIO_OUTPUT_FLAG_BIT_PERFECT -->
            <profile format="AUDIO_FORMAT_PCM_16_BIT"
                     samplingRates="44100" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
        </mixPort>
    </mixPorts>
</module>
```

Key findings:
- No `AUDIO_OUTPUT_FLAG_DIRECT` on USB mixPort
- No `AUDIO_OUTPUT_FLAG_BIT_PERFECT` on USB mixPort
- `getSupportedMixerAttributes()` doesn't expose 44100 Hz (HAL limitation)
- `MIXER_BEHAVIOR_BIT_PERFECT` not supported

## Qualcomm PAL Behavior

The PAL (Platform Audio Layer) aggressively manages USB devices:

```
PAL: Device: open: deviceCount 0 for device id 11 (PAL_DEVICE_OUT_USB_DEVICE)
PAL: Device: setMediaConfig: USB_AUDIO-RX rate 48000 ch 2 fmt 32
```

When our delegate AudioTrack is routed to SPEAKER (via `setPreferredDevice`), PAL stops touching the USB device:
```
AudioFlinger Output devices: 0x2 (AUDIO_DEVICE_OUT_SPEAKER)
PAL: (no USB activity)
```

## snd-usb-audio Race Condition

Timeline when USB DAC is connected:
```
T+0ms:    USB device detected by kernel
T+1ms:    snd-usb-audio kernel module binds
T+3ms:    snd-usb-audio configures DAC (384kHz UHQA)
T+100ms:  Android generates USB_DEVICE_ATTACHED intent
T+3000ms: Our handler receives the intent
T+3100ms: claimInterface(force=true) detaches snd-usb-audio
```

The ~3 second gap between kernel binding and our claim means the DAC is already configured at 384kHz. With the correct Clock Source ID (0x05), our subsequent SET_CUR successfully changes the clock. Without it (the old 0x0B bug), the clock stayed at 384kHz.

## Samsung Sound Effects

During normal playback, Samsung adds these effects to USB output:
- SoundBoosterPlus (session -32502)
- SoundBoosterEQ (session -32502)
- VoiceBooster (session -32502)
- Dolby_FX (session -32502)
- SoundAlivePlus (session -32502)

All running at 384kHz, 32-bit float, stereo.

Our bit-perfect driver **bypasses all of these**.

## Debugging on S26 Ultra

### No debugfs access (no root)
```bash
cat /sys/kernel/debug/usb/devices  # Permission denied
```
Cannot verify `#Iso` count without root. Use `dumpsys` and `sysfs` instead.

### Available verification methods
```bash
# Driver binding (works without root)
readlink /sys/bus/usb/devices/1-1:1.1/driver

# ALSA cards (works without root)
cat /proc/asound/cards

# AudioFlinger state
dumpsys media.audio_flinger | grep "Output devices:"

# PAL activity
logcat | grep "PAL:.*Device.*id 11"

# Our driver logs
logcat -s UsbAudioOutput UsbAudioManager AaudioAudioSink
```

## Tested Scenarios on S26 Ultra

| Scenario | Result |
|----------|--------|
| 44.1kHz/16-bit FLAC (Adele) | Bit-perfect, DAC shows 44.1kHz |
| 96kHz/24-bit FLAC (Dio) | Bit-perfect, DAC shows 96kHz |
| Track change (44.1→96kHz) | Works, ~100ms gap (PLL relock) |
| Long playback (>10 min) | Stable, inflight=8, zero errors |
| App background/foreground | Continues playing |
| Screen off | Continues playing |
