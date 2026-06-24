# 12. USB Audio Pops Resolution

## Symptom

Subtle audio clicks/pops every 4-6 seconds during playback via USB DAC. Initially observed on 16-bit 44.1kHz content (Adele), later confirmed on 24-bit as well. Present on both Samsung S26 Ultra and iBasso DX340. Not present with another USB audio app on the same hardware.

## Investigation Methodology

### xHCI Trace Capture (iBasso DX340 with root)

The breakthrough came from comparing kernel-level xHCI traces between our app and a reference USB audio app:

```bash
# Enable xHCI tracing
adb shell "su -c '
echo 1 > /sys/kernel/debug/tracing/events/xhci-hcd/xhci_urb_giveback/enable
echo 1 > /sys/kernel/debug/tracing/events/xhci-hcd/xhci_urb_enqueue/enable
echo 1 > /sys/kernel/debug/tracing/tracing_on
'"
# Capture 15 seconds, then stop and read
```

### Reference App Comparison

Captured a reference USB audio app's behavior on the same iBasso DX340 + Cayin RU7 setup:

| Parameter | Reference app | Our driver (before) |
|-----------|------|---------------------|
| URB sizes (44.1kHz) | 920/928 bytes | 352/360 + **312-344 short** |
| URBs in flight | 76-78 | 48 |
| Feedback reading | Continuous (~1000/sec) | Once at start |
| Short URBs | 0 | **220 in 15 seconds** |
| Dedicated feedback thread | Yes ("send USB") | No |

## Root Cause: Truncated ISO Packets

The xHCI trace revealed **220 short URBs (312-344 bytes)** in 15 seconds of playback, compared to zero in the reference app:

```
=== GIVEBACK SIZES (before fix) ===
  18280 352    (89.2%)
   1982 360    (9.7%)
    220 312    (1.1%)  ← THE CAUSE
```

### Why short URBs cause pops

Each URB contains 8 ISO packets, one per USB microframe (125us). When a URB has fewer than 8 full-size packets, the remaining microframes are **empty** — the xHCI transmits zero data for those slots. The DAC receives silence for those 125us gaps, causing an audible click.

### Why short URBs were being created

At the end of each `nativeWriteRaw()` call, the remaining PCM data often couldn't fill a complete 8-packet URB. The code had two bugs:

**Bug 1: Truncated last packet**
```cpp
if (b > remaining) {
    b = (remaining / ctx->bytesPerFrame) * ctx->bytesPerFrame;
    if (b <= 0) break;
    // ^^^ This truncated the last packet to fewer frames than expected
}
```

A URB with 8 packets where the last packet is truncated (e.g., 2 frames instead of 5-6) still has `numPackets == 8`, bypassing the short URB check. But the total URB size is significantly smaller, and the last ISO packet carries far less data than the DAC expects.

**Bug 2: Residual buffer too small for high sample rates**
```cpp
uint8_t residualBuffer[16];  // Only 16 bytes!
// Later increased to 512, but still too small for 96kHz+
```

At 96kHz stereo 32-bit, a partial URB can be ~672 bytes. With a 512-byte residual buffer, leftover data exceeding 512 bytes was **silently dropped** — causing even larger gaps in the audio stream. This manifested as the music completely stopping on the iBasso DX340 at 24-bit/96kHz.

## Fixes Applied

### Fix 1: Never truncate ISO packets

Instead of truncating the last packet when data runs out, stop filling the URB and save the remaining data:

```cpp
if (b > remaining) {
    // Don't truncate — save remaining data for next call
    break;
}
```

Combined with the short URB check that was already in place:

```cpp
if (numPackets < USB_AUDIO_PACKETS_PER_URB) {
    // Save leftover to residual buffer instead of sending short URB
    int leftover = dataLen - offset;
    if (leftover > 0 && leftover < (int)sizeof(ctx->residualBuffer)) {
        memcpy(ctx->residualBuffer, data + offset, leftover);
        ctx->residualBytes = leftover;
    }
    break;
}
```

### Fix 2: Residual buffer sized for worst case

```cpp
// In usb-audio-output.h
uint8_t residualBuffer[USB_AUDIO_URB_BUFFER_SIZE];  // 4096 bytes
```

This accommodates partial URBs at any sample rate up to 384kHz.

### Fix 3: Continuous feedback reading

The DAC's async feedback endpoint reports its actual clock frequency. The reference app reads this continuously (~1000/sec). We now do the same, integrated into the URB reap loop:

```cpp
static int reapOldestUrb(UsbAudioContext *ctx, int timeoutMs) {
    // ...
    if (c == ctx->feedbackUrb) {
        handleFeedbackCompletion(ctx);  // Update fpmf + resubmit
        continue;  // Retry — we need an audio URB
    }
    // Audio URB reaped
}
```

The feedback value updates `calibratedFpmf` which controls ISO packet sizes. This tracks the DAC's actual clock in real-time instead of using a single measurement from stream start.

## Results After Fixes

### xHCI trace comparison (15 seconds, 44.1kHz)

```
=== BEFORE ===
  18280 352
   1982 360
    220 312  ← short URBs causing pops

=== AFTER ===
  13732 352
   1550 360
      0 short URBs  ← ELIMINATED
```

### Full validation on Samsung S26 Ultra

- 16-bit 44.1kHz (Adele): Zero pops, zero gaps
- 24-bit 96kHz: Zero pops, zero gaps
- 24-bit 192kHz: Zero pops, zero gaps
- Transitions between sample rates: Clean
- WriteRaw interval: ~1.00s constant (no jitter)
- inflight=80 constant
- Zero URB errors, zero boundary breaks

### iBasso DX340 limitation

The DX340 exhibits periodic audio stalls (3-7 second gaps) at high sample rates (96kHz+). This is **not a USB driver issue** — the xHCI trace is clean when data flows. The stalls are caused by the delegate AudioTrack (muted, used for ExoPlayer clock tracking) blocking `super.handleBuffer()` when the device's CPU/AudioFlinger can't keep up. This is an app architecture issue to be addressed separately.

## Key Insight

The pops were invisible at the application level — all diagnostics showed zero errors:
- URB completion status: 0 (success)
- Pipeline depth: always full (80 URBs in flight)
- No boundary discontinuities in PCM data
- No queue drops in the streaming thread

Only the **kernel-level xHCI trace** revealed the 312-byte URBs that the host controller was dutifully transmitting, creating silence microframes that the DAC output as clicks. Application-level logging cannot detect this class of bug — xHCI tracing is essential.

## Files Modified

| File | Change |
|------|--------|
| `usb-audio-output.h` | `residualBuffer[USB_AUDIO_URB_BUFFER_SIZE]`, `USB_AUDIO_NUM_URBS=80`, feedback URB fields |
| `usb-audio-output.cpp` | No packet truncation, short URB prevention, continuous feedback, feedback URB lifecycle |
| `engine/build.gradle` | Re-enabled `media3-decoder-flac` dependency |
