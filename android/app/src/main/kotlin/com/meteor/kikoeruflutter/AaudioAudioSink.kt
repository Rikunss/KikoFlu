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

    private val FORMAT_HANDLED = 0
    private val FORMAT_UNSUPPORTED_TYPE = 1

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        Log.i(TAG, "configure(${inputFormat.sampleRate}Hz, ${inputFormat.channelCount}ch)")
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
            if (remaining <= 0) return true
            val numFrames = remaining / bytesPerFrame
            if (numFrames <= 0) return true

            lastPresentationTimeUs = presentationTimeUs
            val written = when (pcmEncoding) {
                C.ENCODING_PCM_16BIT -> writeI16(buffer, numFrames)
                C.ENCODING_PCM_FLOAT -> writeFloat(buffer, numFrames)
                C.ENCODING_PCM_32BIT -> writeFloat32Bit(buffer, numFrames)
                else -> writeI16(buffer, numFrames)
            }
            if (written < 0) { Log.e(TAG, "write error: $written"); return false }
            totalFramesWritten += written
            buffer.position(buffer.position() + remaining)
            return written >= numFrames
        }
        
        // Fallback to DefaultAudioSink if AAudio failed
        if (fallbackAudioSink != null) {
            return fallbackAudioSink!!.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
        }
        // Both AAudio and fallback AudioSink are unavailable — drain silently and report error
        Log.e(TAG, "No audio sink available (AAudio=0, fallback=null) — audio will be silent")
        listener?.onAudioSinkError(RuntimeException("AAudio init failed, no fallback available"))
        buffer.position(buffer.limit())
        return true
    }

    override fun play() {
        if (nativePlayerPtr != 0L) {
            playing = true
            ExclusiveAudioPlugin.nativeStartPlayerStatic(nativePlayerPtr)
        } else if (fallbackAudioSink != null) {
            fallbackAudioSink!!.play()
        }
        listener?.onPositionDiscontinuity()
    }

    override fun pause() {
        if (nativePlayerPtr != 0L) {
            playing = false
            ExclusiveAudioPlugin.nativeStopPlayerStatic(nativePlayerPtr)
        } else if (fallbackAudioSink != null) {
            fallbackAudioSink!!.pause()
        }
    }

    override fun flush() {
        playing = false; ended = false; totalFramesWritten = 0
        if (nativePlayerPtr != 0L) ExclusiveAudioPlugin.nativeResetFramesWritten(nativePlayerPtr)
        if (fallbackAudioSink != null) fallbackAudioSink!!.flush()
        listener?.onPositionDiscontinuity()
    }

    override fun reset() {
        playing = false; configured = false; ended = false; totalFramesWritten = 0
        destroyNativePlayer()
        fallbackAudioSink?.release()
        fallbackAudioSink = null
        currentSink = null
    }

    override fun playToEndOfStream() {
        if (nativePlayerPtr != 0L) ExclusiveAudioPlugin.nativeStopPlayerStatic(nativePlayerPtr)
        if (fallbackAudioSink != null) fallbackAudioSink!!.playToEndOfStream()
        ended = true
    }

    override fun isEnded(): Boolean = ended

    override fun handleDiscontinuity() {
        totalFramesWritten = 0
        if (nativePlayerPtr != 0L) ExclusiveAudioPlugin.nativeResetFramesWritten(nativePlayerPtr)
    }

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        if (nativePlayerPtr != 0L && sampleRate > 0) {
            val frames = ExclusiveAudioPlugin.nativeGetFramesWrittenStatic(nativePlayerPtr)
            if (frames > 0) return (frames * 1000000L) / sampleRate
        }
        if (fallbackAudioSink != null) return fallbackAudioSink!!.getCurrentPositionUs(sourceEnded)
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
        buffer.order(ByteOrder.nativeOrder()).asShortBuffer().get(shorts)
        // Bit-perfect mode: skip all volume gain to preserve original PCM samples
        if (!bitPerfectMode && currentVolume < 1.0f) {
            for (i in shorts.indices) {
                shorts[i] = (shorts[i] * currentVolume).toInt().coerceIn(-32768, 32767).toShort()
            }
        }
        return ExclusiveAudioPlugin.nativeWritePcmI16Static(nativePlayerPtr, shorts, numFrames)
    }

    private fun writeFloat(buffer: ByteBuffer, numFrames: Int): Int {
        val totalSamples = numFrames * channelCount
        val floatBuf = FloatArray(totalSamples)
        buffer.order(ByteOrder.nativeOrder()).asFloatBuffer().get(floatBuf, 0, totalSamples)
        // Bit-perfect mode: skip all volume gain to preserve original PCM samples
        if (!bitPerfectMode && currentVolume < 1.0f) {
            for (i in floatBuf.indices) {
                floatBuf[i] = (floatBuf[i] * currentVolume).coerceIn(-1.0f, 1.0f)
            }
        }
        return ExclusiveAudioPlugin.nativeWritePcmFloatStatic(nativePlayerPtr, floatBuf, numFrames)
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
            return ExclusiveAudioPlugin.nativeWritePcmFloatStatic(nativePlayerPtr, floatBuf, numFrames)
        }
        val floatBuf = FloatArray(totalSamples)
        for (i in 0 until totalSamples) {
            floatBuf[i] = (ints[i] / 2147483648.0f) * currentVolume
        }
        return ExclusiveAudioPlugin.nativeWritePcmFloatStatic(nativePlayerPtr, floatBuf, numFrames)
    }

    private fun destroyNativePlayer() {
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
