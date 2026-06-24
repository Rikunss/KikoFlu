# Cayin RU7 USB Audio Analysis — Samsung Galaxy S26 Ultra (Android 16, API 36)

Data collected 2026-04-03 while a a direct USB driver was playing via USB.

## USB Device Descriptors

- **Manufacturer**: Cayin
- **Product**: Cayin RU7
- **Version**: 2.01 (USB Audio Class 2.0, protocol=32)
- **Device address**: `/dev/bus/usb/001/002`
- **ALSA**: card=1, device=0

### Interfaces

| Interface | Alt Setting | Class | Subclass | Protocol | Description |
|-----------|------------|-------|----------|----------|-------------|
| 0 | 0 | 1 (Audio) | 1 (AudioControl) | 32 (UAC2) | Control interface |
| 1 | 0 | 1 (Audio) | 2 (AudioStreaming) | 32 (UAC2) | Playback (zero-bandwidth) |
| 1 | 1 | 1 (Audio) | 2 (AudioStreaming) | 32 (UAC2) | Playback alt 1 |
| 1 | 2 | 1 (Audio) | 2 (AudioStreaming) | 32 (UAC2) | Playback alt 2 |
| 1 | 3 | 1 (Audio) | 2 (AudioStreaming) | 32 (UAC2) | Playback alt 3 |
| 1 | 4 | 1 (Audio) | 2 (AudioStreaming) | 32 (UAC2) | Playback alt 4 |

### Endpoints (all alt settings share same structure)

| Endpoint | Address | Direction | Type | Attributes | Max Packet Size | Interval |
|----------|---------|-----------|------|------------|-----------------|----------|
| 1 | 0x01 | OUT (0) | Isochronous | 5 (async) | 776 bytes | 1 (125μs) |
| 1 | 0x81 | IN (128) | Isochronous | 17 (feedback) | 4 bytes | 4 |

**Key observations:**
- Attributes=5 → Isochronous, Asynchronous mode (DAC has its own clock, sends feedback)
- Attributes=17 → Isochronous, Feedback endpoint
- Max packet size 776 bytes = enough for 32-bit stereo at 384kHz (384000 × 4 bytes × 2ch / 8000 μframes = 384 bytes per μframe, but 776 allows for variable packet sizes)
- 4 alternate settings likely correspond to different bit depths (16/24/32-bit + possibly DSD)

## HAL-Reported Formats (via getSupportedMixerAttributes API)

All `MIXER_BEHAVIOR_DEFAULT` — **NO BIT_PERFECT support**

| Bit Depth | Sample Rates |
|-----------|-------------|
| PCM 16-bit | 48000, 88200, 96000, 176400, 192000, 352800, 384000 |
| PCM 24-bit | 48000, 88200, 96000, 176400, 192000, 352800, 384000 |
| PCM 32-bit | 48000, 88200, 96000, 176400, 192000, 352800, 384000 |

**44100 Hz is NOT listed** — explains HAL resampling of CD-quality content.

Channel masks: `0x0003` (Stereo) and `0x80000003` (unspecified stereo variant)

## Samsung Audio Policy (USB Module)

From `/vendor/etc/audio/sku_alor/audio_policy_configuration.xml`:

```xml
<module name="usb" halVersion="2.0">
    <mixPorts>
        <mixPort name="usb_accessory output" role="source">
            <!-- NO flags="AUDIO_OUTPUT_FLAG_DIRECT" -->
            <!-- NO flags="AUDIO_OUTPUT_FLAG_BIT_PERFECT" -->
            <profile format="AUDIO_FORMAT_PCM_16_BIT"
                     samplingRates="44100" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
        </mixPort>
    </mixPorts>
</module>
```

**No DIRECT or BIT_PERFECT profiles on USB.** The official API paths are dead.

## USB Protocol Behavior Analysis (AudioFlinger Dump)

### Key finding: Direct USB driver bypasses AudioFlinger entirely

- Direct USB driver PID 23417, UID 10404
- **Zero active AudioTracks in any AudioFlinger output thread** while playing
- USB device permission granted: `device_name=/dev/bus/usb/001/002, uids=10404`
- Log confirms: `m_useUSBAudio = true`
- Uses a "ghost" AudioTrack for MediaSession/notification integration only
- On pause/resume: `AudioTrack: stop(422)` / `restoreTrack_l(423): dead IAudioTrack, PCM, creating a new one from setOutputDevice()`

### AudioFlinger USB threads (Samsung-created, not the direct USB driver)

- `AudioOut_145` (MIXER): 384000 Hz, PCM 32-bit, **Standby=yes** (not used by direct USB driver)
- `AudioOut_13D` (DIRECT): 8000 Hz, PCM Float, **Standby=yes** (not used by direct USB driver)
- Samsung effects on USB mixer: SoundBoosterPlus, SoundBoosterEQ, VoiceBooster, Dolby_FX, SoundAlivePlus

### Conclusion

The direct USB driver communicates directly via UsbManager -> UsbDeviceConnection -> isochronous transfers. It does NOT use AudioFlinger, AudioTrack, AAudio, or any Android audio framework for actual sound output.
