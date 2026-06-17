package com.meteor.kikoeruflutter

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.AuxEffectInfo
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.AudioSink.Listener
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Custom [AudioSink] that routes decoded PCM audio directly to the USB DAC
 * via the libusb native driver, bypassing the Android audio mixer entirely.
 *
 * This provides TRUE bit-perfect output — no software mixing, no sample rate
 * conversion, no digital gain processing. Audio data flows:
 *   ExoPlayer decoder → handleBuffer() → JNI → libusb → USB DAC (hardware)
 *
 * Unlike [AaudioAudioSink], this sink does NOT create or manage its own
 * native player. It relies on [UsbDacPlugin] to manage the USB DAC connection
 * lifecycle (open, start, stop, close). This sink only writes PCM data to
 * the already-connected USB DAC via static JNI methods.
 *
 * Bit-perfect is always enabled (no volume gain applied) because libusb
 * output is inherently bit-perfect — the Android mixer is not involved.
 *
 * @see UsbDacPlugin.getCurrentDriverPtr
 * @see UsbDacPlugin.nativeWritePcmFloatStatic
 * @see UsbDacPlugin.nativeWritePcmI16Static
 */
@UnstableApi
class LibusbAudioSink : AudioSink {

    companion object {
        private const val TAG = "LibusbAudioSink"

        /** Log every N-th handleBuffer call for throttled throughput tracking. */
        private const val THROTTLE_LOG_INTERVAL_MS = 5000L // 5 seconds

        /** Per-second [FORMAT-STATS] log interval for encoding-aware diagnostics. */
        private const val FORMAT_STATS_INTERVAL_MS = 1000L // 1 second

    }

    // ── State ──
    private var listener: Listener? = null
    private var sampleRate: Int = 0
    private var channelCount: Int = 2
    private var pcmEncoding: Int = C.ENCODING_PCM_16BIT
    private var bytesPerFrame: Int = 4
    private var playing = false
    private var configured = false
    private var ended = false
    private var lastPresentationTimeUs: Long = 0
    private var playbackParameters = PlaybackParameters.DEFAULT

    init {
        Log.i("USBPCM", "LIBUSB_SINK_CONSTRUCTED")
    }

    // ── Monotonic call counters for starvation detection ──
    private var handleBufferCallCount: Long = 0      // Total handleBuffer calls (monotonic)
    private var totalFramesWritten: Long = 0          // Total frames written to native driver
    private var totalWriteTimeUs: Long = 0             // Cumulative time spent in JNI write
    private var lastHandleBufferTimestampMs: Long = 0  // Timestamp of last handleBuffer call

    // ── Throttled logging accumulators (reset every THROTTLE_LOG_INTERVAL_MS) ──
    private var totalFramesSinceLastLog = 0L
    private var totalBytesSinceLastLog = 0L
    private var lastThrottleLogMs: Long = 0L
    private var handleBufferCallsSinceLastLog = 0
    private var dacDisconnectedCalls = 0
    private var writeErrorCalls = 0

    // ── [FORMAT-STATS] per-second accumulators ──
    private var lastFormatStatsLogMs: Long = 0L
    private var statsFramesAtLastLog: Long = 0L

    // ── AudioSink implementation ──

    override fun configure(
        inputFormat: Format,
        specifiedBufferSize: Int,
        outputChannels: IntArray?
    ) {
        val encodingName = when (inputFormat.pcmEncoding) {
            C.ENCODING_PCM_16BIT -> "PCM_16BIT"
            C.ENCODING_PCM_24BIT -> "PCM_24BIT"
            C.ENCODING_PCM_32BIT -> "PCM_32BIT"
            C.ENCODING_PCM_FLOAT -> "PCM_FLOAT"
            else -> "UNKNOWN(${inputFormat.pcmEncoding})"
        }
        Log.i(TAG, "═ configure(" +
                "sampleRate=${inputFormat.sampleRate}Hz, " +
                "channels=${inputFormat.channelCount}, " +
                "encoding=$encodingName, " +
                "specifiedBufferSize=$specifiedBufferSize, " +
                "outputChannels=${outputChannels?.contentToString()})")

        sampleRate = inputFormat.sampleRate
        channelCount = outputChannels?.size ?: inputFormat.channelCount
        pcmEncoding = inputFormat.pcmEncoding

        val bytesPerSample = when (pcmEncoding) {
            C.ENCODING_PCM_16BIT -> 2
            C.ENCODING_PCM_24BIT -> 3
            C.ENCODING_PCM_32BIT -> 4
            C.ENCODING_PCM_FLOAT -> 4
            else -> 2
        }
        bytesPerFrame = bytesPerSample * channelCount

        Log.i(TAG, "  → bytesPerFrame=$bytesPerFrame, " +
                "configured=true, ended=false")

        // ── [PCM16] trace ──
        if (pcmEncoding == C.ENCODING_PCM_16BIT) {
            Log.i(TAG, "[PCM16] configure(): sampleRate=${inputFormat.sampleRate}Hz, " +
                    "channels=$channelCount, bytesPerFrame=$bytesPerFrame, encoding=PCM_16BIT")
        }

        configured = true
        ended = false
        listener?.onPositionDiscontinuity()
    }

    override fun handleBuffer(
        buffer: ByteBuffer,
        presentationTimeUs: Long,
        encodedAccessUnitCount: Int
    ): Boolean {
        val nowMs = System.currentTimeMillis()
        if (lastThrottleLogMs == 0L) {
            lastThrottleLogMs = nowMs
        }

        // ── Monotonic call counter + gap detection ──
        handleBufferCallCount++
        handleBufferCallsSinceLastLog++
        val gapMs = if (lastHandleBufferTimestampMs > 0) (nowMs - lastHandleBufferTimestampMs) else 0L
        lastHandleBufferTimestampMs = nowMs

        val remaining = buffer.remaining()
        val numFrames = if (remaining > 0 && bytesPerFrame > 0) remaining / bytesPerFrame else 0
        val alignmentRemainder = if (bytesPerFrame > 0) remaining % bytesPerFrame else 0

        // ── ByteBuffer diagnostic ──
        val bufPos = buffer.position()
        val bufLim = buffer.limit()
        val bufCap = buffer.capacity()
        val expectedBytes = numFrames * bytesPerFrame
        val droppedBytes = remaining - expectedBytes

        Log.i(TAG, "[HB#$handleBufferCallCount] enter: " +
                "ts=${nowMs}ms, " +
                "gap=${gapMs}ms, " +
                "frames=$numFrames, " +
                "bytes=$remaining, " +
                "bpf=$bytesPerFrame, " +
                "rem%bps=$alignmentRemainder, " +
                "expectBytes=$expectedBytes, " +
                "dropBytes=$droppedBytes, " +
                "bufPos=$bufPos, bufLim=$bufLim, bufCap=$bufCap, " +
                "pts=${presentationTimeUs}us, " +
                "play=$playing, " +
                "ended=$ended")

        if (alignmentRemainder != 0) {
            Log.w(TAG, "[FRAME-ALIGN] HB#$handleBufferCallCount: " +
                    "remaining=$remaining NOT aligned to bytesPerFrame=$bytesPerFrame " +
                    "(remainder=$alignmentRemainder, frames=$numFrames, expected=$expectedBytes)")
        }

        if (remaining <= 0) {
            Log.v(TAG, "[HB#$handleBufferCallCount] empty buffer — returning true")
            return true
        }
        if (numFrames <= 0) {
            Log.v(TAG, "[HB#$handleBufferCallCount] incomplete frame (remaining=$remaining, bpf=$bytesPerFrame)")
            return true
        }

        totalFramesSinceLastLog += numFrames
        totalBytesSinceLastLog += remaining

        val ptr = UsbDacPlugin.getCurrentDriverPtr()
        if (ptr == 0L) {
            dacDisconnectedCalls++
            Log.w(TAG, "[HB#$handleBufferCallCount] DAC not connected — draining ${remaining}B")
            buffer.position(buffer.limit())
            return true
        }

        lastPresentationTimeUs = presentationTimeUs

        // ── [PCM16] trace: confirm encoding dispatch ──
        if (pcmEncoding == C.ENCODING_PCM_16BIT) {
            Log.i(TAG, "[PCM16] handleBuffer #$handleBufferCallCount: " +
                    "dispatching to writeI16(), frames=$numFrames, bytes=$remaining, " +
                    "sampleRate=$sampleRate, channels=$channelCount, ptr=0x${ptr.toString(16)}")
        } else {
            Log.i(TAG, "[PCM16] handleBuffer #$handleBufferCallCount: " +
                    "pcmEncoding=$pcmEncoding (NOT PCM_16BIT), skipping [PCM16] trace")
        }

        // ── [KOTLIN-AUDIO] Trace format reaching JNI ──
        val audioEncodingName = when (pcmEncoding) {
            C.ENCODING_PCM_16BIT -> "PCM16"
            C.ENCODING_PCM_24BIT -> "PCM24"
            C.ENCODING_PCM_32BIT -> "PCM32"
            C.ENCODING_PCM_FLOAT -> "FLOAT32"
            else -> "UNKNOWN(${pcmEncoding})"
        }
        Log.i(TAG, "[KOTLIN-AUDIO] encoding=$audioEncodingName " +
                "sampleRate=${sampleRate}Hz " +
                "channelCount=$channelCount " +
                "bytesPerFrame=$bytesPerFrame " +
                "buffer.remaining()=$remaining " +
                "numFrames=$numFrames " +
                "presentationTimeUs=${presentationTimeUs}us")

        // ── Write start timestamp for latency measurement ──
        val writeStartUs = System.nanoTime() / 1000

        val written = when (pcmEncoding) {
            C.ENCODING_PCM_16BIT -> writeI16(buffer, ptr, numFrames)
            C.ENCODING_PCM_FLOAT -> writeFloat(buffer, ptr, numFrames)
            C.ENCODING_PCM_32BIT -> writeFloat32Bit(buffer, ptr, numFrames)
            C.ENCODING_PCM_24BIT -> writePcm24AsPcm16(buffer, ptr, numFrames)
            else -> writeI16(buffer, ptr, numFrames)
        }
        val writtenFrames = written

        // ── Advance buffer position by actually-written frames ──
        // writeI16() uses duplicate() to read data, which does NOT advance
        // the original buffer's position. We must advance it manually so the
        // drain loop reads the CORRECT remaining frames, not the same ones.
        // Without this, every short write causes: frames 0-3839 written once,
        // frames 0-479 written AGAIN (duplicated), frames 3840-4409 LOST.
        val consumedBytes = if (written > 0) written * bytesPerFrame else 0
        if (consumedBytes > 0) {
            buffer.position(buffer.position() + consumedBytes)
        }

        val writeEndUs = System.nanoTime() / 1000
        val writeDurationUs = writeEndUs - writeStartUs
        totalWriteTimeUs += writeDurationUs

        totalFramesWritten += writtenFrames
        Log.i(TAG, "[HB#$handleBufferCallCount] write result: " +
                "requested=$numFrames frames, " +
                "written=$writtenFrames frames, " +
                "totalWritten=$totalFramesWritten, " +
                "duration=${writeDurationUs}us, " +
                "avgWrite=${if (handleBufferCallCount > 0) totalWriteTimeUs / handleBufferCallCount else 0}us/call")

        if (written < 0) {
            writeErrorCalls++
            Log.e(TAG, "[HB#$handleBufferCallCount] write ERROR=$written")
            return false
        }

        if (written < numFrames) {
            val consumedFrames = if (written > 0) written else 0
            val remainingFrames = numFrames - consumedFrames
            Log.w(TAG, "[HB#$handleBufferCallCount] short write ($consumedFrames/$numFrames) — draining $remainingFrames frames")
            var drained = 0
            var loopCount = 0
            val maxLoops = 50
            while (drained < remainingFrames && loopCount < maxLoops) {
                val drainFrames = remainingFrames - drained
                val drainPtr = UsbDacPlugin.getCurrentDriverPtr()
                if (drainPtr == 0L) break
                val drainWritten = when (pcmEncoding) {
                    C.ENCODING_PCM_16BIT -> writeI16(buffer, drainPtr, drainFrames)
                    C.ENCODING_PCM_FLOAT -> writeFloat(buffer, drainPtr, drainFrames)
                    C.ENCODING_PCM_32BIT -> writeFloat32Bit(buffer, drainPtr, drainFrames)
                    C.ENCODING_PCM_24BIT -> writePcm24AsPcm16(buffer, drainPtr, drainFrames)
                    else -> writeI16(buffer, drainPtr, drainFrames)
                }
                // Advance buffer position for each drain write too
                if (drainWritten > 0) {
                    buffer.position(buffer.position() + drainWritten * bytesPerFrame)
                }
                drained += drainWritten
                loopCount++
                if (drainWritten <= 0) break
            }
            Log.i(TAG, "[HB#$handleBufferCallCount] drain: drained=$drained/${remainingFrames} in $loopCount loops")
        }

        // ── Per-second [FORMAT-STATS] logging (encoding-aware) ──
        // Logs write rate, frame count, and encoding at 1-second intervals.
        // Use this to compare PCM16 vs PCM24 vs FLOAT production rates.
        if (lastFormatStatsLogMs == 0L) lastFormatStatsLogMs = nowMs
        if (nowMs - lastFormatStatsLogMs >= FORMAT_STATS_INTERVAL_MS) {
            val elapsedSec = (nowMs - lastFormatStatsLogMs) / 1000.0
            val framesDelta = totalFramesWritten - statsFramesAtLastLog
            val writeRate = if (elapsedSec > 0) (framesDelta / elapsedSec).toLong() else 0L
            val encodingName = when (pcmEncoding) {
                C.ENCODING_PCM_16BIT -> "PCM16"
                C.ENCODING_PCM_24BIT -> "PCM24"
                C.ENCODING_PCM_32BIT -> "PCM32"
                C.ENCODING_PCM_FLOAT -> "FLOAT"
                else -> "UNKNOWN(${pcmEncoding})"
            }

            Log.i(TAG, "[FORMAT-STATS] encoding=$encodingName " +
                    "writeRate=${writeRate}fps " +
                    "totalFramesWritten=$totalFramesWritten " +
                    "framesDelta=$framesDelta " +
                    "hbCalls=$handleBufferCallCount " +
                    "sampleRate=${sampleRate}Hz " +
                    "channels=$channelCount " +
                    "playing=$playing")

            lastFormatStatsLogMs = nowMs
            statsFramesAtLastLog = totalFramesWritten
        }

        // Throttled throughput logging every THROTTLE_LOG_INTERVAL_MS
        if (nowMs - lastThrottleLogMs >= THROTTLE_LOG_INTERVAL_MS) {
            val elapsedSec = (nowMs - lastThrottleLogMs) / 1000.0
            val framesPerSec = if (elapsedSec > 0) (totalFramesSinceLastLog / elapsedSec).toLong() else 0L
            val bytesPerSec = if (elapsedSec > 0) (totalBytesSinceLastLog / elapsedSec).toLong() else 0L

            Log.i(TAG, "[HB-HEALTH] period=${elapsedSec.toInt()}s: " +
                    "hbCalls=$handleBufferCallsSinceLastLog, " +
                    "totalHBCalls=$handleBufferCallCount, " +
                    "totalFramesWritten=$totalFramesWritten, " +
                    "periodFrames=$totalFramesSinceLastLog (${framesPerSec}fps), " +
                    "periodBytes=$totalBytesSinceLastLog (${bytesPerSec}B/s), " +
                    "writeDuration=${totalWriteTimeUs}us, " +
                    "avgGap=${if (handleBufferCallsSinceLastLog > 0) gapMs else 0}ms, " +
                    "dacDrains=$dacDisconnectedCalls, " +
                    "writeErrors=$writeErrorCalls")

            // Reset accumulators
            totalFramesSinceLastLog = 0L
            totalBytesSinceLastLog = 0L
            handleBufferCallsSinceLastLog = 0
            totalWriteTimeUs = 0L
            lastThrottleLogMs = nowMs
            lastFormatStatsLogMs = 0L
            statsFramesAtLastLog = totalFramesWritten
        }

        return written >= numFrames
    }

    override fun play() {
        Log.i(TAG, "[STATE] play() — playing=$playing → true, hbCalls=$handleBufferCallCount")
        playing = true
        listener?.onPositionDiscontinuity()
    }

    override fun pause() {
        Log.i(TAG, "[STATE] pause() — playing=$playing → false, hbCalls=$handleBufferCallCount")
        playing = false
    }

    override fun flush() {
        Log.i(TAG, "[STATE] flush() — " +
                "playing=$playing, ended=$ended, " +
                "hbCalls=$handleBufferCallCount, " +
                "framesWritten=$totalFramesWritten")
        playing = false
        ended = false
        // Reset throttled logging on flush
        totalFramesSinceLastLog = 0L
        totalBytesSinceLastLog = 0L
        handleBufferCallsSinceLastLog = 0
        dacDisconnectedCalls = 0
        writeErrorCalls = 0
        lastThrottleLogMs = 0L
        listener?.onPositionDiscontinuity()
    }

    override fun reset() {
        Log.i(TAG, "[STATE] reset() — " +
                "playing=$playing, configured=$configured, ended=$ended, " +
                "hbCalls=$handleBufferCallCount, framesWritten=$totalFramesWritten")
        playing = false
        configured = false
        ended = false
        // Reset all accumulators
        totalFramesSinceLastLog = 0L
        totalBytesSinceLastLog = 0L
        handleBufferCallsSinceLastLog = 0
        dacDisconnectedCalls = 0
        writeErrorCalls = 0
        lastThrottleLogMs = 0L
        handleBufferCallCount = 0L
        totalFramesWritten = 0L
        totalWriteTimeUs = 0L
        lastHandleBufferTimestampMs = 0L
    }

    override fun playToEndOfStream() {
        Log.i(TAG, "[STATE] playToEndOfStream() — ended=false → true, hbCalls=$handleBufferCallCount")
        ended = true
    }

    override fun isEnded(): Boolean {
        val result = ended
        if (result) Log.v(TAG, "[QUERY] isEnded()=$result")
        return result
    }

    override fun handleDiscontinuity() {
        Log.i(TAG, "[STATE] handleDiscontinuity() — hbCalls=$handleBufferCallCount")
    }

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        val pos = lastPresentationTimeUs
        Log.v(TAG, "[QUERY] getCurrentPositionUs(sourceEnded=$sourceEnded) = ${pos}us (${pos/1000}ms)")
        return pos
    }

    override fun setListener(listener: Listener) {
        Log.i(TAG, "[STATE] setListener(${listener::class.java.simpleName})")
        this.listener = listener
    }

    override fun setAudioSessionId(audioSessionId: Int) {
        Log.v(TAG, "setAudioSessionId($audioSessionId) — N/A for libusb")
    }

    override fun setVolume(volume: Float) {
        Log.v(TAG, "setVolume($volume) — ignored (bit-perfect)")
    }

    private var formatSupportQueried = false

    override fun getFormatSupport(format: Format): Int {
        val encodingName = when (format.pcmEncoding) {
            C.ENCODING_PCM_16BIT -> "PCM_16BIT"
            C.ENCODING_PCM_24BIT -> "PCM_24BIT"
            C.ENCODING_PCM_32BIT -> "PCM_32BIT"
            C.ENCODING_PCM_FLOAT -> "PCM_FLOAT"
            else -> "UNKNOWN(${format.pcmEncoding})"
        }
        val supported = when (format.pcmEncoding) {
            C.ENCODING_PCM_16BIT,
            C.ENCODING_PCM_24BIT,
            C.ENCODING_PCM_32BIT -> FORMAT_HANDLED
            C.ENCODING_PCM_FLOAT -> {
                Log.w(TAG, "[QUERY] getFormatSupport(PCM_FLOAT) = UNSUPPORTED (diagnostic test — forcing PCM16 fallback)")
                FORMAT_UNSUPPORTED_TYPE
            }
            else -> FORMAT_UNSUPPORTED_TYPE
        }
        if (!formatSupportQueried) {
            formatSupportQueried = true
            Log.i(TAG, "[QUERY] getFormatSupport($encodingName) = ${if (supported == FORMAT_HANDLED) "HANDLED" else "UNSUPPORTED"}")
        }
        return supported
    }

    override fun supportsFormat(format: Format): Boolean =
        getFormatSupport(format) == FORMAT_HANDLED

    override fun hasPendingData(): Boolean {
        Log.v(TAG, "[QUERY] hasPendingData()=false — hbCalls=$handleBufferCallCount")
        return false
    }

    override fun setPlaybackParameters(params: PlaybackParameters) {
        playbackParameters = params
    }

    override fun getPlaybackParameters(): PlaybackParameters = playbackParameters

    override fun setSkipSilenceEnabled(enabled: Boolean) { /* N/A */ }

    override fun getSkipSilenceEnabled(): Boolean = false

    override fun setAudioAttributes(audioAttributes: androidx.media3.common.AudioAttributes) { /* N/A */ }

    override fun getAudioAttributes(): androidx.media3.common.AudioAttributes? = null

    override fun setAuxEffectInfo(auxEffectInfo: AuxEffectInfo) { /* N/A */ }

    override fun enableTunnelingV21() { /* N/A */ }

    override fun disableTunneling() { /* N/A */ }

    // ── Format constants ──

    private val FORMAT_HANDLED = 0
    private val FORMAT_UNSUPPORTED_TYPE = 1

    // ── PCM write helpers ──

    /**
     * Write 16-bit PCM data to the USB DAC via libusb.
     * No volume gain is applied — bit-perfect output is always preserved.
     *
     * Writes directly to the native ring buffer on every call.
     * The ring buffer naturally accumulates small writes from handleBuffer()
     * and the USB isochronous transfer callback consumes them in 1920-byte
     * reads. This provides a steady stream of data to the USB DAC.
     */
    private fun writeI16(buffer: ByteBuffer, ptr: Long, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val consumedBytes = numFrames * bytesPerFrame
        val bufBeforePos = buffer.position()
        val bufBeforeRem = buffer.remaining()

        Log.i(TAG, "[PCM16] [ENTER] writeI16: frames=$numFrames, samples=$totalSamples, " +
                "ptr=0x${ptr.toString(16)}, " +
                "bufPos=$bufBeforePos, bufRem=$bufBeforeRem, " +
                "consumeBytes=$consumedBytes, consumeShorts=$totalSamples")

        val shorts = ShortArray(totalSamples)
        // ── CRITICAL: Use duplicate() to read without advancing original buffer position ──
        // asShortBuffer().get() advances the ShortBuffer's position but does NOT
        // advance the original ByteBuffer's position via duplicate(). However, calling
        // buffer.order().asShortBuffer() directly DOES create a view that shares state
        // with the original buffer — and advancing that view DOES advance the original!
        // Using duplicate() ensures the original buffer's position stays untouched,
        // allowing the drain loop in handleBuffer to retry the same data on short writes.
        // Without this, short writes cause BufferUnderflowException in the drain loop.
        val dup = buffer.duplicate().order(ByteOrder.nativeOrder())
        val shortBuf = dup.asShortBuffer()
        val shortBufBeforePos = shortBuf.position()
        shortBuf.get(shorts)
        val shortBufAfterPos = shortBuf.position()
        val dupPos = dup.position()

        val bufAfterRem = buffer.remaining()
        Log.i(TAG, "[PCM16] [BBUF] writeI16: shortBuf=$shortBufBeforePos→$shortBufAfterPos, " +
                "bufPos orig=$bufBeforePos (unchanged), " +
                "bufRem=$bufBeforeRem→$bufAfterRem, " +
                "dupPos=$dupPos")

        Log.i(TAG, "[PCM16] [JNI] calling nativeWritePcmI16Static(ptr=0x${ptr.toString(16)}, " +
                "shorts.size=${shorts.size}, numFrames=$numFrames)")
        val written = UsbDacPlugin.nativeWritePcmI16Static(ptr, shorts, numFrames)
        Log.i(TAG, "[PCM16] [EXIT] writeI16: returned=$written (frames=$numFrames)")
        if (written < 0) {
            Log.e(TAG, "✗ writeI16: JNI returned $written (frames=$numFrames, samples=$totalSamples)")
        }
        return written
    }

    /**
     * Write 32-bit float PCM data to the USB DAC via libusb.
     * No volume gain is applied — bit-perfect output is always preserved.
     */
    private fun writeFloat(buffer: ByteBuffer, ptr: Long, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val floatBuf = FloatArray(totalSamples)
        // Use duplicate() to avoid advancing original buffer position — consistent with
        // writeI16() and other write functions. Without this, handleBuffer's drain loop
        // position advancement would double-advance and skip data when FLOAT is enabled.
        buffer.duplicate().order(ByteOrder.nativeOrder()).asFloatBuffer().get(floatBuf, 0, totalSamples)
        // No volume gain — always bit-perfect
        val written = UsbDacPlugin.nativeWritePcmFloatStatic(ptr, floatBuf, numFrames)
        if (written < 0) {
            Log.e(TAG, "✗ writeFloat: JNI returned $written (frames=$numFrames, samples=$totalSamples)")
        }
        return written
    }

    /**
     * Write 32-bit integer PCM data to the USB DAC.
     * Converts from int32_t to float32 for the native driver.
     */
    private fun writeFloat32Bit(buffer: ByteBuffer, ptr: Long, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val intBuffer = buffer.duplicate().order(ByteOrder.nativeOrder()).asIntBuffer()
        val ints = IntArray(totalSamples)
        intBuffer.get(ints, 0, totalSamples)
        val floatBuf = FloatArray(totalSamples)
        for (i in 0 until totalSamples) {
            floatBuf[i] = ints[i] / 2147483648.0f
        }
        val written = UsbDacPlugin.nativeWritePcmFloatStatic(ptr, floatBuf, numFrames)
        if (written < 0) {
            Log.e(TAG, "✗ writeFloat32Bit: JNI returned $written (frames=$numFrames, samples=$totalSamples)")
        }
        return written
    }

    /**
     * Write 24-bit PCM data to the USB DAC via libusb — **direct 24-bit path**.
     *
     * Sends the raw 24-bit packed bytes directly to the native driver,
     * bypassing the float32 conversion entirely. The C++ layer writes
     * 24-bit data straight into the ring buffer without precision loss.
     *
     * ⚡ BYPASSES: PCM_24BIT → float32 → integer pipeline
     * ✅ DIRECT:  PCM_24BIT packed bytes → native writePcm24() → ring buffer
     */
    /**
     * TEMPORARY ISOLATION TEST: Route PCM_24BIT through PCM16 path.
     *
     * Converts 24-bit packed samples (3 bytes LE, signed) to 16-bit
     * (2 bytes LE, signed) by truncating the least significant byte,
     * then writes via the PCM16 native path.
     *
     * Purpose: Isolate whether the continuous crackling/static is caused
     * by PCM24 packing format or by USB transfer timing.
     *
     * - If PCM16 is CLEAN → bug is in 24-bit packing (likely subframe size)
     * - If PCM16 still crackling → USB timing issue
     *
     * Conversion: 24-bit signed LE → keep top 16 bits
     *   24-bit [byte0_LSB, byte1, byte2_MSB] → 16-bit [byte1, byte2]
     */
    private fun writePcm24AsPcm16(buffer: ByteBuffer, ptr: Long, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val shorts = ShortArray(totalSamples)
        // Use duplicate() to avoid advancing the original buffer's position
        // (critical for the drain loop in handleBuffer).
        val dup = buffer.duplicate().order(ByteOrder.nativeOrder())
        for (i in 0 until totalSamples) {
            // Read 3 bytes of 24-bit LE signed sample
            val b0 = dup.get().toInt() and 0xFF   // LSB (discarded)
            val b1 = dup.get().toInt() and 0xFF   // middle byte
            val b2 = dup.get().toInt()             // MSB (signed byte, sign-extended)
            // Truncate to 16-bit: keep b2 (MSB) and b1, drop b0 (LSB)
            // b2 is already sign-extended by .toInt()
            shorts[i] = ((b2 shl 8) or b1).toShort()
        }

        Log.i(TAG, "[PCM16-TEST] writePcm24AsPcm16: " +
                "24-bit → 16-bit conversion, frames=$numFrames, samples=$totalSamples")

        val written = UsbDacPlugin.nativeWritePcmI16Static(ptr, shorts, numFrames)
        if (written < 0) {
            Log.e(TAG, "✗ writePcm24AsPcm16: JNI returned $written (frames=$numFrames)")
        }
        return written
    }

    /**
     * Write 24-bit PCM data to the USB DAC via libusb — **direct 24-bit path**.
     *
     * Sends the raw 24-bit packed bytes directly to the native driver,
     * bypassing the float32 conversion entirely. The C++ layer writes
     * 24-bit data straight into the ring buffer without precision loss.
     *
     * ⚡ BYPASSES: PCM_24BIT → float32 → integer pipeline
     * ✅ DIRECT:  PCM_24BIT packed bytes → native writePcm24() → ring buffer
     */
    private fun writePcm24Bit(buffer: ByteBuffer, ptr: Long, numFrames: Int): Int {
        val totalBytes = numFrames * bytesPerFrame  // bytesPerFrame already = 3 * channelCount
        val byteArray = ByteArray(totalBytes)
        // Use duplicate() to avoid advancing the original buffer's position.
        // This is critical because the drain loop in handleBuffer may call
        // writePcm24Bit again with the same buffer on short write.
        // Without duplicate(), buffer.get() advances position and causes
        // BufferUnderflowException on retry.
        buffer.duplicate().order(ByteOrder.nativeOrder()).get(byteArray, 0, totalBytes)

        Log.i(TAG, "[USB-PIPELINE] writePcm24Bit: " +
                "24-bit packed bytes → direct native writePcm24() (NO float conversion!), " +
                "frames=$numFrames, bytes=$totalBytes")

        val written = UsbDacPlugin.nativeWritePcm24Static(ptr, byteArray, numFrames)
        if (written < 0) {
            Log.e(TAG, "✗ writePcm24Bit: JNI returned $written (frames=$numFrames, bytes=$totalBytes)")
        }
        return written
    }
}
