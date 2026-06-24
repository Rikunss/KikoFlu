# 09 — Future Work & Known Issues

## Priority 1: Stability

### Eliminate startup silence (~2 seconds)
The pipeline is pre-filled with silence URBs. The first real audio arrives ~2 seconds later when ExoPlayer starts delivering buffers. This could be reduced by:
- Using a smaller pipeline (4 URBs instead of 8) for initial fill
- Starting the pipeline only when the first real data buffer arrives
- Using a shorter silence duration per URB

### Handle stream destruction gracefully
When ExoPlayer calls `configure()` again (e.g., track change), the stream is destroyed and recreated. This causes a ~100ms gap. Improvements:
- If same sample rate, don't destroy/recreate — just keep streaming
- Pre-configure the next track's rate while current track plays (gapless)

### ENODEV recovery
Sometimes the fd becomes invalid (ENODEV errno=19) after extended playback. Causes:
- ExoPlayer re-configure cycle
- USB cable glitch
- System reclaiming the device

Need: automatic recovery that re-opens the device and resumes streaming.

## Priority 2: Audio Quality

### Feedback-based packet sizing
Currently we use a fractional accumulator for packet sizes. The DAC's feedback endpoint tells us the exact clock rate. We should adjust packet sizes based on feedback to prevent long-term drift:
```
Feedback says: 5.5127 frames/microframe
We're sending: 5.5125 average (from 44100/8000)
Drift: +0.0002 frames/microframe = +1.6 frames/second
After 1 hour: 5760 extra frames = ~130ms drift
```

### Double-buffering for writes
The current `nativeUsbAudioWrite` converts float→PCM and submits URBs on the same thread. A ring buffer with a separate submission thread would reduce jitter.

### DSD over PCM (DoP)
Alt setting 4 on the Cayin RU7 appears to be DSD. Implementing DoP framing would enable native DSD playback for .dff/.dsf files.

## Priority 3: Compatibility

### UAC1 support
Older/cheaper DACs use USB Audio Class 1.0. Key differences:
- Sample rate is set per-endpoint, not per-clock-source
- Full-speed USB (12 Mbps) with 1ms frames (not 125μs microframes)
- Different descriptor format

### Multiple DAC support
Currently assumes one USB audio device. Should handle:
- Multiple USB audio devices connected simultaneously
- Hot-plug/hot-unplug during playback
- DAC switching without app restart

### Samsung UHQA interference
On Samsung devices, `snd-usb-audio` binds before our handler and configures 384kHz. With the correct Clock Source ID, our SET_CUR overrides this. But the race condition adds ~3 seconds to startup. Could be improved by:
- Faster claim path (minimal work in USB_DEVICE_ATTACHED handler)
- Investigating if Android offers an earlier hook than USB_DEVICE_ATTACHED

## Priority 4: Features

### Bit-perfect indicator in UI
Show in the Audio Pipeline dialog:
- "Output API: USB Bit-Perfect" (instead of "AudioTrack")
- Clock source ID, alt setting, bit depth
- Feedback endpoint value (actual DAC clock)
- Pipeline depth (#URBs in flight)

### Volume control
System volume doesn't work in bit-perfect mode. Options:
- Software volume in the float→PCM conversion (not bit-perfect but convenient)
- USB Feature Unit volume control via SET_CUR to the Feature Unit entity
- Just disable volume and warn the user (current behavior)

### Sample rate display
Show the ACTUAL sample rate from the feedback endpoint, not just the configured rate. This proves to the user that the DAC is really running at the correct rate.

### Gapless playback
Pre-configure the next track's sample rate and alt setting while the current track plays. When the current track ends, seamlessly switch to the next stream without destroying the USB connection.

## Priority 5: Testing

### Automated testing
- Test with multiple DACs (Topping, FiiO, Shanling, iFi, etc.)
- Test all sample rates (44.1k through 384k)
- Test all bit depths (16, 24, 32)
- Test long-duration playback (hours) for drift/stability
- Test hot-plug/hot-unplug during playback
- Test track-to-track transitions

### DAC compatibility database
Build a database of tested DACs with:
- Clock Source entity ID
- Supported alt settings
- Any firmware quirks
- Feedback endpoint behavior

## Priority 6: Distribution

### Publish libraries to Maven Central
The three libraries in `libs/` are currently consumed via Gradle composite-build / project paths from sibling repositories. Once the public API has been exercised by community testing across multiple DACs and proven stable, the plan is to publish to Maven Central so consumers can drop them in via standard coordinates:

```kotlin
implementation("com.decent.usbaudio:decent-usb-audio-driver:<version>")
implementation("com.decent.usbaudio:decent-usb-audio-wrapper-media3:<version>")
implementation("com.decent.usbaudio:decent-media3-decoder-flac:<version>")
```

Until then, the recommended integration path is to add this repository as a sibling clone or git submodule and reference the modules via project paths in `settings.gradle.kts`.
