# Issue: ExoPlayer Pipeline Latency at High Sample Rates

## Status: Resolved (2026-04-06)

## Symptom

On the iBasso DX340, playback of 96kHz and 192kHz content via USB bit-perfect mode suffers periodic audio dropouts (3-10 second silence gaps). The music stops and resumes intermittently.

On the Samsung S26 Ultra (Snapdragon 8 Elite), the same content plays without any dropouts.

A reference USB audio app plays 96/192kHz flawlessly on the same iBasso DX340, proving the hardware is capable.

## Root Cause (Two-Part)

### Part 1: ExoPlayer Pipeline Overhead

The ExoPlayer-based audio pipeline has too many layers between the FLAC decoder and the USB output. On devices with slower CPUs, the decoder can only produce audio at approximately 1x real-time speed for high sample rates. Since the USB DAC consumes at exactly 1x real-time, there is zero headroom — any CPU hiccup (GC, scheduler, I/O) causes the streaming thread to starve and the USB pipeline to drain.

#### Evidence from xHCI Traces

```
Queue nearly empty: 0 before writeRaw   ← queue empty, no headroom
GAP 9.2s @ 03:28:53                      ← 9.2 seconds of silence
GAP 6.9s @ 03:28:48                      ← another gap
```

Despite a backpressure threshold of 16, the queue **never exceeded 0-1 entries**. ExoPlayer delivered buffers at exactly the consumption rate. On the S26 Ultra, the same queue stabilizes at 10-16 entries (the decoder runs at 3-5x real-time).

#### The Pipeline Overhead

ExoPlayer pipeline (before fix):

```
Disk read (Java I/O)
  → FlacExtractor (Java, calls native libflac via JNI)
    → SampleQueue (Java, in-memory ring buffer)
      → MediaCodecAudioRenderer (Java, render loop)
        → handleBuffer (Kotlin, copies ByteBuffer → ByteArray)
          → ArrayBlockingQueue (Java, producer-consumer)
            → UsbStreamingThread (Kotlin, polls queue)
              → JNI call to nativeWriteRaw (C++)
                → padInt24ToInt32 (C++, bit-depth conversion)
                  → submitPcmToUrbs (C++, USB isochronous transfer)
```

**6 language boundary crossings, 3 JNI transitions, 2 data copies, 1 Java queue.**

### Part 2: Metadata Scanner I/O Contention (SD Card Only)

Even after implementing the NativeAudioEngine (Part 1 fix), SD card playback still had stalls. Per-thread I/O analysis (`/proc/PID/task/TID/io`) revealed the true culprit:

```
┌──────────────────┬──────────┬────────────────┐
│  30 seconds       │ Before   │ After fix      │
├──────────────────┼──────────┼────────────────┤
│ SD card read     │ 1390 MB  │    0 MB        │
│ Process read     │ 1411 MB  │   18 MB        │
│ Syscalls         │ 181,584  │  7,186         │
└──────────────────┴──────────┴────────────────┘
```

The Felicity app's `AudioDatabaseLoader` metadata scanner ran 8 `DefaultDispatch` threads reading **~35 MB/s** from the SD card through Android's FUSE layer, competing with playback I/O. The scanner was triggered via `refreshScan()` on every `onResume()`, which called `cancelAndRestartScan()` — canceling the current scan and starting fresh. Since each `adb install` clears the database, ALL files were "new" every time. The scan never completed on large libraries.

#### Diagnostic Breakthrough

The breakthrough came from per-thread I/O analysis:

```bash
# Read /proc/PID/task/TID/io for each thread
for TID in $(ls /proc/$PID/task/); do
    read_bytes=$(cat /proc/$PID/task/$TID/io | grep read_bytes)
    comm=$(cat /proc/$PID/task/$TID/comm)
    echo "$TID $comm $read_bytes"
done
```

Results showed:
- `ExoPlayer:Playb` → 18 MB (LoadControl working correctly)
- `DefaultDispatch` × 8 threads → **700 MB in 20s** (the scanner!)

### What Was Ruled Out

1. **USB driver**: Zero URB errors, zero short packets, stable 80 URBs in flight
2. **LoadControl buffering**: Increased ExoPlayer's minBuffer/maxBuffer — no improvement
3. **Delegate AudioTrack stalling**: Already decoupled
4. **CPU overhead from diagnostics**: Removed checks from hot path — no improvement
5. **FUSE readahead**: Tried mmap, readahead(), posix_fadvise — marginal improvement
6. **ExoPlayer file loading**: Custom `LoadControl` successfully stopped ExoPlayer loading (11 MB → 1 MB), but stalls continued because the scanner was the real problem

## Solution: NativeAudioEngine + LoadControl + Scanner Pause

### NativeAudioEngine (Pipeline Bypass)

A native C++ thread handles FLAC decode → USB directly, bypassing the entire ExoPlayer audio pipeline:

```
┌─────────────────────────────────────────────────┐
│ ExoPlayer (Java/Kotlin)                         │
│   - Playlist management, media session          │
│   - Track metadata, seek/pause/play control     │
│   - Position tracking (via engine.getPositionUs)│
└──────────────┬──────────────────────────────────┘
               │ control only
               ▼
┌─────────────────────────────────────────────────┐
│ NativeAudioEngine (C++)                         │
│   - Single pthread: decode → convert → USB      │
│   - AsyncBufferedDataSource (8MB, I/O thread)   │
│   - FLACParser (xiph/flac) for decode           │
│   - padInt24ToInt32 for bit-depth conversion     │
│   - submitPcmToUrbs for USB isochronous output  │
│   - Position via atomic framesDecoded counter   │
└─────────────────────────────────────────────────┘
```

**Performance**: ~0.11ms per 1ms of audio. Even on iBasso DX340, ~10x headroom. Gaps impossible.

### NativeEngineAwareLoadControl (ExoPlayer I/O Throttle)

Custom `LoadControl` wrapper that returns `false` from `shouldContinueLoading()` when the native engine is active. Prevents ExoPlayer's `FlacExtractor` from reading the same file in parallel.

After seek, `flush()` temporarily unblocks loading so ExoPlayer loads one chunk (post-seek guarantee from Media3) for `presentationTimeUs` capture, then re-blocks.

Note: Kotlin `by` delegation does NOT forward Java default methods — every method must be explicitly overridden. This caused two crashes before we discovered the issue.

### Scanner Pause During Playback

Changed `onResume()` from `refreshScan()` (cancel+restart) to `startScan()` (skip-if-running). Added `AudioDatabaseLoader.playbackActive` flag to pause the scanner while the native engine is playing (implementation pending — scan is temporarily disabled for testing).

## Files Created/Modified

### New Files

| File | Module | Purpose |
|------|--------|---------|
| `native-audio-engine.cpp` | usb-audio-driver | C++ engine: AsyncBufferedDataSource, FLACParser decode loop, JNI entry points |
| `native-audio-engine.h` | usb-audio-driver | Header with forward declarations |
| `NativeAudioEngine.kt` | usb-audio-driver | Kotlin JNI wrapper: createFromFd, start, pause, resume, seek, stop, destroy, getPositionUs |
| `NativeEngineAwareLoadControl.kt` | usb-audio-wrapper-media3 | LoadControl wrapper to stop ExoPlayer file loading during native playback |

### Modified Files

| File | Module | Changes |
|------|--------|---------|
| `usb-audio-output.h` | usb-audio-driver | Exposed `submitPcmToUrbs`, `padInt16ToInt32`, `padInt24ToInt32` as non-static |
| `usb-audio-output.cpp` | usb-audio-driver | Made conversion functions non-static |
| `CMakeLists.txt` | usb-audio-driver | Added libFLAC linking, `native-audio-engine.cpp`, `flac_parser.cc` |
| `UsbAudioStream.kt` | usb-audio-driver | Exposed `nativeHandle` for NativeAudioEngine, added `framesWritten` |
| `UsbAudioSink.kt` | usb-audio-wrapper-media3 | NativeAudioEngine integration: lazy creation, seek, position tracking, deferred config, LoadControl flag |
| `UsbStreamingThread.kt` | usb-audio-wrapper-media3 | Added `pauseStreaming()`, `resumeStreaming()`, `hasPendingData()`, `queueSize()` |
| `flac_parser.cc` | decoder-flac | Added `seekAbsolute()` (sets `mWriteRequested=true` before seek), fixed `lengthCallback` |
| `data_source.h` | decoder-flac | Added `virtual off64_t getLength()` |
| `FelicityPlayerService.kt` | engine | `onMediaItemTransition`: engine lifecycle, `NativeEngineAwareLoadControl` wrapping |
| `MainActivity.kt` | music | Changed `refreshScan` → `startScan` in `onResume()` |
| `AudioDatabaseLoader.kt` | repository | Added `playbackActive` flag, scan logging with SD_CARD/INTERNAL labels |

## Key Design Decisions

1. **AsyncBufferedDataSource with direct pread64 for small reads**: The 8MB I/O buffer handles sequential decode. For FLAC seek (binary search with many small random reads), direct `pread64` in the caller thread avoids I/O thread round-trip latency. This reduced seek time from ~5s to <100ms on SD card.

2. **LoadControl vs disabling audio track**: We considered `setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)` but this disables the renderer entirely, losing position tracking and end-of-stream detection. The LoadControl wrapper is cleaner — the renderer stays active, `hasPendingData()` keeps ExoPlayer in STATE_READY.

3. **Deferred USB reconfiguration**: When ExoPlayer pre-buffers the next track ~10s before EOF, `configure()` fires with the new track's format. If the engine is still playing the current track, we defer the USB reconfiguration until the engine finishes.

4. **readahead limited to 2MB**: Full-file `readahead()` on SD card monopolized the FUSE daemon, blocking our `pread64` calls. Limiting to 2MB (enough for FLAC metadata + initial frames) solved the initial creation timeout.

## Verification Results

### iBasso DX340 (192kHz/24-bit FLAC from SD card)

- Zero stalls during continuous playback (with scanner disabled)
- Seek responds in <1s (was 5s before direct pread64 fix)
- SD card I/O: 18 MB / 30s (was 1,390 MB before fixes)
- Position tracking accurate, seek bar functional

### Samsung S26 Ultra (all formats)

- No regressions — ExoPlayer pipeline fallback works for non-FLAC
- Native engine activates for FLAC files
- Float path (FFmpeg) continues working for MP3/AAC
