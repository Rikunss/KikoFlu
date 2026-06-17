package com.meteor.kikoeruflutter

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.AuxEffectInfo
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.AudioSink.Listener
import androidx.media3.exoplayer.audio.DefaultAudioSink
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Custom [AudioSink] that routes decoded PCM audio to an AAudio exclusive stream
 * instead of the default Android AudioTrack.
 */
@UnstableApi
class AaudioAudioSink(
    private val nativeLibraryLoader: (sampleRate: Int, channels: Int, bitsPerSample: Int, deviceId: Int) -> Long,
    private val onExclusiveStatusChanged: ((Boolean) -> Unit)? = null,
    /**
     * When true, the audio PCM data is passed through WITHOUT any digital volume gain.
     * This ensures truly bit-perfect output — no sample values are modified.
     * Must be paired with volume-locked exclusive mode to be meaningful.
     */
    private val bitPerfectMode: Boolean = false
) : AudioSink {

    companion object {
        private const val TAG = "AaudioAudioSink"

        /**
         * Ring buffer capacity: 1,048,576 bytes (~3.6s of 24-bit 48kHz stereo PCM).
         * Large enough to hold all pre-buffered audio before ExoPlayer calls play().
         */
        private const val RING_BUFFER_CAPACITY = 1_048_576

        /**
         * Maximum chunk size for ring buffer drain writes.
         * Matches the typical ExoPlayer buffer size (4800 frames).
         */
        private const val DRAIN_CHUNK_FRAMES = 4800

        /**
         * Reference to the current active AudioSink instance.
         * Set in [configure], cleared in [reset].
         * Used by [ExclusiveAudioPlugin.setAaudioDeviceId] to recreate
         * the native player with a new device ID without restarting ExoPlayer.
         */
        @Volatile
        var currentSink: AaudioAudioSink? = null
    }

    private var listener: Listener? = null
    @Volatile
    private var nativePlayerPtr: Long = 0L
    private var sampleRate: Int = 0
    private var channelCount: Int = 2
    private var pcmEncoding: Int = C.ENCODING_PCM_16BIT
    private var bytesPerFrame: Int = 4
    private var playing = false
    private var configured = false
    private var ended = false
    private var totalFramesWritten: Long = 0
    private var lastPresentationTimeUs: Long = 0
    private var playbackParameters = PlaybackParameters.DEFAULT

    private var fallbackAudioSink: DefaultAudioSink? = null

    // ── Ring buffer for pre-play() PCM data ──
    // ExoPlayer may call handleBuffer() before play(). Since the AAudio stream
    // is not yet started, writes would fill the buffer with nothing consuming it.
    // To avoid this, we queue PCM data here and drain it into the AAudio stream
    // immediately after play() calls AAudioStream_requestStart().
    private val ringBuffer = ByteArray(RING_BUFFER_CAPACITY)
    private var ringWritePos = 0
    private var ringBytes = 0
    private var playStarted = false

    private val FORMAT_HANDLED = 0
    private val FORMAT_UNSUPPORTED_TYPE = 1

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        Log.i(TAG, "[AUDIO-SINK-LIFECYCLE] configure(${inputFormat.sampleRate}Hz, ${inputFormat.channelCount}ch) — will call destroyNativePlayer")
        destroyNativePlayer()

        sampleRate = inputFormat.sampleRate
        channelCount = outputChannels?.size ?: inputFormat.channelCount
        pcmEncoding = inputFormat.pcmEncoding

        val bytesPerSample = when (pcmEncoding) {
            C.ENCODING_PCM_16BIT -> 2; C.ENCODING_PCM_24BIT -> 3
            C.ENCODING_PCM_32BIT -> 4; C.ENCODING_PCM_FLOAT -> 4
            else -> 2
        }
        bytesPerFrame = bytesPerSample * channelCount

        val bitsPerSample = when (pcmEncoding) {
            C.ENCODING_PCM_16BIT -> 16; C.ENCODING_PCM_24BIT -> 24
            C.ENCODING_PCM_32BIT -> 32; C.ENCODING_PCM_FLOAT -> 32
            else -> 16
        }

        val ptr = ExclusiveAudioPlugin.nativeCreatePlayerStatic()
        var inited = false
        if (ptr != 0L) {
            inited = ExclusiveAudioPlugin.nativeInitPlayerStatic(ptr, sampleRate, channelCount, bitsPerSample,
                ExclusiveAudioPlugin.getAaudioDeviceId())
        }

        // If exclusive mode failed, fallback to DefaultAudioSink for bit-perfect via native sample rate
        if (inited && ptr != 0L) {
            nativePlayerPtr = ptr
            configured = true
            ended = false
            totalFramesWritten = 0
            lastPresentationTimeUs = 0
            listener?.onPositionDiscontinuity()

            val isExclusive = ExclusiveAudioPlugin.nativeIsExclusiveStatic(nativePlayerPtr)
            Log.i(TAG, "Playback AAudio stream: exclusive=$isExclusive, rate=${sampleRate}Hz, bits=${bitsPerSample}")

            // Report status
            onExclusiveStatusChanged?.invoke(isExclusive)

            // Register this sink (for potential USB switch)
            currentSink = this
        } else {
            // Fallback to DefaultAudioSink - still bit-perfect if format matches hardware
            Log.w(TAG, "AAudio init failed, falling back to DefaultAudioSink for native rate")
            fallbackAudioSink?.release()
            fallbackAudioSink = DefaultAudioSink.Builder()
                .setAudioProcessors(emptyArray())
                .setEnableFloatOutput(true)
                .setEnableAudioTrackPlaybackParams(true)
                .build()
            fallbackAudioSink?.configure(inputFormat, specifiedBufferSize, outputChannels)
            fallbackAudioSink?.setVolume(currentVolume)
            nativePlayerPtr = 0L
            configured = false
            currentSink = this
        }
    }

    override fun handleBuffer(buffer: ByteBuffer, presentationTimeUs: Long, encodedAccessUnitCount: Int): Boolean {
        // If AAudio native player is active, use it
        if (nativePlayerPtr != 0L) {
            val remaining = buffer.remaining()
            val bufSize = buffer.capacity()
            Log.i(TAG, "[AUDIO-BUFFER] enter: bufSize=$bufSize, remaining=$remaining, presTimeUs=$presentationTimeUs, " +
                    "encAccessUnit=$encodedAccessUnitCount, ptr=0x${nativePlayerPtr.toString(16)}")
            if (remaining <= 0) {
                Log.i(TAG, "[AUDIO-BUFFER] remaining <= 0 — returning true (drained)")
                return true
            }
            val numFrames = remaining / bytesPerFrame
            Log.i(TAG, "[AUDIO-BUFFER] frameCalc: remaining=$remaining, bytesPerFrame=$bytesPerFrame, numFrames=$numFrames")
            if (numFrames <= 0) {
                Log.i(TAG, "[AUDIO-BUFFER] numFrames <= 0 (remaining=$remaining, bytesPerFrame=$bytesPerFrame) — returning true")
                return true
            }

            // ── Pre-play() buffering: queue data in ring buffer ──
            // If the AAudio stream hasn't been started yet (play() not called),
            // writing to it would fill the buffer with no consumer draining it.
            // Instead, copy raw PCM bytes into the ring buffer and return true
            // (data consumed). The ring buffer will be drained into the AAudio
            // stream immediately after play() calls AAudioStream_requestStart().
            //
            // If play() has been called but the ring buffer still has undrained
            // data (from a partial drain where AAudio buffer was full), re-attempt
            // draining now — the AAudio buffer may have freed space since the
            // last attempt.
            if (playStarted && ringBytes > 0) {
                drainRingBuffer()
            }

            if (!playStarted || ringBytes > 0) {
                if (ringBytes + remaining > RING_BUFFER_CAPACITY) {
                    // Ring buffer overflow — advance read position to discard oldest data
                    val discard = ringBytes + remaining - RING_BUFFER_CAPACITY
                    ringBytes -= discard
                    ringBytes = maxOf(0, ringBytes)  // defensive: prevent negative on extreme overflow
                    Log.w(TAG, "[RING-BUFFER] overflow: discarded $discard oldest bytes, " +
                            "ringBytes=$ringBytes, remaining=$remaining")
                }
                // Copy incoming PCM bytes into ring buffer, handling circular wraparound.
                // Cannot use buffer.get(ringBuffer, ringWritePos, remaining) directly because
                // ByteBuffer.get(byte[], int, int) requires offset+length <= array length.
                val firstPart = minOf(remaining, RING_BUFFER_CAPACITY - ringWritePos)
                buffer.get(ringBuffer, ringWritePos, firstPart)
                if (firstPart < remaining) {
                    // Wraparound: remaining data goes at the start of the array
                    buffer.get(ringBuffer, 0, remaining - firstPart)
                }
                ringWritePos = (ringWritePos + remaining) % RING_BUFFER_CAPACITY
                ringBytes += remaining
                lastPresentationTimeUs = presentationTimeUs
                Log.v(TAG, "[RING-BUFFER] buffered $remaining bytes (${remaining/bytesPerFrame} frames, " +
                        "total=$ringBytes bytes, writePos=$ringWritePos)")
                buffer.position(buffer.limit())  // Mark all data as consumed
                return true
            }

            lastPresentationTimeUs = presentationTimeUs
            val written = when (pcmEncoding) {
                C.ENCODING_PCM_16BIT -> writeI16(buffer, numFrames)
                C.ENCODING_PCM_FLOAT -> writeFloat(buffer, numFrames)
                C.ENCODING_PCM_32BIT -> writeFloat32Bit(buffer, numFrames)
                C.ENCODING_PCM_24BIT -> writeI16Padded24Bit(buffer, numFrames)
                else -> writeI16(buffer, numFrames)
            }
            Log.i(TAG, "[AUDIO-BUFFER] write result: frames=$numFrames, written=$written")
            if (written < 0) {
                Log.i(TAG, "[AUDIO-BUFFER] exit: written=$written (<0) — sink error, returning false (buffer NOT advanced)")
                Log.e(TAG, "write error: $written")
                return false
            }
            totalFramesWritten += written
            // Only advance buffer by actual bytes consumed.
            // If written < numFrames, only advance the consumed portion so ExoPlayer
            // retries the remaining data on the next call (bug fix: was advancing by
            // full remaining even on partial write, causing data loss).
            // Cap at remaining to prevent position exceeding buffer limit if native
            // returns a value larger than numFrames (unlikely defensive guard).
            val consumedBytes = minOf(written.toLong() * bytesPerFrame, remaining.toLong()).toInt()
            buffer.position(buffer.position() + consumedBytes)
            val handled = written >= numFrames
            Log.i(TAG, "[AUDIO-BUFFER] exit: written=$written/$numFrames frames, " +
                    "consumedBytes=$consumedBytes, handled=$handled")
            return handled
        }
        
        // Fallback to DefaultAudioSink if AAudio failed
        if (fallbackAudioSink != null) {
            Log.i(TAG, "[AUDIO-BUFFER] using fallbackAudioSink (nativePlayerPtr=0) — delegating to DefaultAudioSink")
            return fallbackAudioSink!!.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
        }
        // Both AAudio and fallback AudioSink are unavailable — drain silently and report error
        Log.e(TAG, "[AUDIO-BUFFER] No audio sink available (AAudio=0, fallback=null) — draining buffer")
        listener?.onAudioSinkError(RuntimeException("AAudio init failed, no fallback available"))
        buffer.position(buffer.limit())
        Log.i(TAG, "[AUDIO-BUFFER] drained silently — returning true")
        return true
    }

    override fun play() {
        Log.i(TAG, "[AUDIO-SINK-LIFECYCLE] play() called")
        if (nativePlayerPtr != 0L) {
            playing = true
            // Start the AAudio stream first — this ensures the audio HAL
            // begins consuming frames from the buffer.
            ExclusiveAudioPlugin.nativeStartPlayerStatic(nativePlayerPtr)
            playStarted = true

            // Drain any PCM data that was buffered before play() was called.
            // This data was queued in the ring buffer by handleBuffer() to avoid
            // writing to an unstarted AAudio stream (which would buffer-fill and
            // return 0 repeatedly).
            if (ringBytes > 0) {
                drainRingBuffer()
            }
        } else if (fallbackAudioSink != null) {
            fallbackAudioSink!!.play()
        }
        listener?.onPositionDiscontinuity()
    }

    override fun pause() {
        val sb = StringBuilder()
        sb.appendLine("[STACK] pause() called — will call nativeStopPlayerStatic")
        val trace = Thread.currentThread().stackTrace
        for (e in trace.take(25)) {
            val line = e.toString()
            if (line.contains("com.meteor.kikoeruflutter") ||
                line.contains("androidx.media3") ||
                line.contains("ExoPlayerImplInternal")) {
                sb.appendLine("[STACK]   at $line")
            }
        }
        sb.appendLine("[STACK] (total frames: ${trace.size})")
        Log.i(TAG, sb.toString().trimEnd())

        if (nativePlayerPtr != 0L) {
            playing = false
            ExclusiveAudioPlugin.nativeStopPlayerStatic(nativePlayerPtr)
        } else if (fallbackAudioSink != null) {
            fallbackAudioSink!!.pause()
        }
    }

    override fun flush() {
        Log.i(TAG, "[AUDIO-SINK-LIFECYCLE] flush() called — playing=$playing")
        playing = false; ended = false; totalFramesWritten = 0
        playStarted = false; ringBytes = 0; ringWritePos = 0
        if (nativePlayerPtr != 0L) ExclusiveAudioPlugin.nativeResetFramesWritten(nativePlayerPtr)
        if (fallbackAudioSink != null) fallbackAudioSink!!.flush()
        listener?.onPositionDiscontinuity()
    }

    override fun reset() {
        val sb = StringBuilder()
        sb.appendLine("[STACK] reset() called — will call destroyNativePlayer")
        val trace = Thread.currentThread().stackTrace
        for (e in trace.take(25)) {
            val line = e.toString()
            if (line.contains("com.meteor.kikoeruflutter") ||
                line.contains("androidx.media3") ||
                line.contains("ExoPlayerImplInternal") ||
                line.contains("MediaCodecAudioRenderer")) {
                sb.appendLine("[STACK]   at $line")
            }
        }
        Log.i(TAG, sb.toString().trimEnd())

        playing = false; configured = false; ended = false; totalFramesWritten = 0
        playStarted = false; ringBytes = 0; ringWritePos = 0
        destroyNativePlayer()
        fallbackAudioSink?.release()
        fallbackAudioSink = null
        currentSink = null
    }

    override fun playToEndOfStream() {
        Log.i(TAG, "[AUDIO-END] playToEndOfStream() ENTER: ended=$ended, playing=$playing, " +
                "nativePlayerPtr=0x${nativePlayerPtr.toString(16)}, totalFramesWritten=$totalFramesWritten, " +
                "reason=SOURCE_ENDED")
        val sb = StringBuilder()
        sb.appendLine("[STACK] playToEndOfStream() called — will call nativeStopPlayerStatic")
        val trace = Thread.currentThread().stackTrace
        for (e in trace.take(25)) {
            val line = e.toString()
            if (line.contains("com.meteor.kikoeruflutter") ||
                line.contains("androidx.media3") ||
                line.contains("ExoPlayerImplInternal") ||
                line.contains("MediaCodecAudioRenderer")) {
                sb.appendLine("[STACK]   at $line")
            }
        }
        sb.appendLine("[STACK] (total frames: ${trace.size})")
        Log.i(TAG, sb.toString().trimEnd())

        if (nativePlayerPtr != 0L) ExclusiveAudioPlugin.nativeStopPlayerStatic(nativePlayerPtr)
        if (fallbackAudioSink != null) fallbackAudioSink!!.playToEndOfStream()
        ended = true
        Log.i(TAG, "[AUDIO-END] playToEndOfStream() EXIT: ended set to $ended")
    }

    override fun isEnded(): Boolean {
        val result = ended
        Log.i(TAG, "[AUDIO-END] isEnded() called — returning $result (playing=$playing, ptr=0x${nativePlayerPtr.toString(16)})")
        return result
    }

    override fun handleDiscontinuity() {
        totalFramesWritten = 0
        if (nativePlayerPtr != 0L) ExclusiveAudioPlugin.nativeResetFramesWritten(nativePlayerPtr)
    }

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        if (nativePlayerPtr != 0L && sampleRate > 0) {
            val frames = ExclusiveAudioPlugin.nativeGetFramesWrittenStatic(nativePlayerPtr)
            val posUs = if (frames > 0) (frames * 1000000L) / sampleRate else lastPresentationTimeUs
            Log.v(TAG, "[AUDIO-POS] getCurrentPositionUs: frames=$frames, sampleRate=$sampleRate, posUs=$posUs, lastPresUs=$lastPresentationTimeUs")
            return posUs
        }
        if (fallbackAudioSink != null) return fallbackAudioSink!!.getCurrentPositionUs(sourceEnded)
        Log.v(TAG, "[AUDIO-POS] getCurrentPositionUs: no native player — returning lastPresentationTimeUs=$lastPresentationTimeUs")
        return lastPresentationTimeUs
    }

    override fun setListener(listener: Listener) { this.listener = listener }
    override fun setAudioSessionId(audioSessionId: Int) { /* N/A for AAudio */ }
    private var currentVolume: Float = 1.0f

    override fun setVolume(volume: Float) {
        currentVolume = volume.coerceIn(0.0f, 1.0f)
        if (fallbackAudioSink != null) fallbackAudioSink!!.setVolume(volume)
    }

    override fun getFormatSupport(format: Format): Int {
        return when (format.pcmEncoding) {
            C.ENCODING_PCM_16BIT, C.ENCODING_PCM_24BIT,
            C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT -> FORMAT_HANDLED
            else -> FORMAT_UNSUPPORTED_TYPE
        }
    }

    override fun supportsFormat(format: Format): Boolean = getFormatSupport(format) == FORMAT_HANDLED
    override fun hasPendingData(): Boolean = false
    override fun setPlaybackParameters(p: PlaybackParameters) { playbackParameters = p }
    override fun getPlaybackParameters(): PlaybackParameters = playbackParameters
    override fun setSkipSilenceEnabled(enabled: Boolean) { /* N/A */ }
    override fun getSkipSilenceEnabled(): Boolean = false
    override fun setAudioAttributes(audioAttributes: androidx.media3.common.AudioAttributes) { /* N/A */ }
    override fun getAudioAttributes(): androidx.media3.common.AudioAttributes? = null
    override fun setAuxEffectInfo(auxEffectInfo: AuxEffectInfo) { /* N/A */ }
    override fun enableTunnelingV21() { /* N/A */ }
    override fun disableTunneling() { /* N/A */ }

    // ── Write helpers ──

    private fun writeI16(buffer: ByteBuffer, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val shorts = ShortArray(totalSamples)
        // Use duplicate to avoid mutating the original buffer's byte order or position.
        buffer.duplicate().order(ByteOrder.nativeOrder()).asShortBuffer().get(shorts)
        // Bit-perfect mode: skip all volume gain to preserve original PCM samples
        if (!bitPerfectMode && currentVolume < 1.0f) {
            for (i in shorts.indices) {
                shorts[i] = (shorts[i] * currentVolume).toInt().coerceIn(-32768, 32767).toShort()
            }
        }
        val result = ExclusiveAudioPlugin.nativeWritePcmI16Static(nativePlayerPtr, shorts, numFrames)
        Log.v(TAG, "[AUDIO-WRITE] writeI16: frames=$numFrames samples=$totalSamples result=$result")
        return result
    }

    private fun writeFloat(buffer: ByteBuffer, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val floatBuf = FloatArray(totalSamples)
        // Use duplicate to avoid mutating the original buffer's byte order or position.
        buffer.duplicate().order(ByteOrder.nativeOrder()).asFloatBuffer().get(floatBuf, 0, totalSamples)
        // Bit-perfect mode: skip all volume gain to preserve original PCM samples
        if (!bitPerfectMode && currentVolume < 1.0f) {
            for (i in floatBuf.indices) {
                floatBuf[i] = (floatBuf[i] * currentVolume).coerceIn(-1.0f, 1.0f)
            }
        }
        val result = ExclusiveAudioPlugin.nativeWritePcmFloatStatic(nativePlayerPtr, floatBuf, numFrames)
        Log.v(TAG, "[AUDIO-WRITE] writeFloat: frames=$numFrames samples=$totalSamples result=$result")
        return result
    }

    private fun writeFloat32Bit(buffer: ByteBuffer, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val intBuffer = buffer.duplicate().order(ByteOrder.nativeOrder()).asIntBuffer()
        val ints = IntArray(totalSamples)
        intBuffer.get(ints, 0, totalSamples)
        // Bit-perfect mode: skip all volume gain to preserve original PCM samples
        if (bitPerfectMode) {
            val floatBuf = FloatArray(totalSamples)
            for (i in 0 until totalSamples) {
                floatBuf[i] = ints[i] / 2147483648.0f
            }
            val result = ExclusiveAudioPlugin.nativeWritePcmFloatStatic(nativePlayerPtr, floatBuf, numFrames)
            Log.v(TAG, "[AUDIO-WRITE] writeFloat32Bit(bitPerfect): frames=$numFrames samples=$totalSamples result=$result")
            return result
        }
        val floatBuf = FloatArray(totalSamples)
        for (i in 0 until totalSamples) {
            floatBuf[i] = (ints[i] / 2147483648.0f) * currentVolume
        }
        val result = ExclusiveAudioPlugin.nativeWritePcmFloatStatic(nativePlayerPtr, floatBuf, numFrames)
        Log.v(TAG, "[AUDIO-WRITE] writeFloat32Bit: frames=$numFrames samples=$totalSamples result=$result")
        return result
    }

    /**
     * Write 24-bit PCM data (3 bytes per sample) by padding to 32-bit float.
     * Reads 3-byte packed samples from a DUPLICATED buffer (little-endian),
     * sign-extends to 32-bit int, then converts to float for native AAudio.
     * Uses a duplicate so the original buffer's position is NOT advanced —
     * the caller [handleBuffer] handles position advancement after the write.
     */
    private fun writeI16Padded24Bit(buffer: ByteBuffer, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val floatBuf = FloatArray(totalSamples)
        val dup = buffer.duplicate()
        val logLimit = minOf(16, totalSamples)
        val rawHex = StringBuilder()
        for (i in 0 until totalSamples) {
            // Read 3 bytes from duplicate — original buffer position unchanged
            val low = dup.get().toInt() and 0xFF
            val mid = dup.get().toInt() and 0xFF
            val high = dup.get().toInt()
            val sample = (low) or (mid shl 8) or (high shl 16)
            // Sign-extend from 24-bit to 32-bit
            val signed = if (sample and 0x800000 != 0) sample or 0xFF000000.toInt() else sample
            // Bit-perfect mode: skip all volume gain to preserve original PCM samples
            floatBuf[i] = if (!bitPerfectMode && currentVolume < 1.0f) {
                (signed / 8388608.0f) * currentVolume
            } else {
                signed / 8388608.0f
            }
            if (i < logLimit) {
                rawHex.append("%06X ".format(sample and 0xFFFFFF))
            }
        }
        Log.i(TAG, "[PCM-DEBUG] 24-bit: frames=$numFrames ch=$channelCount first $logLimit raw samples (hex): $rawHex")
        val floatHex = StringBuilder()
        for (i in 0 until logLimit) {
            val bits = java.lang.Float.floatToRawIntBits(floatBuf[i])
            floatHex.append("%08X(%+.4f) ".format(bits, floatBuf[i]))
        }
        Log.i(TAG, "[PCM-DEBUG] 24-bit: first $logLimit float samples (hexIEEE754(float)): $floatHex")
        val result = ExclusiveAudioPlugin.nativeWritePcmFloatStatic(nativePlayerPtr, floatBuf, numFrames)
        Log.v(TAG, "[AUDIO-WRITE] writeI16Padded24Bit: frames=$numFrames samples=$totalSamples result=$result")
        return result
    }

    /**
     * Drain the ring buffer into the AAudio stream after play() has started it.
     * Reads buffered PCM data in chunks, wraps each chunk in a ByteBuffer, and
     * passes it through the appropriate write helper (matching the current PCM encoding).
     * Stops draining if the AAudio buffer becomes full (written < numFrames).
     */
    private fun drainRingBuffer() {
        var totalDrained = 0
        var drainCycles = 0
        while (ringBytes >= bytesPerFrame) {
            drainCycles++
            val readPos = (ringWritePos - ringBytes + RING_BUFFER_CAPACITY) % RING_BUFFER_CAPACITY
            val maxFrames = ringBytes / bytesPerFrame
            val numFrames = minOf(maxFrames, DRAIN_CHUNK_FRAMES)
            val chunkBytes = numFrames * bytesPerFrame

            // Copy from ring buffer into a temporary contiguous array
            val tmp = ByteArray(chunkBytes)
            val firstPart = minOf(chunkBytes, RING_BUFFER_CAPACITY - readPos)
            System.arraycopy(ringBuffer, readPos, tmp, 0, firstPart)
            if (firstPart < chunkBytes) {
                System.arraycopy(ringBuffer, 0, tmp, firstPart, chunkBytes - firstPart)
            }

            // Wrap in ByteBuffer for the write helper
            val bb = ByteBuffer.wrap(tmp).order(ByteOrder.nativeOrder())

            val written = when (pcmEncoding) {
                C.ENCODING_PCM_16BIT -> writeI16(bb, numFrames)
                C.ENCODING_PCM_FLOAT -> writeFloat(bb, numFrames)
                C.ENCODING_PCM_32BIT -> writeFloat32Bit(bb, numFrames)
                C.ENCODING_PCM_24BIT -> writeI16Padded24Bit(bb, numFrames)
                else -> writeI16(bb, numFrames)
            }

            if (written < 0) {
                Log.e(TAG, "[RING-BUFFER] drain write error: $written — aborting drain")
                break
            }

            val consumedBytes = minOf(written.toLong() * bytesPerFrame, chunkBytes.toLong()).toInt()
            ringBytes -= consumedBytes
            totalDrained += written
            totalFramesWritten += written

            if (written < numFrames) {
                // AAudio buffer full — stop draining, remaining data will be
                // picked up naturally by subsequent handleBuffer() calls
                Log.v(TAG, "[RING-BUFFER] drain stopped early: wrote $written/$numFrames frames, " +
                        "$ringBytes bytes remain in ring buffer")
                break
            }
        }
        Log.i(TAG, "[RING-BUFFER] drain complete: $totalDrained frames in $drainCycles cycles, " +
                "ringBytes=$ringBytes")
        // Discard partial frame tail (bytes < bytesPerFrame can never form a complete frame).
        if (ringBytes > 0 && ringBytes < bytesPerFrame) {
            Log.v(TAG, "[RING-BUFFER] discarding $ringBytes partial frame bytes (bytesPerFrame=$bytesPerFrame)")
            ringBytes = 0
        }
    }

    private fun destroyNativePlayer() {
        val sb = StringBuilder()
        sb.appendLine("[STACK] destroyNativePlayer() called — nativePlayerPtr=$nativePlayerPtr")
        val trace = Thread.currentThread().stackTrace
        for (e in trace.take(25)) {
            val line = e.toString()
            if (line.contains("com.meteor.kikoeruflutter") ||
                line.contains("androidx.media3") ||
                line.contains("ExoPlayerImplInternal") ||
                line.contains("MediaCodecAudioRenderer")) {
                sb.appendLine("[STACK]   at $line")
            }
        }
        sb.appendLine("[STACK] (total frames: ${trace.size})")
        Log.i(TAG, sb.toString().trimEnd())

        if (nativePlayerPtr != 0L) {
            ExclusiveAudioPlugin.nativeStopPlayerStatic(nativePlayerPtr)
            ExclusiveAudioPlugin.nativeDestroyPlayerStatic(nativePlayerPtr)
            nativePlayerPtr = 0L
        }
    }

    /**
     * Recreate the native player to target a new USB DAC device ID.
     * Called by [ExclusiveAudioPlugin.setAaudioDeviceId] when the USB DAC
     * device changes. Destroys the old native player and creates a new one
     * with the updated device ID, preserving the current playback state.
     *
     * This allows the AudioSink to switch USB DACs WITHOUT restarting ExoPlayer.
     */
    fun recreateWithDeviceId(deviceId: Int) {
        val wasPlaying = playing
        val prevFrames = totalFramesWritten
        destroyNativePlayer()
        val newPtr = nativeLibraryLoader(sampleRate, channelCount,
            when (pcmEncoding) {
                C.ENCODING_PCM_16BIT -> 16; C.ENCODING_PCM_24BIT -> 24
                C.ENCODING_PCM_32BIT -> 32; C.ENCODING_PCM_FLOAT -> 32
                else -> 16
            }, deviceId)
        if (newPtr != 0L) {
            nativePlayerPtr = newPtr
            totalFramesWritten = prevFrames
            if (wasPlaying) {
                ExclusiveAudioPlugin.nativeStartPlayerStatic(newPtr)
            }
            Log.i(TAG, "recreated native player for device #$deviceId (playing=$wasPlaying)")
        } else {
            Log.e(TAG, "failed to recreate native player for device #$deviceId")
        }
    }
}
