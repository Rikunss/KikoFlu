# 11 — Packaging the Driver as a Standalone Android Library

**Purpose:** This document captures the design of the standalone, framework-agnostic Android libraries that ship in `libs/`. The bit-perfect USB Audio driver was originally prototyped inside a fork of the [Felicity](https://github.com/Hamza417/Felicity) music player (now living in `driver/Felicity/` purely as a proof-of-concept harness); its core was then extracted into the three independent modules under `libs/` so that any Android app — including the future standalone `decent-player` application built from scratch — can consume it without taking on a dependency on Felicity.

---

## Vision

```
┌─────────────────────────────────────────────────────────┐
│                  Any Android App                         │
│  (DecentPlayer, custom player, Flutter, React Native)   │
│                                                          │
│    ┌──────────────┐        ┌─────────────────────┐      │
│    │  Your Audio   │        │  usb-audio-media3   │      │
│    │  Pipeline     │        │  (optional module)   │      │
│    │  (any decoder)│        │  ExoPlayer AudioSink │      │
│    └──────┬───────┘        └──────────┬──────────┘      │
│           │                           │                  │
│           ▼                           ▼                  │
│    ┌──────────────────────────────────────────────┐      │
│    │           usb-audio-driver (core)             │      │
│    │                                                │      │
│    │  UsbAudioDevice.open(context)                  │      │
│    │  UsbAudioStream.write(floatPcm)                │      │
│    │  UsbAudioStream.close()                        │      │
│    │                                                │      │
│    │  ┌─────────────┐  ┌──────────────────────┐    │      │
│    │  │ Kotlin API   │  │ Native (JNI/C++)     │    │      │
│    │  │              │  │                      │    │      │
│    │  │ UsbAudioDev  │  │ usb-audio-output.cpp │    │      │
│    │  │ UsbAudioStrm │  │ ISO URB pipeline     │    │      │
│    │  │ DescParser   │  │ Float→PCM convert    │    │      │
│    │  └─────────────┘  └──────────────────────┘    │      │
│    └──────────────────────────────────────────────┘      │
│                          │                                │
└──────────────────────────┼────────────────────────────────┘
                           │ usbdevfs ioctl
                           ▼
                    ┌──────────────┐
                    │  USB DAC     │
                    │ (any UAC2)   │
                    └──────────────┘
```

## Module Structure

The library is split into **two modules** — a core that has zero Android audio framework dependency, and an optional Media3 integration.

```
decentplayer-usb-audio/
├── usb-audio-driver/              # Core library (STANDALONE)
│   ├── build.gradle
│   ├── src/main/
│   │   ├── AndroidManifest.xml    # USB permission, no activities
│   │   ├── jni/
│   │   │   ├── CMakeLists.txt
│   │   │   ├── usb-audio-output.cpp
│   │   │   └── usb-audio-output.h
│   │   ├── java/com/decentplayer/usbaudio/
│   │   │   ├── UsbAudioDevice.kt          # Device lifecycle (detect, open, close)
│   │   │   ├── UsbAudioStream.kt          # Stream lifecycle (configure, write, stop)
│   │   │   ├── UsbAudioDeviceInfo.kt       # Data class with detected capabilities
│   │   │   ├── UsbAudioDescriptorParser.kt  # Clock source + alt setting parser
│   │   │   ├── UsbAudioPermissionHelper.kt  # Permission request helper
│   │   │   └── UsbAudioException.kt         # Typed exceptions
│   │   └── res/xml/
│   │       └── usb_audio_device_filter.xml
│   └── consumer-rules.pro
│
├── usb-audio-media3/              # Optional ExoPlayer/Media3 integration
│   ├── build.gradle               # depends on usb-audio-driver + media3
│   └── src/main/java/com/decentplayer/usbaudio/media3/
│       └── UsbAudioSink.kt        # AudioSink implementation using core library
│
└── sample-app/                    # Demo app
    └── ...
```

### Dependencies

**usb-audio-driver (core):**
- `androidx.core:core-ktx` (only for Context extensions)
- Android SDK USB Host API (`android.hardware.usb.*`)
- NDK (for JNI/C++ native code)
- **Zero** ExoPlayer/Media3 dependency
- **Zero** AudioTrack/AudioFlinger dependency

**usb-audio-media3 (optional):**
- `usb-audio-driver` (core)
- `androidx.media3:media3-exoplayer`

---

## Core Library Public API

### UsbAudioDevice — Device Lifecycle

```kotlin
package com.decentplayer.usbaudio

/**
 * Represents a USB Audio Class 2.0 device.
 *
 * Usage:
 *   val device = UsbAudioDevice.getInstance(context)
 *   val info = device.open()  // claims interface, parses descriptors
 *   val stream = device.createStream(sampleRate = 44100, channelCount = 2)
 *   stream.write(floatPcmData)
 *   stream.close()
 *   device.close()
 */
class UsbAudioDevice private constructor(context: Context) {

    companion object {
        /** Singleton — one USB device per app process. */
        fun getInstance(context: Context): UsbAudioDevice

        /**
         * Call from Activity.onCreate() or onNewIntent() when receiving
         * USB_DEVICE_ATTACHED intent. Claims the device immediately,
         * preventing the kernel snd-usb-audio driver from configuring it.
         */
        fun handleUsbDeviceAttached(context: Context, intent: Intent): Boolean
    }

    /** Discover connected USB audio devices. */
    fun findDevice(): UsbDevice?

    /** Check if we have permission to access the device. */
    fun hasPermission(): Boolean

    /** Request permission from the user (shows system dialog). */
    fun requestPermission(callback: (granted: Boolean) -> Unit)

    /** Open the device, claim interfaces, parse descriptors.
     *  Returns device capabilities (sample rates, bit depths, etc). */
    fun open(): UsbAudioDeviceInfo

    /** Create an audio stream at the specified format. */
    fun createStream(
        sampleRate: Int,
        channelCount: Int = 2,
        bitDepth: Int = 0  // 0 = auto-detect best
    ): UsbAudioStream

    /** Close the device and release all resources. */
    fun close()

    /** True if the device is open and ready. */
    val isOpen: Boolean

    /** Device info (null if not open). */
    val deviceInfo: UsbAudioDeviceInfo?
}
```

### UsbAudioDeviceInfo — Detected Capabilities

```kotlin
data class UsbAudioDeviceInfo(
    val deviceName: String,           // "Cayin RU7"
    val vendorId: Int,                // 0x2D87
    val productId: Int,               // 0xC002
    val uacVersion: Int,              // 2 (UAC2)
    val clockSourceId: Int,           // 0x05 (auto-detected)
    val supportedFormats: List<AudioFormat>,  // all alt settings
    val bestFormat: AudioFormat,      // highest quality format
    val endpointOut: Int,             // 0x01
    val endpointFeedback: Int,        // 0x81
    val maxPacketSize: Int,           // 776
) {
    data class AudioFormat(
        val altSetting: Int,          // 1, 2, 3, etc.
        val bitDepth: Int,            // 16, 24, 32
        val subslotSize: Int,         // 2, 3, 4 bytes
        val channelCount: Int,        // 2
    )
}
```

### UsbAudioStream — Audio Streaming

```kotlin
/**
 * An active audio stream to the USB DAC.
 *
 * Usage:
 *   val stream = device.createStream(sampleRate = 96000)
 *   stream.write(floatPcmBuffer)  // interleaved float [-1.0, 1.0]
 *   stream.write(floatPcmBuffer)  // call repeatedly from audio thread
 *   stream.close()
 */
class UsbAudioStream internal constructor(...) {

    /** Write interleaved float PCM data.
     *  Blocks until there's space in the URB pipeline.
     *  Thread-safe — call from any thread (typically audio render thread). */
    fun write(pcm: FloatArray)

    /** Write interleaved float PCM from a ByteBuffer (zero-copy path). */
    fun write(pcm: ByteBuffer, encoding: Int)

    /** Current sample rate (may differ from requested if DAC doesn't support it). */
    val sampleRate: Int

    /** Actual bit depth being used (from alt setting). */
    val bitDepth: Int

    /** Number of URBs currently in flight (pipeline depth). */
    val urbsInFlight: Int

    /** Read the DAC's feedback endpoint (actual hardware clock rate in Hz). */
    fun readFeedbackHz(): Double

    /** Stop streaming and release resources. */
    fun close()

    /** True if the stream is active and ready for writes. */
    val isActive: Boolean

    /** Listener for stream events. */
    interface Listener {
        fun onStreamStarted(sampleRate: Int, bitDepth: Int)
        fun onStreamError(error: UsbAudioException)
        fun onFeedbackUpdate(actualRateHz: Double)
        fun onStreamStopped()
    }

    fun setListener(listener: Listener?)
}
```

### UsbAudioPermissionHelper — Intent Filter Setup

```kotlin
/**
 * Helper for setting up USB_DEVICE_ATTACHED handling.
 *
 * The host Activity must:
 * 1. Declare the intent filter in AndroidManifest.xml
 * 2. Call handleIntent() in onCreate() and onNewIntent()
 */
object UsbAudioPermissionHelper {

    /** XML resource for the USB device filter (include in manifest meta-data). */
    val DEVICE_FILTER_RESOURCE: Int  // R.xml.usb_audio_device_filter

    /**
     * Process an intent that may be USB_DEVICE_ATTACHED.
     * Returns true if it was handled (device claimed).
     */
    fun handleIntent(context: Context, intent: Intent): Boolean
}
```

---

## Integration Examples

### Example 1: Minimal Standalone (No ExoPlayer)

For apps with their own decoder (FFmpeg, Opus, custom):

```kotlin
class MyPlayerActivity : AppCompatActivity() {

    private val usbDevice = UsbAudioDevice.getInstance(this)
    private var stream: UsbAudioStream? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        UsbAudioDevice.handleUsbDeviceAttached(this, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        UsbAudioDevice.handleUsbDeviceAttached(this, intent)
    }

    fun startPlayback(sampleRate: Int) {
        val info = usbDevice.open()
        Log.i("Player", "DAC: ${info.deviceName}, clock=0x${info.clockSourceId.toString(16)}")

        stream = usbDevice.createStream(sampleRate = sampleRate)

        // Your audio decode thread:
        thread {
            val decoder = MyDecoder("song.flac")
            while (decoder.hasMore()) {
                val floatPcm = decoder.decodeNextBuffer()  // interleaved float
                stream?.write(floatPcm)  // blocks naturally via USB timing
            }
            stream?.close()
        }
    }
}
```

**Manifest:**
```xml
<activity android:name=".MyPlayerActivity" android:launchMode="singleTask">
    <intent-filter>
        <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
    </intent-filter>
    <meta-data
        android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
        android:resource="@xml/usb_audio_device_filter" />
</activity>
```

### Example 2: ExoPlayer/Media3 Integration

For apps using ExoPlayer (drop-in replacement for DefaultAudioSink):

```kotlin
// build.gradle
dependencies {
    implementation("com.decentplayer:usb-audio-driver:1.0.0")
    implementation("com.decentplayer:usb-audio-media3:1.0.0")
}

// In your player setup:
val usbAudioSink = UsbAudioSink(context)  // from usb-audio-media3 module

val player = ExoPlayer.Builder(context)
    .setRenderersFactory { handler, _, audioListener, _, _ ->
        arrayOf(
            MediaCodecAudioRenderer(
                context,
                MediaCodecSelector.DEFAULT,
                handler,
                audioListener,
                usbAudioSink  // replaces DefaultAudioSink
            )
        )
    }
    .build()
```

### Example 3: Jetpack Compose

```kotlin
@Composable
fun BitPerfectPlayer(uri: Uri) {
    val context = LocalContext.current
    val usbDevice = remember { UsbAudioDevice.getInstance(context) }
    var isPlaying by remember { mutableStateOf(false) }
    var feedbackHz by remember { mutableStateOf(0.0) }

    LaunchedEffect(uri) {
        withContext(Dispatchers.IO) {
            val info = usbDevice.open()
            val stream = usbDevice.createStream(sampleRate = 44100)
            stream.setListener(object : UsbAudioStream.Listener {
                override fun onFeedbackUpdate(actualRateHz: Double) {
                    feedbackHz = actualRateHz
                }
                // ... other callbacks
            })
            isPlaying = true
            // decode and write loop...
        }
    }

    Column {
        Text("Playing: ${if (isPlaying) "Yes" else "No"}")
        Text("DAC Clock: ${feedbackHz.toInt()} Hz")
        Text("Bit-Perfect: USB Direct")
    }
}
```

### Example 4: Flutter Plugin (via Platform Channels)

```dart
// Dart side
final channel = MethodChannel('com.decentplayer/usb_audio');

Future<void> openDevice() async {
    final info = await channel.invokeMethod('openDevice');
    print('DAC: ${info['deviceName']}, clock: ${info['clockSourceId']}');
}

Future<void> writeAudio(Float32List pcm) async {
    await channel.invokeMethod('write', {'pcm': pcm});
}
```

```kotlin
// Android side (MethodChannel handler)
class UsbAudioPlugin : MethodCallHandler {
    private val device = UsbAudioDevice.getInstance(context)
    private var stream: UsbAudioStream? = null

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "openDevice" -> {
                val info = device.open()
                result.success(mapOf(
                    "deviceName" to info.deviceName,
                    "clockSourceId" to info.clockSourceId,
                    "bestBitDepth" to info.bestFormat.bitDepth
                ))
            }
            "write" -> {
                val pcm = call.argument<FloatArray>("pcm")!!
                stream?.write(pcm)
                result.success(null)
            }
        }
    }
}
```

### Example 5: React Native Module

```typescript
// JS side
import { UsbAudio } from 'react-native-usb-audio';

const info = await UsbAudio.openDevice();
console.log(`DAC: ${info.deviceName}, ${info.bestBitDepth}-bit`);

// In native audio callback:
UsbAudio.write(floatPcmArray);
```

---

## Publishing

### As Android Library (AAR)

```groovy
// usb-audio-driver/build.gradle
plugins {
    id 'com.android.library'
    id 'maven-publish'
}

android {
    namespace 'com.decentplayer.usbaudio'
    compileSdk 36
    defaultConfig {
        minSdk 29  // Android 10+
        ndk { abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64' }
        externalNativeBuild { cmake { path "src/main/jni/CMakeLists.txt" } }
    }
}

publishing {
    publications {
        release(MavenPublication) {
            groupId = 'com.decentplayer'
            artifactId = 'usb-audio-driver'
            version = '1.0.0'
        }
    }
}
```

### Distribution Options

1. **JitPack** — push to GitHub, add JitPack repo, instant dependency
2. **Maven Central** — for wider adoption, requires signing + OSSRH account
3. **Local AAR** — `./gradlew :usb-audio-driver:assembleRelease` produces `.aar`

### Gradle Dependency (end user)

```groovy
// settings.gradle
maven { url 'https://jitpack.io' }

// build.gradle
dependencies {
    implementation 'com.github.decentplayer:usb-audio-driver:1.0.0'
    // Optional:
    implementation 'com.github.decentplayer:usb-audio-media3:1.0.0'
}
```

---

## Extraction Plan from Felicity

### What to extract (copy into new library):

| Current Location | New Location | Notes |
|-----------------|-------------|-------|
| `engine/src/main/jni/usb-audio-output.cpp` | `usb-audio-driver/src/main/jni/` | As-is |
| `engine/src/main/jni/usb-audio-output.h` | `usb-audio-driver/src/main/jni/` | As-is |
| `engine/.../UsbAudioOutputProcessor.kt` | `usb-audio-driver/.../UsbAudioStream.kt` | Rename + clean API |
| `engine/.../UsbAudioManager.kt` | `usb-audio-driver/.../UsbAudioDevice.kt` | Rename + clean API |
| `engine/.../AaudioAudioSink.kt` (USB parts) | `usb-audio-media3/.../UsbAudioSink.kt` | Extract USB branch |
| `music/res/xml/usb_audio_device_filter.xml` | `usb-audio-driver/res/xml/` | As-is |

### Manifest & XML Configuration (CRITICAL)

The following XML configurations are **essential** for the driver to work. Without them, the app cannot claim USB devices before the kernel driver.

**1. AndroidManifest.xml — USB Intent Filter on the host Activity:**
```xml
<activity
    android:name=".YourMainActivity"
    android:launchMode="singleTask"
    android:exported="true">

    <!-- Normal launcher intent -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent-filter>

    <!-- USB Audio device claim — MUST be on an Activity, not a Service/Receiver.
         When the user connects a USB DAC, Android shows a dialog asking which app
         should handle it. If the user selects our app, we get the device BEFORE
         snd-usb-audio can configure it (or at least close to it). -->
    <intent-filter>
        <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
    </intent-filter>

    <!-- Links to the device filter XML that matches USB Audio Class devices -->
    <meta-data
        android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
        android:resource="@xml/usb_audio_device_filter" />
</activity>
```

**Key notes:**
- `android:launchMode="singleTask"` is required — otherwise Android creates a new Activity instance on each USB connect, causing state loss
- The intent filter MUST be on an Activity (not a BroadcastReceiver) for the system USB dialog to work
- The `meta-data` element links the intent filter to the device filter XML

**2. res/xml/usb_audio_device_filter.xml — USB Device Matching:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Matches ANY USB Audio Class device (class 1 = Audio).
     This makes Android offer our app as a handler when any USB DAC is connected.
     More specific filters can be added for vendor/product ID matching. -->
<resources>
    <usb-device class="1" />
</resources>
```

**Filter options:**
```xml
<!-- Match ANY USB Audio device (recommended for a universal player) -->
<usb-device class="1" />

<!-- Match a specific vendor (e.g., only Cayin devices) -->
<usb-device vendor-id="11655" />  <!-- 0x2D87 in decimal -->

<!-- Match a specific product -->
<usb-device vendor-id="11655" product-id="49154" />  <!-- Cayin RU7 -->

<!-- Match multiple devices -->
<resources>
    <usb-device class="1" />
    <usb-device vendor-id="11655" />
    <usb-device vendor-id="10494" />  <!-- FiiO -->
</resources>
```

**3. Activity code — handling the intent:**
```kotlin
class YourMainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Handle USB device if app was launched by USB_DEVICE_ATTACHED
        UsbAudioDevice.handleUsbDeviceAttached(this, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Handle USB device if app was already running and DAC was reconnected
        UsbAudioDevice.handleUsbDeviceAttached(this, intent)
    }
}
```

**4. Permission handling — PendingIntent for runtime permission:**

When the USB device is connected for the first time (no prior "always use this app" selection), the app must request permission explicitly:

```kotlin
// Inside UsbAudioDevice (library handles this internally)
fun requestPermission(device: UsbDevice, callback: (Boolean) -> Unit) {
    // CRITICAL: On Android 14+ (targetSdk 34+), the PendingIntent MUST have
    // an explicit intent (with setPackage). Implicit intents with FLAG_MUTABLE
    // cause IllegalArgumentException.
    val intent = Intent(ACTION_USB_PERMISSION)
    intent.setPackage(context.packageName)  // Makes it explicit!
    val pendingIntent = PendingIntent.getBroadcast(
        context, 0, intent, PendingIntent.FLAG_MUTABLE
    )

    // Register a receiver for the permission result
    val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            context.unregisterReceiver(this)
            callback(granted)
        }
    }
    context.registerReceiver(receiver, IntentFilter(ACTION_USB_PERMISSION),
        Context.RECEIVER_NOT_EXPORTED)  // Required on Android 13+

    usbManager.requestPermission(device, pendingIntent)
}
```

**5. Complete manifest permissions needed:**
```xml
<!-- No special permissions needed for USB Host mode on most devices.
     The USB permission is granted at runtime via the system dialog.
     These are optional but recommended: -->
<uses-feature android:name="android.hardware.usb.host" android:required="false" />
```

Note: `android.hardware.usb.host` as a `<uses-feature>` with `required="false"` declares that the app CAN use USB Host but doesn't require it (so it's still installable on devices without USB Host support like some tablets).

### What NOT to extract:

- AAudio code (separate concern)
- ExoPlayer/Media3 imports (only in media3 module)
- Felicity-specific preferences
- UI code (dialogs, toggles)
- DSP engine

### Key Refactoring:

1. Remove `AudioPreferences` dependency → pass config via constructor
2. Remove `AaudioAudioSink` coupling → standalone stream API
3. Remove Felicity package names → `com.decentplayer.usbaudio`
4. Remove Hilt/DI → simple singleton pattern
5. Add proper error types (`UsbAudioException` subclasses)
6. Add stream listener for async events
7. Add `ByteBuffer` write path for zero-copy from native decoders

---

## License

The USB audio driver code is **100% original work** — written entirely from scratch during this project. No code was taken from Felicity's codebase (which has no USB audio driver). Specifically:

- `usb-audio-output.cpp/.h` — original native code
- `UsbAudioOutputProcessor.kt` — original JNI wrapper
- `UsbAudioManager.kt` — original device management + descriptor parser
- `UsbAudioDiagnosticDialog.kt` — original diagnostic UI
- All USB-related additions to `AaudioAudioSink.kt` — original integration code
- All manifest/XML changes for USB — original configuration

The driver was developed using:
- Public USB Audio Class 2.0 specification
- Public Linux kernel documentation (`usbdevfs`, `USBDEVFS_SUBMITURB`)
- Public Android SDK APIs (`UsbManager`, `UsbDeviceConnection`)
- System-level observation of USB audio protocol behavior via `dumpsys` / `sysfs` / xHCI ftrace

**Recommended license for the standalone library:** MIT or Apache 2.0 — maximizes adoption. The code is ours to license as we choose.

---

## DecentPlayer: Recommended Tech Stack

For the new app from scratch, not based on Felicity:

```
UI:           Jetpack Compose (Material 3)
Audio decode: Media3/ExoPlayer (with FFmpeg extension for hi-res)
USB output:   usb-audio-driver (this library)
Integration:  usb-audio-media3 (AudioSink for ExoPlayer)
DI:           Hilt
Database:     Room (for library, playlists)
Metadata:     jAudioTagger or MediaMetadataRetriever
Architecture: MVVM + Clean Architecture
Language:     100% Kotlin
Min SDK:      29 (Android 10)
```

The USB audio driver library is the foundation. Everything else is standard Android audio player architecture — but with the unique ability to output bit-perfect audio that no other open-source player has.
