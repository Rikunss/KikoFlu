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

    // ── Throttled logging accumulators (reset every THROTTLE_LOG_INTERVAL_MS) ──
    private var totalFramesSinceLastLog = 0L
    private var totalBytesSinceLastLog = 0L
    private var lastThrottleLogMs: Long = 0L
    private var handleBufferCallsSinceLastLog = 0
    private var dacDisconnectedCalls = 0
    private var writeErrorCalls = 0

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

        configured = true
        ended = false
        listener?.onPositionDiscontinuity()
    }

    override fun handleBuffer(
        buffer: ByteBuffer,
        presentationTimeUs: Long,
        encodedAccessUnitCount: Int
    ): Boolean {
        // Throttled periodic log
        val nowMs = System.currentTimeMillis()
        if (lastThrottleLogMs == 0L) {
            lastThrottleLogMs = nowMs
        }

        handleBufferCallsSinceLastLog++
        val remaining = buffer.remaining()
        if (remaining <= 0) return true
        val numFrames = remaining / bytesPerFrame
        if (numFrames <= 0) return true

        totalFramesSinceLastLog += numFrames
        totalBytesSinceLastLog += remaining

        // Get the current libusb driver pointer from UsbDacPlugin.
        // Returns 0L if no USB DAC is connected. We handle this gracefully
        // by draining the buffer silently (handles the case where the DAC
        // disconnects mid-playback).
        val ptr = UsbDacPlugin.getCurrentDriverPtr()
        if (ptr == 0L) {
            dacDisconnectedCalls++
            if (dacDisconnectedCalls <= 3 || dacDisconnectedCalls % 50 == 0) {
                Log.w(TAG, "⚠ handleBuffer: DAC not connected (ptr=0) — " +
                        "draining ${remaining}B silently " +
                        "(totalDrainCalls=$dacDisconnectedCalls)")
            }
            // No USB DAC connected — drain buffer silently.
            // The audio will be silent, which is expected since the user
            // intended to use USB DAC output. The fallback to system audio
            // is handled by the routing logic in AudioPlayerService.
            buffer.position(buffer.limit())
            return true
        }

        lastPresentationTimeUs = presentationTimeUs

        val encodingName = when (pcmEncoding) {
            C.ENCODING_PCM_16BIT -> "I16"
            C.ENCODING_PCM_FLOAT -> "FLOAT"
            C.ENCODING_PCM_32BIT -> "I32→FLOAT"
            C.ENCODING_PCM_24BIT -> "I24→FLOAT"
            else -> "I16(default)"
        }

        val written = when (pcmEncoding) {
            C.ENCODING_PCM_16BIT -> writeI16(buffer, ptr, numFrames)
            C.ENCODING_PCM_FLOAT -> writeFloat(buffer, ptr, numFrames)
            C.ENCODING_PCM_32BIT -> writeFloat32Bit(buffer, ptr, numFrames)
            // For 24-bit PCM: expand to 32-bit float and write
            C.ENCODING_PCM_24BIT -> writePcm24Bit(buffer, ptr, numFrames)
            else -> writeI16(buffer, ptr, numFrames)
        }

        if (written < 0) {
            writeErrorCalls++
            Log.e(TAG, "✗ libusb write ERROR: $written " +
                    "(encoding=$encodingName, frames=$numFrames, " +
                    "bytes=$remaining, errors=$writeErrorCalls)")
            return false
        }

        // Throttled throughput logging every THROTTLE_LOG_INTERVAL_MS
        if (nowMs - lastThrottleLogMs >= THROTTLE_LOG_INTERVAL_MS) {
            val elapsedSec = (nowMs - lastThrottleLogMs) / 1000.0
            val framesPerSec = if (elapsedSec > 0) (totalFramesSinceLastLog / elapsedSec).toLong() else 0L
            val bytesPerSec = if (elapsedSec > 0) (totalBytesSinceLastLog / elapsedSec).toLong() else 0L
            val avgPtsMs = if (handleBufferCallsSinceLastLog > 0)
                (lastPresentationTimeUs / 1000) / handleBufferCallsSinceLastLog else 0L

            Log.i(TAG, "═ THROUGHPUT [${elapsedSec.toInt()}s]: " +
                    "calls=$handleBufferCallsSinceLastLog, " +
                    "frames=$totalFramesSinceLastLog ($framesPerSec fps), " +
                    "bytes=$totalBytesSinceLastLog ($bytesPerSec B/s), " +
                    "avgPts=${avgPtsMs}ms, " +
                    "dacDrains=$dacDisconnectedCalls, " +
                    "writeErrors=$writeErrorCalls")

            // Reset accumulators
            totalFramesSinceLastLog = 0L
            totalBytesSinceLastLog = 0L
            handleBufferCallsSinceLastLog = 0
            lastThrottleLogMs = nowMs
        }

        // Advance buffer position to mark data as consumed
        buffer.position(buffer.position() + remaining)

        if (written < numFrames) {
            Log.w(TAG, "⚠ handleBuffer: short write " +
                    "($written/$numFrames frames written)")
        }
        return written >= numFrames
    }

    override fun play() {
        Log.i(TAG, "▶ play()")
        playing = true
        listener?.onPositionDiscontinuity()
    }

    override fun pause() {
        Log.i(TAG, "⏸ pause()")
        playing = false
    }

    override fun flush() {
        Log.i(TAG, "⏹ flush() — resetting accumulators")
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
        Log.i(TAG, "↺ reset() — full state reset")
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
    }

    override fun playToEndOfStream() {
        Log.i(TAG, "⏹ playToEndOfStream()")
        ended = true
    }

    override fun isEnded(): Boolean = ended

    override fun handleDiscontinuity() {
        Log.v(TAG, "handleDiscontinuity()")
    }

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        return lastPresentationTimeUs
    }

    override fun setListener(listener: Listener) {
        Log.v(TAG, "setListener(${listener::class.java.simpleName})")
        this.listener = listener
    }

    override fun setAudioSessionId(audioSessionId: Int) {
        Log.v(TAG, "setAudioSessionId($audioSessionId) — N/A for libusb")
    }

    override fun setVolume(volume: Float) {
        Log.v(TAG, "setVolume($volume) — ignored (bit-perfect)")
    }

    override fun getFormatSupport(format: Format): Int {
        return when (format.pcmEncoding) {
            C.ENCODING_PCM_16BIT,
            C.ENCODING_PCM_24BIT,
            C.ENCODING_PCM_32BIT,
            C.ENCODING_PCM_FLOAT -> FORMAT_HANDLED
            else -> FORMAT_UNSUPPORTED_TYPE
        }
    }

    override fun supportsFormat(format: Format): Boolean =
        getFormatSupport(format) == FORMAT_HANDLED

    override fun hasPendingData(): Boolean = false

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
     */
    private fun writeI16(buffer: ByteBuffer, ptr: Long, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val shorts = ShortArray(totalSamples)
        buffer.order(ByteOrder.nativeOrder()).asShortBuffer().get(shorts)
        val written = UsbDacPlugin.nativeWritePcmI16Static(ptr, shorts, numFrames)
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
        buffer.order(ByteOrder.nativeOrder()).asFloatBuffer().get(floatBuf, 0, totalSamples)
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
     * Write 24-bit PCM data to the USB DAC.
     * Expands to 32-bit float for the native driver.
     */
    private fun writePcm24Bit(buffer: ByteBuffer, ptr: Long, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val floatBuf = FloatArray(totalSamples)
        val order = ByteOrder.nativeOrder()

        for (i in 0 until totalSamples) {
            // Read 3 bytes in native order and convert to 32-bit signed int
            val b0 = buffer.get().toInt() and 0xFF
            val b1 = buffer.get().toInt() and 0xFF
            val b2 = buffer.get().toInt() and 0xFF

            val sample = if (order == ByteOrder.LITTLE_ENDIAN) {
                (b0) or (b1 shl 8) or (b2 shl 16)
            } else {
                (b2) or (b1 shl 8) or (b0 shl 16)
            }

            // Sign-extend 24-bit to 32-bit
            val extended = if (sample and 0x800000 != 0) {
                sample or 0xFF000000.toInt()
            } else {
                sample
            }

            floatBuf[i] = extended / 8388608.0f
        }

        val written = UsbDacPlugin.nativeWritePcmFloatStatic(ptr, floatBuf, numFrames)
        if (written < 0) {
            Log.e(TAG, "✗ writePcm24Bit: JNI returned $written (frames=$numFrames, samples=$totalSamples)")
        }
        return written
    }
}
