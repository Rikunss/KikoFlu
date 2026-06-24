# Architecture

## Audio Pipeline

There are three decoding paths, all bit-perfect. The `UsbAudioSink` routes automatically based on URI scheme and file format via `attachToPlayer()`.

### Path 1: FFmpeg (float, all formats)

```
Source File (FLAC/MP3/AAC/WAV)
    |
    v
FFmpeg Decoder (enableFloatOutput=true)
    |  int16/int24 -> float32 (/2^N, exact for 16/24-bit)
    v
ExoPlayer Render Thread
    |  calls handleBuffer() on UsbAudioSink
    v
+---------------------------------------------+
|  UsbAudioSink (ForwardingAudioSink)         |
|                                             |
|  1. Snapshot ByteBuffer                     |
|  2. Detect PCM_FLOAT encoding               |
|  3. Convert to FloatArray                   |
|  4. enqueue(FloatArray) to streaming thread  |
|  5. Feed delegate for ExoPlayer clock       |
+----------------+----------------------------+
                 | ArrayBlockingQueue (128 buffers)
                 v
+---------------------------------------------+
|  UsbStreamingThread (dedicated thread)      |
|                                             |
|  1. Poll AudioBuffer.FloatBuffer            |
|  2. Call usbStream.write(floatBuf)          |
|  3. Native reap provides DAC clock          |
|     backpressure (~1ms per URB)             |
+----------------+----------------------------+
                 | JNI
                 v
+---------------------------------------------+
|  usb-audio-output.cpp (native C++)          |
|                                             |
|  1. Float -> int32 conversion (x2^N, exact) |
|  2. Build ISO packets (8 per URB)           |
|  3. Submit to pre-allocated ring buffer     |
|  4. Reap completed URBs (FIFO order)        |
|  5. 80 URBs in flight = ~80ms pipeline      |
+----------------+----------------------------+
                 | ioctl(USBDEVFS_SUBMITURB)
                 v
+---------------------------------------------+
|  Linux Kernel (usbdevfs)                    |
|                                             |
|  xHCI host controller schedules ISO packets |
|  at 125us microframe intervals (USB 2.0     |
|  high-speed). ISO_ASAP flag ensures correct |
|  scheduling.                                |
+----------------+----------------------------+
                 | USB cable
                 v
             USB DAC
```

### Path 2: libFLAC (raw integer, FLAC only)

```
FLAC File
    |
    v
FlacExtractor (libFLAC, extractor level)
    |  Decodes to raw int: PCM_16BIT or PCM_32BIT (24-bit sign-extended)
    v
ExoPlayer Render Thread
    |  calls handleBuffer() on UsbAudioSink
    v
+---------------------------------------------+
|  UsbAudioSink (ForwardingAudioSink)         |
|                                             |
|  1. Snapshot ByteBuffer                     |
|  2. Detect non-float encoding (PCM_16BIT,   |
|     PCM_32BIT, PCM_24BIT)                   |
|  3. Copy raw bytes to ByteArray             |
|  4. enqueueRaw(ByteArray, encoding)         |
|  5. Feed delegate for ExoPlayer clock       |
+----------------+----------------------------+
                 | ArrayBlockingQueue (128 buffers)
                 v
+---------------------------------------------+
|  UsbStreamingThread (dedicated thread)      |
|                                             |
|  1. Poll AudioBuffer.RawBuffer              |
|  2. Call usbStream.writeRaw(bytes, enc)     |
|  3. Native reap provides DAC clock          |
|     backpressure (~1ms per URB)             |
+----------------+----------------------------+
                 | JNI
                 v
+---------------------------------------------+
|  usb-audio-output.cpp (native C++)          |
|                                             |
|  1. Integer shift: pad to DAC bit depth     |
|     (e.g., 24-bit << 8 -> 32-bit)          |
|  2. Build ISO packets (8 per URB)           |
|  3. Submit to pre-allocated ring buffer     |
|  4. 80 URBs in flight = ~80ms pipeline      |
+----------------+----------------------------+
                 | ioctl(USBDEVFS_SUBMITURB)
                 v
             USB DAC
```

**Key difference:** Path 2 has zero float math in the entire pipeline. The original integer samples from the FLAC file reach the DAC with only a lossless bit shift.

### Path 3: NativeAudioEngine (native C++ thread, FLAC only)

Bypasses the entire ExoPlayer audio pipeline. A single native thread handles decode → USB directly. Activated automatically for FLAC files when USB bit-perfect is enabled. Falls back to Path 1 or 2 for non-FLAC formats.

```
FLAC File (fd from Java)
    |
    v
+---------------------------------------------+
| NativeAudioEngine (C++, single pthread)     |
|                                             |
| AsyncBufferedDataSource                     |
|   - 8MB ring buffer with I/O thread         |
|   - readahead for sequential decode          |
|   - Direct pread64 for small reads (seek)    |
|       |                                     |
|       v                                     |
| FLACParser (xiph/flac)                      |
|   - Decode FLAC frame → raw PCM             |
|   - seekAbsolute for sample-accurate seek    |
|       |                                     |
|       v                                     |
| Bit-depth conversion                        |
|   - padInt16ToInt32 / padInt24ToInt32        |
|       |                                     |
|       v                                     |
| submitPcmToUrbs (USB isochronous output)    |
|   - Blocks on URB reap = natural backpressure|
|   - ~0.11ms per 1ms of audio                |
+---------------------------------------------+
           | ioctl(USBDEVFS_SUBMITURB)
           v
       USB DAC
```

**Key advantages over Path 1/2:**
- **Zero JNI in the hot path** — decode, convert, and USB all in one C++ thread
- **Zero Java queues** — submitPcmToUrbs blocks naturally on URB reap (DAC clock backpressure)
- **~10x headroom** on iBasso DX340 (was ~1.2x with ExoPlayer pipeline)
- **SD card optimized** — AsyncBufferedDataSource with direct pread64 for FLAC seek binary search

ExoPlayer remains active for playlist management, media session (lock screen, notifications), position tracking (via `engine.getPositionUs()`), and track transitions. A custom `NativeEngineAwareLoadControl` stops ExoPlayer from loading the same file in parallel (prevents FUSE I/O contention on SD cards).

**Automatic routing via `attachToPlayer()`:**

```
                    ┌─────────────────────────────┐
                    │    MediaItem URI             │
                    └──────────┬──────────────────┘
                               │
                    ┌──────────▼──────────────────┐
                    │   resolveTrackPath(uri)      │
                    └──────────┬──────────────────┘
                               │
         ┌────────────────┼────────────────────────┐
         │                │                        │
   file:// / bare   content://         http(s):// / sftp:// / ftp://
   path to .flac    MediaStore         streaming / seedbox
         │                │                        │
         ▼                ▼                        ▼
 NativeAudioEngine  NativeAudioEngine      ExoPlayer Pipeline
 (C++ thread)       (via fd)               (VfsDataSource or default)
              │                │                │
              └────────────────┴────────────────┘
                               │
                           USB DAC
```

All paths deliver bit-perfect audio. The routing is fully automatic and transparent to the integrating app. HTTP/HTTPS streams and SFTP (seedbox) use the ExoPlayer pipeline with FlacExtractor or FFmpeg. SFTP is handled by the built-in `SftpDataSource` (JSch with native offset seek) via `DecentDataSourceFactory`. All network streams are cached locally (500MB LRU) for instant seeks on replayed content.

## Modules

### `decent-usb-audio-driver` (Core)

Native USB Audio Class 2.0 driver. Communicates directly with the DAC via Linux usbdevfs isochronous transfers.

| Component | File | Role |
|-----------|------|------|
| `UsbAudioDevice` | `UsbAudioDevice.kt` | Device discovery, permissions, descriptor parsing, clock control |
| `UsbAudioStream` | `UsbAudioStream.kt` | JNI wrapper for native stream (create, start, write, writeRaw, stop, drain, release) |
| `UsbAudioPermissionHelper` | `UsbAudioPermissionHelper.kt` | Handle USB_DEVICE_ATTACHED intent, request permission, claim device |
| `NativeAudioEngine` | `NativeAudioEngine.kt` | Kotlin JNI wrapper for native FLAC decode → USB engine |
| Native driver | `usb-audio-output.cpp` | URB ring buffer, float->int conversion, raw int padding, ISO packet scheduling |
| Native engine | `native-audio-engine.cpp` | C++ FLAC decode loop, AsyncBufferedDataSource, JNI entry points |
| Native headers | `usb-audio-output.h`, `native-audio-engine.h` | Context structs, ring buffer slots, constants |

### `decent-usb-audio-wrapper-media3` (ExoPlayer Integration)

Drop-in `ForwardingAudioSink` for Media3/ExoPlayer apps.

| Component | File | Role |
|-----------|------|------|
| `UsbAudioSink` | `UsbAudioSink.kt` | ForwardingAudioSink with USB routing, NativeAudioEngine management, rate transitions, stale fd detection, tri-path handleBuffer (native engine / float / raw) |
| `NativeEngineAwareLoadControl` | `NativeEngineAwareLoadControl.kt` | LoadControl wrapper that stops ExoPlayer file loading when native engine is active (prevents SD card FUSE I/O contention) |
| `SftpDataSource` | `SftpDataSource.kt` | Media3 DataSource for SFTP streaming with JSch native offset seek (`ChannelSftp.get(path, null, offset)`) and SSH session caching |
| `DecentDataSourceFactory` | `DecentDataSourceFactory.kt` | Composite DataSource.Factory: routes SFTP to SftpDataSource, all else to default. Wraps both with `SimpleCache` (500MB LRU) for local caching of network streams |
| `UsbStreamingThread` | `UsbStreamingThread.kt` | Producer-consumer queue decoupling render thread from USB timing; supports FloatBuffer and RawBuffer types, pause/resume |
| `UsbAudioSinkConfig` | `UsbAudioSinkConfig.kt` | Configuration (bitPerfectEnabled, forceRouteToSpeaker) |
| `PcmUtils` | `PcmUtils.kt` | PCM encoding detection, bytes-per-sample, float conversion utilities |

### `decent-media3-decoder-flac` (Optional Native FLAC Decoder)

Native FLAC decoder built from xiph/flac source. Decodes FLAC at the extractor level.

| Component | File | Role |
|-----------|------|------|
| `FlacExtractor` | `FlacExtractor.java` | Decodes FLAC to raw integer PCM at extractor level (before renderer) |
| `LibflacAudioRenderer` | `LibflacAudioRenderer.java` | Marker class for runtime detection via reflection |
| `FlacLibrary` | `FlacLibrary.java` | Native library loader (libflacJNI.so) |

## Thread Model

### With NativeAudioEngine (FLAC files, USB bit-perfect)

```
Thread                    Responsibility                     Blocks on
---                       ---                                ---
NativeAudioEngine decode  FLAC decode → convert → USB        URB reap (~1ms per URB)
NativeAudioEngine I/O     Async file read (8MB buffer)       pread64 (~varies)
ExoPlayer Render          handleBuffer returns true (no-op)  N/A (idle)
ExoPlayer Loader          Blocked by LoadControl             N/A (stopped)
Main/UI                   Lifecycle, permissions              N/A
```

The native engine's decode thread and I/O thread are the only active threads during FLAC playback. ExoPlayer's render thread is idle (handleBuffer instantly returns true), and the loader is blocked by `NativeEngineAwareLoadControl`.

### Without NativeAudioEngine (non-FLAC, or fallback)

```
Thread                  Responsibility                    Blocks on
---                     ---                               ---
ExoPlayer Render        Decode -> handleBuffer -> enqueue  Delegate AudioTrack (~5ms)
UsbStreamingThread      Poll queue -> write to native      URB reap (~1ms per URB)
Main/UI                 Lifecycle, permissions             N/A
```

The render thread and USB thread are fully decoupled via the `ArrayBlockingQueue` (capacity 128). The render thread never blocks on USB. The USB thread never blocks on ExoPlayer.

The `UsbStreamingThread` uses a sealed class `AudioBuffer` with two variants (`FloatBuffer` and `RawBuffer`) for type-safe queueing of both paths through a single queue.

## Rate Transition Sequence

Matches the exact behavior observed via xHCI ftrace analysis on iBasso DX340:

```
1. stop()              Stop accepting new writes
2. drainUrbs()         Block until ALL in-flight URBs complete
3. setAlt(0)           xHCI Configure Endpoint: FREE old ISO ring
4. SET_CUR             Write new sample rate to Clock Source entity
5. CLOCK_VALID         GET_CUR verify clock locked (selector 0x02)
6. setAlt(0)           Defensive reset after clock change
7. setAlt(N)           xHCI Configure Endpoint: ALLOC new ISO ring
8. sleep(50ms)         DAC PLL lock time
9. start()             Begin submitting URBs on new ring
```

Steps 3, 6, and 7 MUST use Java `UsbDeviceConnection.setInterface()` -- the native `USBDEVFS_SETINTERFACE` ioctl does not trigger the xHCI Configure Endpoint Command properly.

## URB Pipeline Configuration

The driver uses a ring buffer of **80 URBs** (`USB_AUDIO_NUM_URBS = 80`), each carrying 8 ISO packets. This provides ~80ms of buffered audio in the USB pipeline — enough headroom for any scheduling jitter.

Both tested devices (Samsung S26 Ultra and iBasso DX340) handle 80 URBs without issues. Earlier investigations suggested Samsung's xHCI ring had a ~256 TRB limit (~20 URBs), but this was disproven — 80 URBs (requiring ~800 TRBs) work stable on the S26 Ultra.

## Bit-Perfect Math

### Float Normalization (FFmpeg -> Driver)

FFmpeg's libswresample normalizes integer PCM to float by dividing by `2^N`:

```
int16  ->  float:  sample / 32768.0f     (/2^15)
int24  ->  float:  sample / 8388608.0f   (/2^23)
```

The driver reconverts by multiplying by `2^N`:

```
float  ->  int16:  sample x 32768.0f  + clamp    (x2^15)
float  ->  int24:  sample x 8388608.0f + clamp   (x2^23)
float  ->  int32:  sample x 2147483648.0 + clamp (x2^31, via double)
```

This is **mathematically lossless** for 16-bit and 24-bit:
- `2^N` is exactly representable in float32 (power of 2)
- Division/multiplication by a power of 2 only changes the exponent -- zero rounding
- Float32 has 24-bit mantissa, exactly covering int16 (16-bit) and int24 (24-bit)

For 32-bit: float32 cannot represent all int32 values (24-bit mantissa < 31 bits needed). The `double` intermediate helps with scaling precision, but the int->float->int round-trip is inherently lossy for 32-bit.

### Raw Integer Path (libFLAC -> Driver)

When libFLAC delivers raw integer PCM, the native driver pads to the DAC's bit depth using integer shift:

```
16-bit source -> 32-bit DAC:  sample << 16  (0xABCD -> 0xABCD0000)
24-bit source -> 32-bit DAC:  sample << 8   (0xABCDEF -> 0xABCDEF00)
32-bit source -> 32-bit DAC:  pass-through
```

No float math at any point. The original bits are preserved exactly. This is trivially lossless by construction.

### Zero-Padding (Bit Depth Mismatch)

When the source bit depth is less than the DAC's bit depth, samples are zero-padded in the LSBs:

```
16-bit source -> 32-bit DAC:  0xABCD -> 0xABCD0000 (16 zeros in LSB)
24-bit source -> 32-bit DAC:  0xABCDEF -> 0xABCDEF00 (8 zeros in LSB)
```

This is standard bit-perfect practice per USB Audio Class 2.0 spec. The original bits are preserved in the MSBs. The DAC's internal converter ignores the zero LSBs.
