# AAudio Exclusive Mode — Architecture

## Overview

The AAudio exclusive mode feature enables **true bit-perfect audio playback** on Android by:

1. **Volume lock** — Forces system media volume to maximum so physical volume keys don't affect loudness. Volume is controlled purely at the app level via PCM gain.

2. **AAudio exclusive stream** — Opens an Android AAudio stream with `AAUDIO_SHARING_MODE_EXCLUSIVE`, bypassing the Android AudioFlinger mixer. Audio data at the source sample rate/bit depth flows directly to the hardware DAC.

3. **Status reporting** — Real-time display of AAudio status (exclusive/shared/available/unavailable) in the Audio Info sheet.

---

## Architecture Diagram

```
┌══════════════════════════════════════════════════════════════════┐
│                     Flutter / Dart Layer                         │
│                                                                  │
│  ┌─────────────────────┐  ┌────────────────────────────────┐    │
│  │ AudioPlayerService  │  │ ExclusiveAudioService          │    │
│  │  • setExclusiveMode │──│  • enable() / disable()        │    │
│  │  • toggles AAudio   │  │  • aaudioExclusive getter      │    │
│  │    sink on HiRes    │  │  • status stream               │    │
│  └─────────┬───────────┘  └──────────────┬─────────────────┘    │
│            │                              │                      │
│            │   ┌──────────────────┐       │                      │
│            └──→│ HiResAudioService │       │                      │
│                │  setUseAaudioSink│       │                      │
│                └────────┬─────────┘       │                      │
│                         │                 │                      │
│              MethodChannel                │                      │
└═════════════════════════╤═════════════════╪══════════════════════┘
                          │                 │
┌═════════════════════════╪═════════════════╪══════════════════════┐
│                  Kotlin / Android Layer   │                      │
│                          │                 │                      │
│  ┌───────────────────────▼──────────┐  ┌──▼──────────────────┐   │
│  │    HiResAudioPlugin.kt          │  │ ExclusiveAudioPlugin  │   │
│  │                                 │  │   .kt                │   │
│  │  ExoPlayer.Builder              │  │                      │   │
│  │    .setRenderersFactory(        │  │  • Volume lock thread │   │
│  │      DefaultRenderersFactory    │  │  • USB hotplug        │   │
│  │        .buildAudioSink()))      │  │  • Status detection   │   │
│  │         ↓                       │  │  • Companion statics  │   │
│  │  ┌──────────────────────┐       │  │    for AudioSink      │   │
│  │  │ AaudioAudioSink.kt  │       │  └──────────┬────────────┘   │
│  │  │ (AudioSink impl.)   │       │             │                │
│  │  │  • configure()      │       │    JNI native*StaticImpl()  │
│  │  │  • handleBuffer()   │───────┼─────────────┘                │
│  │  │  • play/pause/reset │       │                              │
│  │  └────────┬────────────┘       │                              │
│  └───────────┼────────────────────┘                              │
│              │ JNI                                                │
└══════════════╪════════════════════════════════════════════════════┘
               │
┌══════════════╪════════════════════════════════════════════════════┐
│       C++ NDK Layer (libaaudio_exclusive.so)                     │
│              │                                                    │
│  ┌───────────▼────────────────────────────────────────────────┐  │
│  │                  jni_bridge.cpp                             │  │
│  │                                                             │  │
│  │  nativeCreatePlayerStaticImpl → new AaudioExclusivePlayer()  │  │
│  │  nativeWritePcmFloatStaticImpl → player->write(float[])      │  │
│  │  nativeWritePcmI16StaticImpl   → player->writeI16(int16[])   │  │
│  │  nativeGetFramesWrittenStatic  → player->getTotalFrames()    │  │
│  │  nativeDestroyPlayerStaticImpl → delete player               │  │
│  └───────────────────────────┬─────────────────────────────────┘  │
│                              │                                    │
│  ┌───────────────────────────▼────────────────────────────────┐  │
│  │              aaudio_player.cpp / .h                        │  │
│  │                                                             │  │
│  │  AaudioExclusivePlayer (PIMPL → Impl)                      │  │
│  │                                                             │  │
│  │  • init(sampleRate, channels, bitsPerSample)                │  │
│  │    → AAudio_createStreamBuilder + builder_set* → openStream │  │
│  │    → Requests AAUDIO_SHARING_MODE_EXCLUSIVE                 │  │
│  │    → Verifies via AAudioStream_getSharingMode()             │  │
│  │                                                             │  │
│  │  • write(float[]) — writes float PCM to AAudio stream       │  │
│  │  • writeI16(int16[]) — converts I16→float on pre-allocated  │  │
│  │    buffer, then writes                                      │  │
│  │                                                             │  │
│  │  • start() / stop() — AAudioStream_requestStart/Stop        │  │
│  │  • destroy() — closeStream + cleanup                        │  │
│  │                                                             │  │
│  │  Thread safety: All mutation methods guarded by std::mutex  │  │
│  │  Frame tracking: std::atomic<int64_t> totalFramesWritten_   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  AAudio API loaded via dlopen("libaaudio.so") at runtime          │
│  → No compile-time dependency on libaaudio.so                    │
│  → Same APK runs on API 24+ (AAudio only on API 26+)             │
└════════════════════════════════════════════════════════════════════┘
```

---

## Layer-by-Layer Breakdown

### 1. Dart Layer

#### `ExclusiveAudioService` (`lib/src/services/exclusive_audio_service.dart`)

Singleton service wrapping the `com.kikoeru.flutter/exclusive_audio` MethodChannel.

**Key state fields:**
| Field | Type | Description |
|-------|------|-------------|
| `_enabled` | `bool` | Whether exclusive mode toggle is on |
| `_volumeLocked` | `bool` | Whether system volume is locked at max |
| `_aaudioAvailable` | `bool` | Whether device supports AAudio (API 27+) |
| `_aaudioActive` | `bool` | Whether AAudio stream is open |
| `_aaudioExclusive` | `bool` | Whether AAudio exclusive mode was GRANTED |
| `_mixerBypassed` | `bool` | Whether Android mixer is bypassed |

**Key methods:**
- `enable()` / `disable()` — Toggle exclusive mode via MethodChannel
- `getStatus()` — Fetch detailed status map from native
- `stateStream` — Reactive stream of `ExclusiveModeState` changes

#### `HiResAudioService` (`lib/src/services/hi_res_audio_service.dart`)

Manages `setUseAaudioSink(bool)` — tells the native plugin whether to use the AAudio AudioSink for the next ExoPlayer creation.

#### `AudioPlayerService` (`lib/src/services/audio_player_service.dart`)

`setExclusiveMode(bool enabled)` — the main entry point. When enabled:
1. Calls `ExclusiveAudioService.enable()` → volume lock + AAudio status stream opens
2. Calls `HiResAudioService.setUseAaudioSink(true)` → next playback uses AAudio AudioSink

> **⚠️ Toggle requires restart:** The AAudio AudioSink takes effect only when `HiResAudioPlugin` creates a **new** ExoPlayer (i.e., the next `play()` call). If the user enables exclusive mode mid-track, they must restart playback for the sink to swap.

---

### 2. Kotlin Layer

#### `ExclusiveAudioPlugin` (`android/.../ExclusiveAudioPlugin.kt`)

**Volume Lock mechanism:**
- Saves `originalMusicVolume` when enabling
- Starts a daemon thread polling every 500ms: `audioManager.setStreamVolume(MUSIC, max, 0)`
- Registers `BroadcastReceiver` for `VOLUME_CHANGED_ACTION` — instantaneous restoration
- Registers `AudioDeviceCallback` for USB hotplug detection

**Status detection stream:**
- `initAaudioPlayer()` creates a test AAudio stream (48000Hz, 2ch, 24bit)
- Checks if `nativeIsExclusive()` returns true
- Reports status back to Dart via `onExclusiveModeChanged` method call

**Companion object statics (used by AaudioAudioSink):**
```kotlin
fun nativeCreatePlayerStatic(): Long
fun nativeInitPlayerStatic(ptr, sr, ch, bits): Boolean
fun nativeStartPlayerStatic(ptr): Boolean
fun nativeStopPlayerStatic(ptr)
fun nativeDestroyPlayerStatic(ptr)
fun nativeWritePcmFloatStatic(ptr, FloatArray, numFrames): Int
fun nativeWritePcmI16Static(ptr, ShortArray, numFrames): Int
fun nativeGetFramesWrittenStatic(ptr): Long
fun nativeResetFramesWritten(ptr)
```

These delegate to `@JvmStatic private external fun native*StaticImpl()` methods.

#### `AaudioAudioSink` (`android/.../AaudioAudioSink.kt`)

Custom `AudioSink` implementation for ExoPlayer. Routes decoded PCM to AAudio instead of AudioTrack.

**Lifecycle:**
| ExoPlayer calls | AaudioAudioSink action |
|----------------|----------------------|
| `configure(Format, ...)` | Parse `Format.sampleRate`, `Format.channelCount`, `Format.pcmEncoding`. Create + init native AAudio player via `nativeLibraryLoader` lambda. Returns `false` if format unsupported. |
| `handleBuffer(ByteBuffer, ...)` | Convert PCM data (I16/Float/32-bit) to float[], apply volume gain, call `nativeWritePcmFloat` or `nativeWritePcmI16`. Advance ByteBuffer position. |
| `play()` | Call `nativeStartPlayer` — starts AAudio stream |
| `pause()` | Call `nativeStopPlayer` — stops AAudio stream |
| `flush()` | Call `nativeResetFramesWritten` — resets frame counter. Sets `needsEndOfStream` flag. |
| `isEnded()` | Returns `true` after `flush()` + final `handleBuffer` with end-of-stream flag (used by ExoPlayer for stream lifecycle termination). |
| `reset()` | Call `nativeDestroyPlayer` — destroys native player |

**Format conversion:**
| Source format | Conversion |
|-------------|-----------|
| `ENCODING_PCM_16BIT` | `ShortArray` → `nativeWritePcmI16` → C++ divides by 32768.0f |
| `ENCODING_PCM_FLOAT` | `FloatArray` → `nativeWritePcmFloat` |
| `ENCODING_PCM_32BIT` | `IntArray` → divide by 2147483648.0f → `nativeWritePcmFloat` |

**Volume gain:** Applied to PCM data before write: `sample = sample * volume.coerceIn(0f, 1f)`

#### `HiResAudioPlugin` (`android/.../HiResAudioPlugin.kt`)

`setUseAaudioSink(enabled)` flag controls whether the ExoPlayer uses `DefaultRenderersFactory` with overridden `buildAudioSink()`:

```kotlin
val renderersFactory = object : DefaultRenderersFactory(context) {
    override fun buildAudioSink(ctx, enableFloatOutput, enableAudioTrackPlaybackParams): AudioSink? {
        return AaudioAudioSink { sr, ch, bits ->
            val ptr = ExclusiveAudioPlugin.nativeCreatePlayerStatic()
            if (ptr != 0L && ExclusiveAudioPlugin.nativeInitPlayerStatic(ptr, sr, ch, bits)) {
                ptr
            } else { 0L }
        }
    }
}
```

When disabled, the standard `DefaultAudioSink` (AudioTrack-based) is used.

---

### 3. JNI Bridge

#### `jni_bridge.cpp`

Two sets of JNI functions:

| Instance methods (for ExclusiveAudioPlugin's own status player) | Static methods (for AaudioAudioSink) |
|----------------------------------------------------------------|--------------------------------------|
| `nativeCreatePlayer` | `nativeCreatePlayerStaticImpl` |
| `nativeInitPlayer` | `nativeInitPlayerStaticImpl` |
| `nativeStartPlayer` | `nativeStartPlayerStaticImpl` |
| `nativeStopPlayer` | `nativeStopPlayerStaticImpl` |
| `nativeDestroyPlayer` | `nativeDestroyPlayerStaticImpl` |
| `nativeIsExclusive` | `nativeIsExclusiveStaticImpl` |
| `nativeGetSampleRate` | `nativeGetSampleRateStaticImpl` |
| `nativeGetLatencyMs` | — |
| — | `nativeWritePcmFloatStaticImpl` |
| — | `nativeWritePcmI16StaticImpl` |
| — | `nativeGetFramesWrittenStaticImpl` |
| — | `nativeResetFramesWrittenStaticImpl` |

JNI array handling: Uses `GetFloatArrayElements` / `GetShortArrayElements` with `JNI_ABORT` (no copy-back on release). Null-checked throughout.

---

### 4. C++ Layer

#### `aaudio_player.h` — Public API

```cpp
class AaudioExclusivePlayer {
    bool init(int32_t sampleRate, int32_t channelCount, int32_t bitsPerSample);
    bool start();
    void stop();
    void destroy();
    int32_t write(const float* data, int32_t numFrames);
    int32_t writeI16(const int16_t* data, int32_t numFrames);
    int64_t getTotalFramesWritten() const;
    void resetTotalFramesWritten();
    bool isExclusive() const;
    bool isActive() const;
    int32_t getSampleRate() const;
    double getLatencyMs() const;
};
```

#### `aaudio_player.cpp` — Implementation

**AAudio loading (runtime dynamic):**
```cpp
static struct AaudioApi {
    bool loaded;
    void* handle;
    aaudio_result_t (*AAudio_createStreamBuilder)(...);
    void (*AAudioStreamBuilder_setSharingMode)(...);
    // ... 21 function pointers total
} s_aaudio = {false, nullptr};
```

Loaded once via `dlopen("libaaudio.so")` + `dlsym` for each symbol. Uses `LOAD_SYM` macro with `#name` stringification for exact symbol matching.

**Stream initialization:**
```cpp
bool init(int32_t sampleRate, int32_t channelCount, int32_t bitsPerSample) {
    loadAaudioLibrary();  // dlopen + dlsym
    closeStream();        // cleanup previous
    
    aaudio_format_t format = (bitsPerSample <= 16)
        ? AAUDIO_FORMAT_PCM_I16
        : AAUDIO_FORMAT_PCM_FLOAT;
    
    builder = ...;
    AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_EXCLUSIVE);
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setFormat(builder, format);
    AAudioStreamBuilder_setSampleRate(builder, sampleRate);
    AAudioStreamBuilder_setChannelCount(builder, channelCount);
    AAudioStreamBuilder_setBufferCapacityInFrames(builder, 256);
    AAudioStreamBuilder_openStream(builder, &stream);
    
    // Verify if exclusive was actually granted
    isExclusive = (AAudioStream_getSharingMode(stream) == AAUDIO_SHARING_MODE_EXCLUSIVE);
}
```

**PCM write with I16→float conversion:**
```cpp
int32_t writeI16(const int16_t* data, int32_t numFrames) {
    int32_t totalSamples = numFrames * channelCount_;
    // Pre-allocated buffer — only re-grows when needed
    if (totalSamples > floatBufferSize_) {
        floatBuffer_.reset(new float[totalSamples]);
        floatBufferSize_ = totalSamples;
    }
    for (int32_t i = 0; i < totalSamples; i++) {
        floatBuffer_[i] = data[i] / 32768.0f;
    }
    return AAudioStream_write(stream_, floatBuffer_.get(), numFrames, 500ms);
}
```

**Frame tracking:** `std::atomic<int64_t> totalFramesWritten_` — written under mutex in `write()`/`writeI16()`, read atomically (without mutex) in `getTotalFramesWritten()`.

---

## Thread Safety Design

| Resource | Protection | Rationale |
|----------|-----------|-----------|
| `Impl::stream_`, `builder_`, state flags | `std::mutex mutex_` | All mutation methods (`init`, `start`, `stop`, `destroy`, `write`, `writeI16`) lock the mutex |
| `totalFramesWritten_` | `std::atomic<int64_t>` | Written under mutex but read without mutex from `getTotalFramesWritten()` (called from JNI position-tracker). Atomic guarantees no torn reads/writes. |
| `s_aaudio` (global AaudioApi) | Write-once after `dlopen` + `dlsym` | `dlopen` is thread-safe in bionic. Concurrent `loadAaudioLibrary()` calls from different `Impl` instances both get identical function pointers. |
| `AaudioAudioSink.tempFloatBuffer` | Local allocation per call | Each `handleBuffer` call creates a local `FloatArray`. No shared mutable state. |
| `ExclusiveAudioPlugin` state | `@Volatile` on flags + `synchronized` on singleton | Thread-safety for Kotlin fields accessed from volume-lock thread and main thread. |

## Graceful Degradation

| Condition | Behavior |
|-----------|----------|
| API < 26 | `loadAaudioLibrary()` returns false. `init()` returns false. `AaudioAudioSink` creates 0L player → buffers consumed silently. Exclusive mode = volume lock only. |
| `libaaudio.so` not found | `dlopen` fails → `loadAaudioLibrary()` returns false. Same degradation as above. |
| Exclusive mode not granted | `AAudioStream_getSharingMode()` returns `AAUDIO_SHARING_MODE_SHARED`. Status shows "⚠️ Shared (exclusive not granted)". Audio still plays through AAudio shared mode. |
| `System.loadLibrary` fails | `UnsatisfiedLinkError` caught in `ExclusiveAudioPlugin.Companion.init`. Plugin methods return false/defaults. |
| `AaudioAudioSink` player fails | `nativePlayerPtr == 0L` → `handleBuffer` silently drains buffers (no audio output). User hears silence. ExoPlayer has no fallback to `DefaultAudioSink` when using a custom `AudioSink`. |

## Status Reporting (Audio Info Sheet)

The Audio Info sheet now shows accurate real-time status:

| Label | Values |
|-------|--------|
| AAudio | ✅ Exclusive (mixer bypassed) / ⚠️ Shared / Available / Unavailable |
| Android Mixer | Bypassed (AAudio) / Active |
| Bit-Perfect | YES (AAudio Exclusive) / NO (AAudio Shared mode) / NO (Vol Lock only) / NO (Android Mixer) |
| Exclusive Mode | Active (Vol Locked) / Off |
| Volume Lock | System volume at max (shown in Technical Information) |

## Files Reference

| File | Layer | Role |
|------|-------|------|
| `lib/src/services/exclusive_audio_service.dart` | Dart | State management for exclusive mode |
| `lib/src/services/hi_res_audio_service.dart` | Dart | AAudio AudioSink toggle |
| `lib/src/services/audio_player_service.dart` | Dart | Wires exclusive mode → AAudio sink |
| `lib/src/widgets/player/audio_info_sheet.dart` | Dart | AAudio status display |
| `android/.../ExclusiveAudioPlugin.kt` | Kotlin | Volume lock + status stream + JNI statics |
| `android/.../AaudioAudioSink.kt` | Kotlin | Custom ExoPlayer AudioSink |
| `android/.../HiResAudioPlugin.kt` | Kotlin | ExoPlayer with custom RenderersFactory |
| `android/.../MainActivity.kt` | Kotlin | Plugin registration |
| `android/app/src/main/cpp/aaudio_player.h` | C++ | AaudioExclusivePlayer API |
| `android/app/src/main/cpp/aaudio_player.cpp` | C++ | AAudio stream management + PCM write |
| `android/app/src/main/cpp/jni_bridge.cpp` | C++ | JNI glue (instance + static methods) |
| `android/app/src/main/cpp/CMakeLists.txt` | CMake | NDK build config (links dl, android, log) |
| `android/app/build.gradle.kts` | Gradle | externalNativeBuild config + media3 dep |
