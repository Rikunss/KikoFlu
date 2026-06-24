# USB Audio Diagnostics Reference

Diagnostic code snippets that were used during the USB audio pops investigation
and delegate decoupling work. Removed from production for performance, but
documented here for future debugging.

## 1. ISO Packet Status Check (in reap loop)

Verifies that the xHCI host controller successfully transmitted all ISO packets.
Catches hardware-level USB errors invisible to the application layer.

**Where**: `reapOldestUrb()` in `usb-audio-output.cpp`, after reaping an audio URB.

```cpp
static int64_t g_urbErrorCount = 0;

// After: ctx->reapIdx = (ctx->reapIdx + 1) % USB_AUDIO_NUM_URBS;
{
    int errPkts = 0;
    int shortPkts = 0;
    for (int p = 0; p < c->number_of_packets; p++) {
        int st = c->iso_frame_desc[p].status;
        int actual = c->iso_frame_desc[p].actual_length;
        int expected = c->iso_frame_desc[p].length;
        if (st != 0) errPkts++;
        if (actual != expected && actual != 0) shortPkts++;
    }
    if (errPkts > 0 || shortPkts > 0) {
        g_urbErrorCount++;
        if (g_urbErrorCount <= 20 || g_urbErrorCount % 100 == 0) {
            LOGW("URB_ERR #%lld slot=%d: %d err_pkts, %d short_pkts, status=%d",
                 (long long)g_urbErrorCount, ctx->reapIdx, errPkts, shortPkts, c->status);
        }
    }
}
```

**Result**: Zero errors during steady-state playback. Only triggered during
stream transitions (status=-108 ESHUTDOWN, expected when draining URBs).

**Cost**: ~0.5µs per reap (8 iterations). At 1000 reaps/sec = 0.5ms/sec.

---

## 2. PCM Boundary Continuity Check

Detects discontinuities between consecutive `nativeWrite`/`nativeWriteRaw` calls.
A large jump between the last sample of call N and the first sample of call N+1
indicates data loss or misalignment.

**Where**: Before `submitPcmToUrbs()` in both `nativeUsbAudioWrite` and `nativeUsbAudioWriteRaw`.

```cpp
static int32_t g_lastSampleL = 0, g_lastSampleR = 0;
static bool g_boundaryInitialized = false;
static int64_t g_boundaryBreakCount = 0;

static void checkWriteBoundary(const uint8_t *data, int totalBytes, int bytesPerFrame, int ch) {
    if (bytesPerFrame != ch * 4 || totalBytes < bytesPerFrame) return;
    auto *samples = reinterpret_cast<const int32_t *>(data);
    int totalFrames = totalBytes / bytesPerFrame;
    int32_t firstL = samples[0];
    int32_t firstR = (ch > 1) ? samples[1] : firstL;
    int32_t lastL = samples[(totalFrames - 1) * ch];
    int32_t lastR = (ch > 1) ? samples[(totalFrames - 1) * ch + 1] : lastL;
    if (g_boundaryInitialized) {
        int64_t deltaL = (int64_t)firstL - (int64_t)g_lastSampleL;
        int64_t deltaR = (int64_t)firstR - (int64_t)g_lastSampleR;
        if (deltaL < 0) deltaL = -deltaL;
        if (deltaR < 0) deltaR = -deltaR;
        // 50% of int32 range = 1073741824
        if (deltaL > 1073741824LL || deltaR > 1073741824LL) {
            g_boundaryBreakCount++;
            LOGW("BOUNDARY_BREAK #%lld: prevL=%d→%d (Δ%lld) prevR=%d→%d (Δ%lld)",
                 (long long)g_boundaryBreakCount,
                 g_lastSampleL, firstL, (long long)deltaL,
                 g_lastSampleR, firstR, (long long)deltaR);
        }
    }
    g_boundaryInitialized = true;
    g_lastSampleL = lastL;
    g_lastSampleR = lastR;
}
```

**Result**: Only triggered during track transitions (expected — different audio
content). Zero triggers during continuous playback, confirming the residual
buffer and short URB prevention work correctly.

**Cost**: ~2µs per write call (4 array accesses). Negligible individually but
adds to cumulative hot-path overhead.

---

## 3. Queue Level Monitoring (streaming thread)

Logs when the USB streaming thread's queue is nearly empty, indicating
ExoPlayer isn't delivering data fast enough.

**Where**: Consumer loop in `UsbStreamingThread.kt`.

```kotlin
val qBefore = audioQueue.size
when (val buf = audioQueue.poll(POLL_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
    is AudioBuffer.FloatBuffer -> {
        usbStream.write(buf.data)
        if (qBefore <= 1) Log.w(TAG, "Queue nearly empty: $qBefore before write")
    }
    is AudioBuffer.RawBuffer -> {
        usbStream.writeRaw(buf.data, buf.encoding)
        if (qBefore <= 1) Log.w(TAG, "Queue nearly empty: $qBefore before writeRaw")
    }
    null -> Log.w(TAG, "Queue EMPTY — poll timeout")
}
```

**Result**: Revealed that on iBasso DX340 at 96kHz+, the queue stays at 0-1
entries (decoder runs at ~1x real-time). On S26 Ultra, queue stabilizes at
10-16 entries (decoder runs at 3-5x). This was the key evidence that the
bottleneck is ExoPlayer's pipeline throughput, not the USB driver.

**Cost**: One `audioQueue.size` call per buffer (~1µs). Safe to keep in
production if needed.

---

## 4. xHCI Trace Capture (requires root)

Kernel-level USB tracing that shows individual URB submissions and completions.
This was the tool that revealed the short URB problem (the root cause of pops).

```bash
# Enable tracing
adb shell "su -c '
echo 0 > /sys/kernel/debug/tracing/tracing_on
echo 0 > /sys/kernel/debug/tracing/trace
echo 1 > /sys/kernel/debug/tracing/events/xhci-hcd/xhci_urb_giveback/enable
echo 1 > /sys/kernel/debug/tracing/events/xhci-hcd/xhci_urb_enqueue/enable
echo 32768 > /sys/kernel/debug/tracing/buffer_size_kb
echo 1 > /sys/kernel/debug/tracing/tracing_on
'"

# Capture N seconds, then stop
sleep 15
adb shell "su -c 'echo 0 > /sys/kernel/debug/tracing/tracing_on'"

# Extract and analyze
adb shell "su -c 'cat /sys/kernel/debug/tracing/trace'" | grep "ep1out" > trace.txt

# URB sizes (should only be 352/360 at 44.1kHz, 768/776 at 96kHz)
grep "giveback" trace.txt | grep -o 'length [0-9]*/[0-9]*' | \
  cut -d' ' -f2 | cut -d'/' -f1 | sort | uniq -c | sort -rn

# Enqueue gaps >50ms (indicates streaming thread stalls)
grep "enqueue" trace.txt | awk '{print $4}' | \
  awk 'NR>1{d=($1-prev)*1000; if(d>50) printf "GAP %.0fms\n", d} {prev=$1}'

# Giveback timing (should be ~1ms at 44.1kHz, ~0.75ms at 96kHz)
grep "giveback" trace.txt | head -20 | awk '{print $4}' | \
  awk 'NR>1{printf "Δ%.3fms\n", ($1-prev)*1000} {prev=$1}'
```

**Key findings from xHCI traces**:
- Short URBs (312-344 bytes instead of 352/360) created empty ISO microframes → pops
- A reference app had zero short URBs and consistent URB sizes
- Our enqueue pattern showed bursts (gap → rapid submissions) vs reference app's even pattern
- After the short URB fix: zero short URBs, timing within ±0.04ms

---

## 5. Feedback Oscillation Monitor

Logs when the DAC's async feedback endpoint reports a changed clock rate.
Useful for verifying continuous feedback is working.

**Where**: `handleFeedbackCompletion()` in `usb-audio-output.cpp`.

```cpp
// Already in production (reduced logging frequency):
if (g_feedbackCount % 10000 == 0) {
    LOGI("Feedback #%lld: fpmf=%.4f (%.1f Hz)",
         (long long)g_feedbackCount, newFpmf, newFpmf * 8000.0);
}

// Verbose version (for debugging clock drift):
double delta = newFpmf - ctx->calibratedFpmf;
if (g_feedbackCount % 1000 == 0 || (delta > 0.0001 || delta < -0.0001)) {
    LOGI("Feedback #%lld: fpmf=%.4f (%.1f Hz) delta=%.6f",
         (long long)g_feedbackCount, newFpmf, newFpmf * 8000.0, delta);
}
```

**Result**: Cayin RU7 oscillates between 2-3 fpmf values (LSB toggling in
Q16.16 feedback format). At 44.1kHz: 5.5126/5.5127. At 96kHz: 12.0002/12.0004/12.0005.
This is normal DAC behavior. The oscillation has no effect on packet sizes
(integer truncation produces identical results).

**Warning**: The verbose version with delta logging fires ~1000/sec at 96kHz,
which severely impacts audio thread performance. Use the 10000th-only version
in production.
