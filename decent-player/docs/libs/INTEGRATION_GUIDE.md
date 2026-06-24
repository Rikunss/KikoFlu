# Integration Guide

## Scenario 1: Wrapper + Driver (Media3 / ExoPlayer Apps)

This is the recommended approach for apps that use AndroidX Media3 or ExoPlayer. The wrapper provides a drop-in `ForwardingAudioSink` that handles all USB communication automatically.

### Step 1: Add Dependencies

> **Maven Central is not yet available** — the `com.decent:*` libraries
> have not been published as artifacts. While the API stabilizes through
> community DAC verification, integrate the libraries by cloning this
> repository as a sibling project and referencing them via project paths
> in your `settings.gradle.kts`:
>
> ```kotlin
> // settings.gradle.kts
> include(":decent-usb-audio-driver")
> include(":decent-usb-audio-wrapper-media3")
> include(":decent-media3-decoder-flac")
>
> project(":decent-usb-audio-driver").projectDir =
>     file("../decent-player/libs/decent-usb-audio-driver")
> project(":decent-usb-audio-wrapper-media3").projectDir =
>     file("../decent-player/libs/decent-usb-audio-wrapper-media3")
> project(":decent-media3-decoder-flac").projectDir =
>     file("../decent-player/libs/decent-media3-decoder-flac")
> ```
>
> Then in `app/build.gradle.kts`:
>
> ```kotlin
> dependencies {
>     implementation(project(":decent-usb-audio-driver"))
>     implementation(project(":decent-usb-audio-wrapper-media3"))
>     implementation(project(":decent-media3-decoder-flac"))
> }
> ```
>
> Once the libraries are published to Maven Central (planned after the
> public API has been validated by the community), the snippet below will
> work as standard coordinates:

```gradle
dependencies {
    // Core USB driver (native URB pipeline, JNI)
    implementation 'com.decent.usbaudio:decent-usb-audio-driver:<version>'

    // ExoPlayer/Media3 AudioSink wrapper
    implementation 'com.decent.usbaudio:decent-usb-audio-wrapper-media3:<version>'

    // FFmpeg decoder — REQUIRED for bit-perfect non-FLAC formats. The Android
    // built-in decoder truncates 24-bit to 16-bit. FFmpeg delivers genuine
    // float32 for all sources.
    implementation 'org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1'

    // Optional: Native FLAC decoder (zero-float integer path for FLAC files).
    // When present, FLAC is decoded to raw int PCM at the extractor level —
    // zero float math in the entire pipeline. When absent, FFmpeg handles
    // FLAC via the float path (also bit-perfect via x2^N round-trip).
    implementation 'com.decent.usbaudio:decent-media3-decoder-flac:<version>'

    // Media3 (your app probably already has these)
    implementation 'androidx.media3:media3-exoplayer:1.9.3'
    implementation 'androidx.media3:media3-common:1.9.3'
    implementation 'androidx.media3:media3-session:1.9.3'
}
```

### Step 2: AndroidManifest.xml — USB Device Handling

The app must register for USB device attach events. This makes Android show a permission dialog when a DAC is plugged in, and ensures your app claims the device before the kernel's `snd-usb-audio` driver binds (~3ms after connection).

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Optional: declare USB host support. Set required=false so the app
         still installs on devices without USB host capability. -->
    <uses-feature android:name="android.hardware.usb.host" android:required="false" />
    
    <application ...>
        <activity android:name=".MainActivity">
            
            <!-- Receive USB DAC connection events -->
            <intent-filter>
                <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
            </intent-filter>
            
            <!-- Filter: only USB Audio Class devices (class 1) -->
            <meta-data
                android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
                android:resource="@xml/usb_audio_device_filter" />
                
        </activity>
    </application>
</manifest>
```

Create `res/xml/usb_audio_device_filter.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Matches any USB Audio Class device (class 1 = Audio).
     This makes Android offer your app as a handler when a USB DAC is connected. -->
<resources>
    <usb-device class="1" />
</resources>
```

### Step 3: Handle USB Device Attach in Your Activity

When a USB DAC is connected, your Activity receives the `USB_DEVICE_ATTACHED` intent. You must handle it immediately to claim the device before the kernel's `snd-usb-audio` driver binds (~3ms window):

```kotlin
import com.decent.usbaudio.UsbAudioPermissionHelper

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Handle USB device attached (app launched by USB connect)
        handleUsbDeviceAttached(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Handle USB device attached (app already running)
        handleUsbDeviceAttached(intent)
    }

    private fun handleUsbDeviceAttached(intent: Intent) {
        // UsbAudioPermissionHelper handles:
        // 1. Checking if intent is USB_DEVICE_ATTACHED
        // 2. Finding the USB audio device
        // 3. Requesting permission if needed
        // 4. Claiming the device (openDevice) to prevent kernel driver binding
        UsbAudioPermissionHelper.handleIntent(applicationContext, intent)
    }
}
```

`UsbAudioPermissionHelper` is provided by the `usb-audio-driver` library. It handles the full flow: detect audio device, check/request permission, and claim the device.

### Step 4: Create RenderersFactory with UsbAudioSink

In your player service or activity, create a custom `DefaultRenderersFactory` that:
1. Forces FFmpeg decoder (for bit-perfect float output on non-FLAC formats)
2. Creates `UsbAudioSink` as the audio sink
3. Conditionally enables float output based on libFLAC availability
4. Keeps a reference to the sink for track bit depth updates

```kotlin
import com.decent.usbaudio.media3.UsbAudioSink
import com.decent.usbaudio.media3.UsbAudioSinkConfig
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.AudioCapabilities

class MyPlayerService : ... {

    // Keep a reference to set trackBitDepth on track transitions
    private var currentUsbSink: UsbAudioSink? = null
    
    private fun createRenderersFactory(): DefaultRenderersFactory {
        val factory = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableOffload: Boolean
            ): AudioSink {
                // Detect libFLAC at runtime. When present, FLAC files are decoded
                // at the extractor level (FlacExtractor), delivering raw integer PCM.
                val hasLibFlac = try {
                    Class.forName("androidx.media3.decoder.flac.LibflacAudioRenderer")
                    true
                } catch (_: ClassNotFoundException) { false }
                
                // enableFloatOutput logic:
                // - With libFLAC:    false — libFLAC delivers raw int for FLAC,
                //                    The FFmpeg extension still handles non-FLAC as float when
                //                    EXTENSION_RENDERER_MODE_PREFER is set.
                // - Without libFLAC: true  — FFmpeg delivers float32 for everything.
                //                    Required for 24-bit precision (Android's built-in
                //                    decoder truncates 24-bit to 16-bit).
                val useFloat = !hasLibFlac

                val delegate = DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(useFloat)
                    .setAudioCapabilities(AudioCapabilities.getCapabilities(context))
                    // Add your audio processors here if needed (EQ, balance, etc.)
                    // .setAudioProcessors(arrayOf(...))
                    .build()

                return UsbAudioSink(delegate, context).also {
                    currentUsbSink = it
                }
            }
        }
        
        // Force FFmpeg decoder. The Android built-in MediaCodec decoder
        // outputs PCM_16BIT for all sources, even 24-bit FLAC. FFmpeg outputs
        // genuine PCM_FLOAT with full precision.
        factory.setExtensionRendererMode(
            DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
        )
        
        return factory
    }
}
```

**How the three decoding paths work (ExoPlayer pipeline):**

| Format | libFLAC in classpath? | Decoder used | Output encoding | Float math? |
|--------|----------------------|-------------|----------------|-------------|
| FLAC | Yes | libFLAC (FlacExtractor) | `PCM_16BIT` or `PCM_32BIT` (raw int) | No |
| FLAC | No | FFmpeg | `PCM_FLOAT` | Yes (x2^N round-trip) |
| MP3, AAC, WAV | Either | FFmpeg | `PCM_FLOAT` | Yes (x2^N round-trip) |

The `UsbAudioSink` handles both paths automatically in `handleBuffer()`:
- `PCM_FLOAT` buffers are converted to `FloatArray` and enqueued via `enqueue()`
- Non-float buffers (raw int from libFLAC) are enqueued as `ByteArray` via `enqueueRaw()`

No app code is needed to distinguish the paths.

**Note on `buildAudioRenderers()`:** You do NOT need to override `buildAudioRenderers()` or remove any renderers. When libFLAC is in the classpath, ExoPlayer's `FlacExtractor` decodes FLAC at the extractor level (before any renderer is consulted), so renderer selection is irrelevant for FLAC files.

### Step 5: Build ExoPlayer with LoadControl Wrapper and Attach

```kotlin
// Wrap LoadControl to prevent ExoPlayer from reading the SD card
// when the native FLAC engine is handling decode+USB directly.
val loadControl = UsbAudioSink.wrapLoadControl(
    DefaultLoadControl.Builder()
        .setBufferDurationsMs(5000, 15000, 2000, 3000)
        .build()
) { currentUsbSink?.isNativeEngineActive == true }

val player = ExoPlayer.Builder(this)
    .setRenderersFactory(createRenderersFactory())
    .setLoadControl(loadControl)
    .build()

// Connect the sink to the player. This registers an internal Player.Listener
// that handles everything automatically:
// - Extracts file path from MediaItem URI (file://, content://, http://)
// - Creates/destroys NativeAudioEngine on track transitions
// - Advances to next track on engine EOF
// - Auto-detects bit depth from FLAC header
currentUsbSink?.attachToPlayer(player)
```

**That's it.** No manual `onMediaItemTransition` handling, no `runBlocking`, no `trackBitDepth` or `currentTrackPath` setting. The sink manages everything internally.

**How it works — automatic routing by URI scheme:**

| Source | URI scheme | Path | Decoder |
|--------|-----------|------|---------|
| Local FLAC (internal/SD) | `file://` or bare path | NativeAudioEngine (C++) | libFLAC native |
| Local FLAC (MediaStore) | `content://` | NativeAudioEngine (C++) | libFLAC native |
| HTTP/HTTPS FLAC stream | `http://`, `https://` | ExoPlayer pipeline | FlacExtractor (libFLAC) |
| HTTP/HTTPS lossy stream | `http://`, `https://` | ExoPlayer pipeline | FFmpeg |
| SFTP FLAC (seedbox) | `sftp://` | ExoPlayer pipeline (SftpDataSource + cache) | FlacExtractor (libFLAC) |
| Local non-FLAC | `file://` | ExoPlayer pipeline | FFmpeg float |

All paths output bit-perfect audio to the USB DAC. The NativeAudioEngine is used only for local FLAC files (where it eliminates JNI overhead and SD card I/O contention). For everything else, the ExoPlayer pipeline handles decode and routes to USB via the streaming thread.

**Streaming-service integration:**

The wrapper is fully compatible with any HTTP/HTTPS-based audio source. Any `DataSource` that ExoPlayer supports works automatically — the wrapper detects non-local URIs and uses the ExoPlayer pipeline. No special configuration needed. Your `MediaSource.Factory` handles authentication and buffering; the wrapper handles USB output.

Tested transitions:
- Local FLAC → HTTP FLAC stream → Local FLAC (engine ↔ pipeline ↔ engine)
- Cross-rate transitions during streaming (44.1kHz HTTP → 192kHz local)
- Seamless USB reconfiguration on rate change

**SFTP seedbox playback (built-in):**

The wrapper includes `SftpDataSource` powered by JSch, supporting `sftp://` URIs with native offset seek. Use `DecentDataSourceFactory` to enable it (also adds local caching for all network streams):

```kotlin
val mediaSourceFactory = DefaultMediaSourceFactory(
    DecentDataSourceFactory(context)  // routes sftp:// to JSch, caches all network streams
)
val player = ExoPlayer.Builder(context)
    .setMediaSourceFactory(mediaSourceFactory)
    .build()
```

Then play from a seedbox:
```kotlin
val item = MediaItem.fromUri("sftp://user:pass@host/path/to/song.flac")
player.setMediaItem(item)
player.prepare()
player.play()
```

Features:
- **Native offset seek**: `ChannelSftp.get(path, null, offset)` sends `SSH_FXP_READ` at exact byte position — no sequential skip
- **SSH session caching**: session reused across seeks (only SFTP channel reopened when stale)
- **SFTP chroot handling**: automatic retry with relative path if absolute fails
- **Local cache**: 500MB LRU via ExoPlayer's `SimpleCache` — replayed content serves from disk instantly
- **Path safety**: manual URI parser accepts `[]`, `()`, CJK characters in filenames

Tested with FLAC from remote seedbox at 44.1kHz through iBasso DX340 + Cayin RU7.

The `wrapLoadControl()` prevents ExoPlayer from reading the audio file when the native engine is active, avoiding SD card FUSE I/O contention (measured: 1.4 GB → 18 MB in 30 seconds).

### Step 6: Configuration Options (Optional)

The default config works for most cases. Customize if needed:

```kotlin
val config = UsbAudioSinkConfig(
    bitPerfectEnabled = true,        // Enable USB output (default: true)
    forceRouteToSpeaker = true       // Route muted delegate to speaker instead of USB
                                     // (prevents AudioFlinger/Qualcomm PAL conflicts)
)

val sink = UsbAudioSink(delegate, context, config)
```

### Complete Working Example

See the Felicity Music Player integration in `driver/Felicity/`:
- **`FelicityPlayerService.kt`** `buildAudioSink()`: Full processor chain, libFLAC detection, conditional `enableFloatOutput`, and `UsbAudioSink` creation
- **`FelicityPlayerService.kt`** `onMediaItemTransition()`: Synchronous bit depth propagation via `runBlocking(Dispatchers.IO)`
- **`MainActivity.kt`** `handleUsbDeviceAttached()`: `UsbAudioPermissionHelper.handleIntent()` for USB device claiming

### Lifecycle Details

The `UsbAudioSink` manages both the USB stream and NativeAudioEngine lifecycle automatically:

| ExoPlayer Event | What UsbAudioSink Does |
|-------|-------------|
| `configure(format)` | Opens USB device, claims interface, sets sample rate via UAC2 sequence. If FLAC + currentTrackPath set → creates NativeAudioEngine (paused). If non-FLAC → starts streaming thread. |
| Track change (same rate) | If engine running same track → defers reconfiguration. If new track → destroys old engine, creates new one. |
| Track change (different rate) | Full UAC2 transition: stop engine/thread → drain URBs → setAlt(0) → SET_CUR → CLOCK_VALID → setAlt(0) → setAlt(N) → sleep(50ms) → start |
| `handleBuffer()` | If NativeAudioEngine active → captures `presentationTimeUs` for position, seeks engine, returns true (ignores data). If no engine → routes to streaming thread (float or raw path). |
| `flush()` | Temporarily unblocks LoadControl (sets `isNativeEngineActive=false`) so ExoPlayer loads one post-seek chunk. Engine seek happens in next `handleBuffer()`. |
| `play()` / `pause()` | Forwards to NativeAudioEngine.resume()/pause(). Respects `engineNeedsInitialSeek` flag. |
| `getCurrentPositionUs()` | If engine active → `windowOffsetUs + engine.getPositionUs()`. If streaming thread → `startMediaTimeUs + framesWritten`. |
| `isEnded()` | If engine running → false. If engine finished → delegates to super (triggers track transition). |
| `reset()` | USB stream **survives** — ExoPlayer calls reset() frequently, killing USB here causes audio to briefly route to speaker |
| `release()` | Full cleanup: stop engine, stop streaming thread, drain all URBs, release native resources |
| Stale fd detected | setAlt(0) fails → auto close/reopen USB device with fresh fd |

### enableFloatOutput: When and Why

With `enableFloatOutput = true` (no libFLAC), the FFmpeg decoder delivers PCM as float32 for **all** sources:

| Source File | Without Float | With Float |
|-------------|--------------|------------|
| 16-bit FLAC/MP3 | PCM_16BIT (correct) | PCM_FLOAT (16->float via /2^15, lossless) |
| 24-bit FLAC | **PCM_16BIT (truncated!)** | PCM_FLOAT (24->float via /2^23, lossless) |
| 32-bit WAV | **PCM_16BIT (truncated!)** | PCM_FLOAT (32->float, lossy -- float32 has only 24-bit mantissa) |

**Without float output and without libFLAC, 24-bit sources lose 8 bits of precision before reaching the USB driver.**

With `enableFloatOutput = false` AND libFLAC in classpath, FLAC files get raw integer PCM:

| Source File | Decoder | Output | Float math? |
|-------------|---------|--------|-------------|
| 16-bit FLAC | libFLAC (FlacExtractor) | PCM_16BIT | None |
| 24-bit FLAC | libFLAC (FlacExtractor) | PCM_32BIT (sign-extended) | None |
| 24-bit MP3 | FFmpeg | PCM_FLOAT | Yes (lossless x2^N) |

The reconversion in the native C++ driver uses `x2^N` scaling with clamping, which is the exact inverse of FFmpeg's `/2^N` normalization. The round-trip is mathematically lossless for 16-bit and 24-bit sources.

---

## Scenario 2: Driver Only (Non-Media3 Apps)

If your app doesn't use ExoPlayer/Media3, you can use the USB driver library directly. You manage the audio pipeline and USB communication yourself.

### Add Dependency

> See the Maven note in [Step 1](#step-1-add-dependencies) — until publication, integrate via project paths.

```gradle
dependencies {
    implementation 'com.decent.usbaudio:decent-usb-audio-driver:<version>'
}
```

### AndroidManifest.xml

Same USB setup as Scenario 1 (see Step 2 above).

### Open the USB Device

```kotlin
import com.decent.usbaudio.UsbAudioDevice

val usbAudioDevice = UsbAudioDevice.getInstance(context)

// Find a connected USB Audio Class 2.0 device
val usbDevice = usbAudioDevice.findUsbAudioDevice() ?: return
val deviceInfo = usbAudioDevice.openDevice(usbDevice) ?: return

// deviceInfo contains everything auto-detected from USB descriptors:
//   fd                    — file descriptor for usbdevfs ioctls
//   interfaceId           — audio streaming interface number (typically 1)
//   endpointOutAddress    — isochronous OUT endpoint (e.g., 0x01)
//   endpointFeedbackAddress — async feedback IN endpoint (e.g., 0x81)
//   maxPacketSize         — from endpoint descriptor (e.g., 776 bytes for Cayin RU7)
//   bestAltSetting        — highest bit depth alt setting (e.g., 3 for 32-bit)
//   bestBitDepth          — highest supported bit depth (e.g., 32)
//   clockSourceId         — UAC2 Clock Source entity ID (e.g., 0x05)
```

### Configure Sample Rate (UAC2 Transition Sequence)

This sequence must be followed exactly. It was confirmed via xHCI ftrace analysis:

```kotlin
// Step 1: FREE old ISO rings
usbAudioDevice.setAltSetting(0)

// Step 2: SET_CUR — write new sample rate to Clock Source entity
usbAudioDevice.setSampleRate(96000)

// Step 3: GET_CUR(CLOCK_VALID_CONTROL) — verify DAC clock locked
val clockValid = usbAudioDevice.readClockValid()  // should return true

// Step 4: Defensive reset (required after SET_CUR per xHCI protocol analysis)
usbAudioDevice.setAltSetting(0)

// Step 5: ALLOC new ISO rings
usbAudioDevice.setAltSetting(deviceInfo.bestAltSetting)

// Step 6: Wait for DAC PLL to lock onto new frequency
Thread.sleep(50)
```

**Why this exact sequence?** The xHCI host controller uses Configure Endpoint Commands to allocate/free isochronous transfer rings. Sending URBs on a stale ring corrupts the host controller state. xHCI ftrace analysis confirms this exact sequence with two setAlt(0) calls -- the second one after SET_CUR is critical for xHCI ring cleanup.

### Create and Start a Stream

```kotlin
import com.decent.usbaudio.UsbAudioStream

val stream = UsbAudioStream(
    fd = deviceInfo.fd,
    interfaceId = deviceInfo.interfaceId,
    endpointOut = deviceInfo.endpointOutAddress,
    endpointFeedback = deviceInfo.endpointFeedbackAddress,
    sampleRate = 96000,
    channelCount = 2,
    bitDepth = 32,               // must match the alt setting's bit depth
    maxPacketSize = deviceInfo.maxPacketSize
)

if (!stream.isReady) { /* handle error */ }
stream.start()
```

### Write Audio Data

Two write methods are available:

```kotlin
// ── Float path (FFmpeg, or any source delivering float32 PCM) ──

// Write interleaved float32 PCM [-1.0, 1.0].
// The native layer converts to the target bit depth (int16/int24/int32)
// and manages the 80-URB isochronous pipeline automatically.
// This call BLOCKS when the pipeline is full — natural backpressure
// matching the DAC's hardware clock rate.
val floatPcm = FloatArray(8192)  // 4096 stereo frames
// ... fill with your audio data ...
stream.write(floatPcm)

// ── Raw integer path (libFLAC, or any source delivering raw int PCM) ──

// Write raw integer PCM bytes directly — zero float conversion.
// The native layer pads to the DAC's bit depth using integer shift
// operations (<< 8 or << 16). True bit-perfect by construction.
val rawBytes = ByteArray(16384)  // raw PCM bytes
// ... fill with your audio data ...
stream.writeRaw(rawBytes, C.ENCODING_PCM_24BIT)  // or PCM_16BIT, PCM_32BIT
```

For continuous streaming, call `write()` or `writeRaw()` in a loop. Each call blocks for approximately the audio duration of the buffer (~85ms at 96kHz for 8192 samples). This is the DAC's clock driving the pace.

### Stop and Release

```kotlin
// Stop accepting new writes
stream.stop()

// CRITICAL: Drain ALL in-flight URBs before calling setAlt(0).
// The xHCI Configure Endpoint Command triggered by setAlt(0) frees the
// isochronous ring. If URBs are still pending, the host controller state
// becomes corrupted and subsequent transfers will fail silently.
val drained = stream.drainUrbs()

// Release native resources (ring buffer, context)
stream.release()

// Do NOT close the device connection between tracks!
// Closing/reopening corrupts the xHCI endpoint state after ~3 cycles.
// Keep the same UsbDeviceConnection and fd for the entire session.
// Use setAlt(0) -> SET_CUR -> setAlt(N) to change rate on the same fd.
```

### Stale Connection Detection

If the app was killed and restarted, the cached fd may be dead:

```kotlin
// Try setAlt(0) — if it fails, the connection is stale
if (!usbAudioDevice.setAltSetting(0)) {
    // Close and reopen
    usbAudioDevice.closeDevice()
    val freshInfo = usbAudioDevice.openDevice(usbDevice)
    // Recreate stream with fresh fd
}
```

### Important Notes

- **Always drain URBs before setAlt(0)** — pending URBs corrupt the xHCI host controller state
- **Keep the device connection open** between tracks — close/reopen corrupts xHCI after ~3 cycles
- **Use Java `setInterface()`** for alt setting changes — the native `USBDEVFS_SETINTERFACE` ioctl does NOT trigger the xHCI Configure Endpoint Command that properly allocates/frees ISO bandwidth
- **URB pipeline** — 80 URBs in flight (~80ms buffer). Both Samsung S26 Ultra and iBasso DX340 handle this without issues
- **Float conversion math** — if converting float->int yourself, use `x2^N` (not `x(2^N-1)`) to match FFmpeg's `/2^N` normalization. Use `double` for 32-bit scaling since float32 can't represent 2^31 exactly
