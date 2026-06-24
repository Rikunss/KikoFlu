# FLAC Decoding: libFLAC vs FFmpeg

Both libFLAC and FFmpeg can decode FLAC files in the bit-perfect USB audio pipeline. Neither is required -- the pipeline works with either one. Both paths are bit-perfect.

## Three paths, same result

### Path 1: FFmpeg (default, no extra dependency)

```
FLAC file -> FFmpeg decoder -> PCM_FLOAT (/2^N) -> float->int32 (x2^N) -> USB
```

- Uses the Jellyfin FFmpeg decoder (`org.jellyfin.media3:media3-ffmpeg-decoder`)
- Delivers `PCM_FLOAT` -- float32 with 24-bit mantissa precision
- The native USB driver reconverts to int32 using `x2^N` scaling
- **Bit-perfect**: the float round-trip is mathematically lossless for 16-bit and 24-bit sources
- Works for ALL audio formats (FLAC, MP3, AAC, WAV, etc.)

### Path 2: libFLAC (optional, zero float)

```
FLAC file -> FlacExtractor (native) -> raw int PCM -> integer shift -> USB
```

- Uses `com.decent.usbaudio:decent-media3-decoder-flac` (built from xiph/flac source)
- Decodes at the **extractor level** (FlacExtractor), before any renderer
- With `enableFloatOutput=false`: delivers `PCM_16BIT` (16-bit source) or `PCM_32BIT` (24-bit source, sign-extended to int32)
- The native USB driver pads to the DAC's bit depth using integer shift (`<< 8` or `<< 16`)
- **Bit-perfect**: zero float math in the entire pipeline -- lossless by construction
- Only works for FLAC files. Non-FLAC formats use the FFmpeg extension (Jellyfin) if present, or the Android built-in MediaCodec decoder.

### Path 3: NativeAudioEngine (native C++ thread, automatic for FLAC + USB)

```
FLAC file -> NativeAudioEngine (C++ thread) -> FLACParser -> raw PCM -> integer shift -> USB
```

- Uses `NativeAudioEngine` in the `decent-usb-audio-driver` module
- A single native C++ thread handles FLAC decode → bit-depth conversion → USB isochronous output
- **Zero JNI in the hot path** — ExoPlayer only controls play/pause/seek
- **~10x headroom** on weak CPUs (vs ~1.2x with ExoPlayer pipeline)
- Activated automatically when USB bit-perfect mode is enabled and the file is FLAC
- Falls back to Path 1 or 2 for non-FLAC formats

**This is the recommended path for FLAC playback via USB.** It was built to solve pipeline latency issues on devices with weak CPUs (e.g., iBasso DX340) where the ExoPlayer pipeline ran at ~1x real-time.

## Which should I use?

**All three paths are bit-perfect.** The choice is largely automatic:

| Aspect | FFmpeg only | FFmpeg + libFLAC | NativeAudioEngine |
|--------|------------|------------------|-------------------|
| FLAC quality | Bit-perfect (float x2^N) | Bit-perfect (zero float) | Bit-perfect (zero float, zero JNI) |
| Non-FLAC quality | Bit-perfect (float x2^N) | Same | Falls back to FFmpeg path |
| Pipeline layers | 6 (Java+JNI+C++) | 6 (Java+JNI+C++) | 1 (C++ only) |
| CPU headroom (weak device) | ~1.2x | ~1.2x | ~10x |
| Dependencies | 1 decoder lib | 2 decoder libs | libFLAC (included) |
| Activation | Always | Always | Automatic (FLAC + USB) |

**For USB bit-perfect FLAC playback:** NativeAudioEngine is activated automatically. No configuration needed beyond the standard integration.

**For non-FLAC formats:** ExoPlayer pipeline handles them (Path 1 or 2). The NativeAudioEngine only activates for FLAC files.

## How it works with ExoPlayer

When `com.decent.usbaudio:decent-media3-decoder-flac` is in the classpath, ExoPlayer auto-detects it. The `FlacExtractor` from the libFLAC module decodes FLAC at the **extractor level** (before the renderer), delivering raw integer PCM directly. This happens automatically -- no configuration needed beyond adding the dependency.

The `UsbAudioSink` handles both paths in `handleBuffer()`:
- When it receives `PCM_FLOAT` data (FFmpeg path), it converts to `FloatArray` and calls `enqueue()`
- When it receives non-float data (libFLAC path: `PCM_16BIT`, `PCM_32BIT`), it copies to `ByteArray` and calls `enqueueRaw()` with the encoding

The `UsbStreamingThread` uses a sealed class with `FloatBuffer` and `RawBuffer` variants to route each buffer type to the correct native write method (`write()` or `writeRaw()`).

When libFLAC is NOT in the classpath, ExoPlayer falls back to FFmpeg for FLAC decoding (if the Jellyfin FFmpeg decoder is present).

## Integration

### FFmpeg only (simplest)

```gradle
dependencies {
    implementation 'com.decent.usbaudio:decent-usb-audio-driver:<version>'
    implementation 'com.decent.usbaudio:decent-usb-audio-wrapper-media3:<version>'
    implementation 'org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1'
}
```

In `buildAudioSink()`:
```kotlin
.setEnableFloatOutput(true)  // FFmpeg needs float for 24-bit precision
```

### FFmpeg + libFLAC (zero float for FLAC)

```gradle
dependencies {
    implementation 'com.decent.usbaudio:decent-usb-audio-driver:<version>'
    implementation 'com.decent.usbaudio:decent-usb-audio-wrapper-media3:<version>'
    implementation 'com.decent.usbaudio:decent-media3-decoder-flac:<version>'
    implementation 'org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1'
}
```

In `buildAudioSink()`:
```kotlin
// Detect libFLAC at runtime
val hasLibFlac = try {
    Class.forName("androidx.media3.decoder.flac.LibflacAudioRenderer")
    true
} catch (_: ClassNotFoundException) { false }

// libFLAC delivers raw int — disable float so it doesn't convert.
// The FFmpeg extension (Jellyfin) still handles non-FLAC formats (MP3, AAC) via float when
// EXTENSION_RENDERER_MODE_PREFER is set.
.setEnableFloatOutput(!hasLibFlac)
```

No runtime toggle needed. Just add the dependency and set `enableFloatOutput` based on libFLAC detection. ExoPlayer and `UsbAudioSink` handle the rest.

## Technical details

### Why can't I switch between libFLAC and FFmpeg at runtime?

The media3 `FlacExtractor` decodes FLAC at the **extractor level**, not the renderer level. When libFLAC is in the classpath, `DefaultExtractorsFactory` loads `FlacExtractor` via reflection, and it decodes FLAC to raw PCM before any renderer is consulted. Removing `LibflacAudioRenderer` from the renderer list doesn't change this -- the extractor already decoded the audio.

To use FFmpeg for FLAC, you'd need to prevent `FlacExtractor` from loading. But without it, ExoPlayer has no extractor that can parse the FLAC container, resulting in `ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED`.

### Why enableFloatOutput=false with libFLAC?

When `enableFloatOutput=true`, even libFLAC's raw integer output gets converted to float by the DefaultAudioSink before reaching the `UsbAudioSink`. Setting it to `false` preserves the raw integer PCM all the way through:

| Setting | libFLAC output | DefaultAudioSink does | UsbAudioSink receives |
|---------|---------------|----------------------|----------------------|
| `enableFloatOutput=true` | PCM_32BIT (raw int) | Converts to PCM_FLOAT | Float (unnecessary round-trip) |
| `enableFloatOutput=false` | PCM_32BIT (raw int) | Passes through | Raw int (zero float) |

With `enableFloatOutput=false`, non-FLAC formats decoded by FFmpeg are also delivered as non-float. However, with `EXTENSION_RENDERER_MODE_PREFER`, FFmpeg still delivers float output for non-FLAC formats since that's how the Jellyfin FFmpeg extension works internally.

### Float precision for 16-bit and 24-bit

The FFmpeg float path uses IEEE 754 float32, which has a 24-bit mantissa. This means:
- **16-bit -> float -> 16-bit**: exact (16 < 24 mantissa bits)
- **24-bit -> float -> 24-bit**: exact (24 = 24 mantissa bits)
- **32-bit -> float -> 32-bit**: NOT exact (32 > 24 mantissa bits)

For 32-bit sources, the libFLAC path (integer only) is the only truly bit-perfect option.
