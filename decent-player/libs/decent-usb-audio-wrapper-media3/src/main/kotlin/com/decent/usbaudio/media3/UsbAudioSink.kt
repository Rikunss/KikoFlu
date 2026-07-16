package com.decent.usbaudio.media3

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import com.decent.usbaudio.NativeAudioEngine
import com.decent.usbaudio.UsbAudioDevice
import com.decent.usbaudio.UsbAudioStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * ExoPlayer [androidx.media3.exoplayer.audio.AudioSink] that sends PCM directly
 * to a USB Audio Class 2.0 DAC via isochronous transfers, bypassing the entire
 * Android audio stack (AudioFlinger, AudioTrack, AAudio).
 *
 * The delegate [DefaultAudioSink] is kept alive (muted) for ExoPlayer's clock
 * and position tracking. Audio data is routed to the USB DAC via a dedicated
 * streaming thread with a producer-consumer queue, decoupling USB timing from
 * the delegate's AudioTrack timing.
 *
 * @param delegate  The [DefaultAudioSink] owned by the ExoPlayer renderer.
 * @param context   Application context for USB device detection and audio routing.
 * @param config    Configuration options (default: bit-perfect enabled, route to speaker).
 */
@OptIn(UnstableApi::class)
class UsbAudioSink(
    private val delegate: DefaultAudioSink,
    private val context: Context,
    private val config: UsbAudioSinkConfig = UsbAudioSinkConfig()
) : ForwardingAudioSink(delegate) {

    /** Source file bit depth (16, 24, 32). Auto-detected from NativeAudioEngine. */
    private var trackBitDepth: Int = 0

    /** True when the native engine is running. Read by [NativeEngineAwareLoadControl]
     *  to stop ExoPlayer from loading data (prevents SD card I/O contention).
     *  Temporarily set to false during seek to allow one post-seek load. */
    @Volatile
    var isNativeEngineActive: Boolean = false
        private set


    /** File path of the current track. Set internally by [PlayerIntegrationListener]
     *  from the MediaItem URI. When non-null and pointing to a FLAC file, the native
     *  audio engine is used. For HTTP URIs, this is null (ExoPlayer pipeline fallback). */
    private var currentTrackPath: String? = null

    /** Clean up a finished native engine and apply deferred USB config.
     *  @return true if an engine was cleaned up (caller should restart playback). */
    private fun cleanupFinishedEngine(): Boolean {
        val engine = nativeEngine
        if (engine != null && !engine.isRunning) {
            engine.destroy()
            nativeEngine = null
            isNativeEngineActive = false
            activeEnginePath = null
            windowOffsetUs = -1L
            usbStartMediaTimeNeedsInit = true
            Log.i(TAG, "cleanupFinishedEngine: old engine cleared")

            if (hasDeferredConfig) {
                Log.i(TAG, "cleanupFinishedEngine: applying deferred config rate=$deferredRate")
                configureUsbBitPerfect(deferredRate, deferredChannels, deferredEncoding)
                hasDeferredConfig = false
            }
            return true
        }
        return false
    }

    /** Creates a native engine if the USB stream is ready and no engine exists.
     *  Replaces the streaming thread fallback if one was set up due to rate mismatch. */
    private fun createEngineIfNeeded() {
        if (nativeEngine?.isRunning == true) return  // already running
        val stream = usbAudioStream
        if (stream != null && stream.isAlive) {
            val old = nativeEngine
            if (old != null && !old.isRunning) {
                old.destroy()
                nativeEngine = null
                activeEnginePath = null
            }
            if (nativeEngine == null) {
                windowOffsetUs = -1L
                usbStartMediaTimeNeedsInit = true
                startNativeEngineIfFlac(stream)
                if (nativeEngine != null) {
                    isNativeEngineActive = false
                }
                Log.i(TAG, "createEngineIfNeeded: engine=${nativeEngine != null}")
            }
        }
    }

    private var usbAudioStream: UsbAudioStream? = null
    private val usbAudioDevice = UsbAudioDevice.getInstance(context)
    private var usbStreamingThread: UsbStreamingThread? = null
    private var nativeEngine: NativeAudioEngine? = null
    private val engineLock = Any()

    private var currentEncoding: Int = C.ENCODING_PCM_16BIT
    private var currentSampleRate: Int = 0
    private var currentChannelCount: Int = 0
    private var pendingVolume: Float = 1f
    private var delegateMuted: Boolean = false
    private var handleBufferCallCount: Long = 0

    /**
     * Media timeline offset captured from the first buffer's presentationTimeUs
     * after each flush/init. Maps framesWritten=0 to the correct song position.
     * DefaultAudioSink calls this startMediaTimeUs internally.
     */
    private var usbStartMediaTimeUs: Long = 0L
    private var usbStartMediaTimeNeedsInit: Boolean = true
    private var handledEndOfStream: Boolean = false

    /** ExoPlayer's window offset, captured once per track. Never reset by flush.
     *  Used to convert between ExoPlayer timeline and FLAC absolute position. */
    private var windowOffsetUs: Long = -1L

    /** True when the engine was just created and needs its first seek from handleBuffer.
     *  Prevents play() from resuming the engine before the correct position is known. */
    private var engineNeedsInitialSeek: Boolean = false

    /** Path of the file the current native engine is decoding. Used to detect track changes. */
    private var activeEnginePath: String? = null


    /** Track whether we've already attempted a reconnect for the current
     *  stale-stream episode. Reset when a new stream is successfully created. */
    private var reconnectAttempted: Boolean = false

    /** Set to true when the USB device is confirmed gone (no device found on reconnect).
     *  Prevents handleBuffer() from repeatedly calling configureUsbBitPerfect() after
     *  the DAC is unplugged, which would log spam and waste CPU. Reset when a new stream
     *  is successfully created in configureUsbBitPerfect() or reconnectUsbStreamIfNeeded(). */
    /** @return true when the USB device is confirmed gone (no device found on reconnect).
     *  Used by [ExoPlayerManager] to decide whether to pause ExoPlayer on
     *  ACTION_AUDIO_BECOMING_NOISY — when the device is lost but useDecentSink
     *  hasn't been cleared yet, the broadcast should NOT be ignored. */
    @Volatile var isDeviceLost: Boolean = false
        private set

    /** Timestamp (SystemClock.elapsedRealtime) of the last reconnect attempt.
     *  Used together with [RECONNECT_COOLDOWN_MS] to rate-limit lazy USB stream
     *  initialization in handleBuffer(), preventing log spam and excessive USB
     *  device-list scanning when the DAC is temporarily disconnected. */
    private var lastReconnectAttemptMs: Long = 0L

    /** Minimum interval between reconnect attempts in handleBuffer() lazy init.
     *  2000 ms = at most one USB device scan every 2 seconds while waiting for
     *  device to reappear or permission to be granted. */
    private val RECONNECT_COOLDOWN_MS = 2000L

    /** Max queue entries before returning false for backpressure (paces ExoPlayer).
     *  Pause responsiveness is handled by pauseStreaming(), not queue size. */
    private val QUEUE_BACKPRESSURE_THRESHOLD = 16

    /** Tracks ExoPlayer's play/pause state so seek-while-paused doesn't auto-resume. */
    private var isPlaying = false

    /** Safety timeout Runnable that force-resumes the native engine if no
     *  handleBuffer() arrives within 500ms of play(). Prevents startup silence
     *  when LoadControl blocks before the first ExoPlayer buffer arrives. */
    @Volatile private var startupSafetyTimeout: Runnable? = null

    /** Deferred USB reconfiguration — applied after engine finishes playing. */
    private var deferredRate: Int = 0
    private var deferredChannels: Int = 0
    private var deferredEncoding: Int = 0
    private var hasDeferredConfig: Boolean = false


    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        val enc = inputFormat.pcmEncoding
        if (enc != Format.NO_VALUE) currentEncoding = enc

        val fmtSr = inputFormat.sampleRate.takeIf { it > 0 }
        val fmtCh = inputFormat.channelCount.takeIf { it > 0 }
        if (fmtSr != null) currentSampleRate = fmtSr
        if (fmtCh != null) currentChannelCount = fmtCh

        if (nativeEngine?.isRunning == true) {
            val trackChanged = currentTrackPath != activeEnginePath
            if (!trackChanged) {
                if (inputFormat.sampleRate != currentSampleRate || inputFormat.channelCount != currentChannelCount) {
                    deferredRate = inputFormat.sampleRate
                    deferredChannels = inputFormat.channelCount
                    deferredEncoding = enc
                    hasDeferredConfig = true
                    Log.i(TAG, "configure: engine running, pre-buffer — deferred rate=${inputFormat.sampleRate}")
                } else {
                    Log.i(TAG, "configure: engine running, same rate — keeping alive")
                }
                super.configure(inputFormat, specifiedBufferSize, outputChannels)
                muteDelegateIfNeeded()
                return
            }
            Log.i(TAG, "configure: track changed, destroying engine")
        }
        val oldEngine = nativeEngine
        if (oldEngine != null) {
            oldEngine.stop()
            oldEngine.destroy()
            nativeEngine = null
            isNativeEngineActive = false
            activeEnginePath = null
            Log.i(TAG, "configure: destroyed old engine")
        }

        handleBufferCallCount = 0

        Log.i(TAG, "configure: pcmEncoding=${when(enc) {
            C.ENCODING_PCM_FLOAT -> "FLOAT"; C.ENCODING_PCM_16BIT -> "16BIT"
            C.ENCODING_PCM_24BIT -> "24BIT"; C.ENCODING_PCM_32BIT -> "32BIT"
            else -> "UNKNOWN($enc)"
        }} rate=${inputFormat.sampleRate} ch=${inputFormat.channelCount} fmtSr=$fmtSr fmtCh=$fmtCh")

        if (config.bitPerfectEnabled && fmtSr != null && fmtCh != null) {
            val device = usbAudioDevice.findUsbAudioDevice()
            if (device != null && usbAudioDevice.hasPermission(device)) {
                configureUsbBitPerfect(fmtSr, fmtCh, enc)
                windowOffsetUs = -1L
                usbStartMediaTimeNeedsInit = true
                if (config.forceRouteToSpeaker) forceMediaToSpeaker()

                val delegateFormat = if (inputFormat.sampleRate > 48000) {
                    inputFormat.buildUpon().setSampleRate(48000).build()
                } else {
                    inputFormat
                }
                super.configure(delegateFormat, specifiedBufferSize, outputChannels)
                muteDelegateIfNeeded()
                if (inputFormat.sampleRate > 48000) {
                    Log.i(TAG, "Delegate forced to 48kHz (source was ${inputFormat.sampleRate}Hz)")
                }
                Log.i(TAG, "Delegate configured (muted, routed to speaker)")
                return
            } else if (device != null) {
                Log.w(TAG, "USB DAC found but no permission")
            } else {
                Log.w(TAG, "configure: no USB device found — will retry in handleBuffer")
            }
        } else {
            Log.i(TAG, "configure: format not ready (fmtSr=$fmtSr fmtCh=$fmtCh) — fallback to delegate")
        }

        super.configure(inputFormat, specifiedBufferSize, outputChannels)

        if (usbAudioStream != null && !config.bitPerfectEnabled) {
            releaseUsbStream()
        }
    }

    override fun handleBuffer(
        buffer: ByteBuffer,
        presentationTimeUs: Long,
        encodedAccessUnitCount: Int
    ): Boolean {
        if (config.bitPerfectEnabled && usbAudioStream?.isAlive != true) {
            if (!reconnectAttempted) {
                isDeviceLost = true
                Log.i(TAG, "handleBuffer: stream dead — proactively set isDeviceLost=true")
            }
            val ok = reconnectUsbStreamIfNeeded()
            if (!ok) {
                if (currentSampleRate <= 0 || currentChannelCount <= 0) {
                    val tracks = attachedPlayer?.currentTracks
                    if (tracks != null) {
                        for (group in tracks.groups) {
                            if (group.type == C.TRACK_TYPE_AUDIO && group.length > 0) {
                                val fmt = group.getTrackFormat(0)
                                if (fmt.sampleRate > 0) currentSampleRate = fmt.sampleRate
                                if (fmt.channelCount > 0) currentChannelCount = fmt.channelCount
                                if (fmt.pcmEncoding != Format.NO_VALUE) currentEncoding = fmt.pcmEncoding
                                Log.i(TAG, "handleBuffer: format from tracks rate=$currentSampleRate ch=$currentChannelCount enc=$currentEncoding")
                                break
                            }
                        }
                    }
                }
                if (currentSampleRate > 0 && currentChannelCount > 0) {
                    if (usbAudioStream?.isAlive != true && !isDeviceLost) {
                        if (lastReconnectAttemptMs > 0 &&
                            SystemClock.elapsedRealtime() - lastReconnectAttemptMs < RECONNECT_COOLDOWN_MS) {
                        } else {
                            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
                            Log.i(TAG, "handleBuffer: lazy USB stream init for ${currentSampleRate}Hz/${currentChannelCount}ch")
                            configureUsbBitPerfect(currentSampleRate, currentChannelCount, currentEncoding)
                            if (usbAudioStream?.isAlive == true) {
                                forceMediaToSpeaker()
                                muteDelegateIfNeeded()
                            }
                        }
                    }
                }
            }
        }

        val stream = usbAudioStream
        if (config.bitPerfectEnabled && stream?.isAlive == true) {
            muteDelegateIfNeeded()

            if (nativeEngine == null && usbStreamingThread == null) {
                startNativeEngineIfFlac(stream)
            }

            if (usbStartMediaTimeNeedsInit) {
                usbStartMediaTimeUs = maxOf(0L, presentationTimeUs)
                usbStartMediaTimeNeedsInit = false
                startupSafetyTimeout?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
                startupSafetyTimeout = null
                if (windowOffsetUs < 0) {
                    windowOffsetUs = presentationTimeUs - initialPlayerPositionUs
                }
                Log.i(TAG, "startMediaTimeUs=$usbStartMediaTimeUs windowOffset=$windowOffsetUs initialPos=${initialPlayerPositionUs / 1000}ms")

                val engine = nativeEngine
                if (engine != null && windowOffsetUs >= 0) {
                    val flacPositionUs = presentationTimeUs - windowOffsetUs
                    if (flacPositionUs >= 0) {
                        engine.seek(flacPositionUs)
                        if (isPlaying) engine.resume()
                        engineNeedsInitialSeek = false
                        Log.i(TAG, "Native engine seek to ${flacPositionUs / 1_000_000}s (playing=$isPlaying)")
                    }
                }
                if (nativeEngine?.isRunning == true) {
                    isNativeEngineActive = true
                }
            }

            val engine = nativeEngine
            if (engine != null) {
                if (engine.isRunning) {
                    buffer.position(buffer.limit())
                    return true
                }
                Log.i(TAG, "Native engine finished — cleaning up for next track")
                engine.destroy()
                nativeEngine = null
                isNativeEngineActive = false
                activeEnginePath = null
                windowOffsetUs = -1L
                usbStartMediaTimeNeedsInit = true
                buffer.position(buffer.limit())
                return true
            }

            val thread = usbStreamingThread ?: return true

            if (thread.queueSize() >= QUEUE_BACKPRESSURE_THRESHOLD) {
                return false
            }

            handleBufferCallCount++
            val snapshot: ByteBuffer = buffer.slice().order(buffer.order())

            if (currentEncoding == C.ENCODING_PCM_FLOAT) {
                val totalSamples = snapshot.remaining() / 4
                if (totalSamples > 0) {
                    val floatBuf = FloatArray(totalSamples)
                    snapshot.asFloatBuffer().get(floatBuf)
                    if (handleBufferCallCount <= 3) {
                        Log.i(TAG, "handleBuffer #$handleBufferCallCount: FLOAT samples=$totalSamples")
                    }
                    thread.enqueue(floatBuf)
                }
            } else {
                val remaining = snapshot.remaining()
                if (remaining > 0) {
                    val rawBytes = ByteArray(remaining)
                    snapshot.get(rawBytes)
                    if (handleBufferCallCount <= 3) {
                        val bps = PcmUtils.bytesPerSample(currentEncoding)
                        Log.i(TAG, "handleBuffer #$handleBufferCallCount: RAW ${bps*8}bit bytes=$remaining")
                    }
                    thread.enqueueRaw(rawBytes, currentEncoding)
                }
            }

            buffer.position(buffer.limit())
            return true
        }

        if (config.bitPerfectEnabled && isDeviceLost) {
            if (!delegateMuted) {
                delegateMuted = true
                super.setVolume(0f)
                Handler(Looper.getMainLooper()).post {
                    if (attachedPlayer?.isPlaying == true) {
                        Log.w(TAG, "Device lost — force-pausing ExoPlayer")
                        attachedPlayer?.pause()
                    }
                }
            }
            buffer.position(buffer.limit())
            return true
        }

        unmuteDelegateIfNeeded()
        return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
    }


    private var posLogCount = 0L

    private var engineEndNotified = false

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        if (config.bitPerfectEnabled) {
            val streamAlive = usbAudioStream?.isAlive == true
            val engine = nativeEngine
            val engineCreated = engine?.isCreated == true

            if (++posLogCount % 500 == 1L) {
                Log.i(TAG, "getPositionUs: streamAlive=$streamAlive engine=$engineCreated " +
                        "running=${engine?.isRunning} window=$windowOffsetUs enginePos=${engine?.getPositionUs()}")
            }

            if (engine != null && !engine.isRunning && !engineEndNotified) {
                engineEndNotified = true
                Log.i(TAG, "Engine finished — advancing to next track")
                val p = attachedPlayer
                if (p != null) {
                    Handler(Looper.getMainLooper()).post {
                        if (p.hasNextMediaItem()) {
                            p.seekToNextMediaItem()
                        } else {
                            p.pause()
                        }
                    }
                }
            }

            if (streamAlive && engineCreated && windowOffsetUs >= 0) {
                return windowOffsetUs + engine!!.getPositionUs()
            }

            if (streamAlive) {
                if (usbStartMediaTimeNeedsInit) return AudioSink.CURRENT_POSITION_NOT_SET
                val frames = usbAudioStream?.framesWritten ?: 0L
                return if (currentSampleRate > 0) {
                    usbStartMediaTimeUs + frames * C.MICROS_PER_SECOND / currentSampleRate
                } else AudioSink.CURRENT_POSITION_NOT_SET
            }
        }
        return super.getCurrentPositionUs(sourceEnded)
    }

    override fun isEnded(): Boolean {
        if (config.bitPerfectEnabled) {
            val engine = nativeEngine
            if (engine != null && engine.isRunning) return false
            if (engine != null && !engine.isRunning) return true
        }
        return super.isEnded()
    }

    override fun hasPendingData(): Boolean {
        if (config.bitPerfectEnabled) {
            if (nativeEngine?.isRunning == true) return true
            if (usbStreamingThread?.hasPendingData() == true) return true
        }
        return super.hasPendingData()
    }

    override fun playToEndOfStream() {
        handledEndOfStream = true
        super.playToEndOfStream()
    }

    override fun play() {
        super.play()
        isPlaying = true

        reconnectAttempted = false
        reconnectUsbStreamIfNeeded()

        val resumed = if (!engineNeedsInitialSeek) { nativeEngine?.resume(); true } else false
        usbStreamingThread?.resumeStreaming()
        Log.i(TAG, "play() needsSeek=$engineNeedsInitialSeek resumed=$resumed")

        if (engineNeedsInitialSeek && nativeEngine?.isRunning == true) {
            startupSafetyTimeout?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
            val safetyRunnable = Runnable {
                if (isPlaying && engineNeedsInitialSeek && nativeEngine?.isRunning == true) {
                    engineNeedsInitialSeek = false
                    nativeEngine?.resume()
                    isNativeEngineActive = true
                    Log.w(TAG, "play(): SAFETY TIMEOUT — resumed engine without seek (500ms elapsed)")
                }
            }
            startupSafetyTimeout = safetyRunnable
            Handler(Looper.getMainLooper()).postDelayed(safetyRunnable, 500)
        }
    }

    override fun pause() {
        isPlaying = false
        startupSafetyTimeout?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
        startupSafetyTimeout = null
        if (!engineNeedsInitialSeek) nativeEngine?.pause()
        usbStreamingThread?.pauseStreaming()
        super.pause()
    }

    override fun setVolume(volume: Float) {
        pendingVolume = volume
        if (config.bitPerfectEnabled && usbAudioStream?.isAlive == true) {
            muteDelegateIfNeeded()
        } else {
            unmuteDelegateIfNeeded()
        }
    }

    override fun flush() {
        super.flush()
        usbStreamingThread?.flush()
        usbAudioStream?.flush()
        usbStartMediaTimeNeedsInit = true
        handledEndOfStream = false
        if (nativeEngine?.isRunning == true) {
            isNativeEngineActive = false
        }
    }

    override fun reset() {
        super.reset()
        startupSafetyTimeout?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
        startupSafetyTimeout = null
    }

    override fun release() {
        releaseUsbStream()
        super.release()
    }


    private fun configureUsbBitPerfect(sampleRate: Int, channelCount: Int, encoding: Int) {

        if (sampleRate == currentSampleRate && channelCount == currentChannelCount
            && encoding == currentEncoding && usbAudioStream?.isAlive == true) {
            Log.d(TAG, "USB stream cached for rate=$sampleRate ch=$channelCount — reusing")
            return
        }

        if (usbAudioStream != null) releaseUsbStream()

        val usbDevice = usbAudioDevice.findUsbAudioDevice()
        if (usbDevice == null) {
            Log.e(TAG, "configureUsbBitPerfect: no USB device found — marking as lost")
            isDeviceLost = true
            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
            return
        }
        var deviceInfo = usbAudioDevice.openDevice(usbDevice)
        if (deviceInfo == null) {
            Log.e(TAG, "Failed to open USB device — marking as lost")
            isDeviceLost = true
            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
            return
        }

        val bitDepth = deviceInfo.bestBitDepth
        val altSetting = deviceInfo.bestAltSetting
        val sourceBitDepth = trackBitDepth.takeIf { it > 0 }
            ?: PcmUtils.bytesPerSample(currentEncoding) * 8
        Log.i(TAG, "Bit-perfect: source=${sourceBitDepth}bit → alt=$altSetting usb=${bitDepth}bit " +
                "clockSource=0x${deviceInfo.clockSourceId.toString(16)}")

        var stream = UsbAudioStream(
            fd = deviceInfo.fd,
            interfaceId = deviceInfo.interfaceId,
            endpointOut = deviceInfo.endpointOutAddress,
            endpointFeedback = deviceInfo.endpointFeedbackAddress,
            sampleRate = sampleRate,
            channelCount = channelCount,
            bitDepth = bitDepth,
            maxPacketSize = deviceInfo.maxPacketSize
        )

        if (!stream.isReady) {
            Log.e(TAG, "USB stream creation failed — marking as lost")
            stream.release()
            isDeviceLost = true
            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
            return
        }


        if (!usbAudioDevice.setAltSetting(0)) {
            Log.w(TAG, "setAlt(0) failed — stale fd, reopening device...")
            usbAudioDevice.closeDevice()
            stream.release()
            deviceInfo = usbAudioDevice.openDevice(usbDevice)
            if (deviceInfo == null) {
                Log.e(TAG, "Failed to reopen USB device — marking as lost")
                isDeviceLost = true
                lastReconnectAttemptMs = SystemClock.elapsedRealtime()
                return
            }
            stream = UsbAudioStream(
                fd = deviceInfo.fd,
                interfaceId = deviceInfo.interfaceId,
                endpointOut = deviceInfo.endpointOutAddress,
                endpointFeedback = deviceInfo.endpointFeedbackAddress,
                sampleRate = sampleRate,
                channelCount = channelCount,
                bitDepth = bitDepth,
                maxPacketSize = deviceInfo.maxPacketSize
            )
            if (!stream.isReady) {
                Log.e(TAG, "USB stream recreation failed after reopen")
                stream.release()
                return
            }
            Log.i(TAG, "Device reopened with fresh fd=${deviceInfo.fd}")
        }
        Log.i(TAG, "Step 1: setAlt(0) — old ISO ring freed")

        usbAudioDevice.setSampleRate(sampleRate)

        val clockValid = usbAudioDevice.readClockValid()
        Log.i(TAG, "Step 2-3: SET_CUR=$sampleRate, CLOCK_VALID=$clockValid")

        usbAudioDevice.setAltSetting(0)
        Log.i(TAG, "Step 4: setAlt(0) again — defensive reset")

        val altResult = usbAudioDevice.setAltSetting(altSetting)
        Log.i(TAG, "Step 5: setAlt($altSetting): $altResult — new ISO ring allocated")

        Thread.sleep(50)

        if (!stream.start()) {
            Log.e(TAG, "USB stream start failed — marking as lost")
            stream.release()
            isDeviceLost = true
            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
            return
        }

        usbAudioStream = stream
        reconnectAttempted = false  // fresh stream — reset for next detach cycle            isDeviceLost = false  // device is back online
        lastReconnectAttemptMs = 0L  // reset cooldown counter
        currentSampleRate = sampleRate
        currentChannelCount = channelCount
        muteDelegateIfNeeded()

        startNativeEngineIfFlac(stream)

        Log.i(TAG, "USB bit-perfect stream ACTIVE: rate=$sampleRate ch=$channelCount " +
                "bits=$bitDepth device=${deviceInfo.deviceName}")
    }

    /**
     * Detect USB DAC hot-plug reconnect and rebuild the native stream.
     *
     * After a USB DAC is detached while playing, the native stream handle
     * becomes invalid (fd closed by kernel). When the same DAC is plugged
     * back in, the stale [usbAudioStream] reference still points to the
     * destroyed native context, and subsequent writes fail with errno=25.
     *
     * This method:
     * 1. Checks if the stream is dead but a USB device is available
     * 2. Rebuilds the full pipeline: openDevice → UsbAudioStream → setAlt →
     *    SET_CUR → start (same sequence as first-connect in [configureUsbBitPerfect])
     * 3. Resets reconnect-attempt flag on success so future detach/reconnect
     *    cycles can retry
     *
     * Called from [play()] and [handleBuffer()] — both are re-invoked after
     * user presses play following a reconnect, so the rebuild happens before
     * any write attempt.
     *
     * @return true if the stream was successfully rebuilt, false otherwise.
     */
    private fun reconnectUsbStreamIfNeeded(): Boolean {
        if (!config.bitPerfectEnabled || currentSampleRate <= 0 || currentChannelCount <= 0) {
            return false
        }

        if (usbAudioStream?.isAlive == true) {
            reconnectAttempted = false
            isDeviceLost = false
            lastReconnectAttemptMs = 0L  // reset cooldown counter
            return false
        }

        if (reconnectAttempted) {
            if (isDeviceLost && lastReconnectAttemptMs > 0 &&
                SystemClock.elapsedRealtime() - lastReconnectAttemptMs > 10_000L) {
                Log.i(TAG, "reconnectUsbStreamIfNeeded: 10s elapsed since last attempt — retrying")
                reconnectAttempted = false
                isDeviceLost = false
            } else {
                return false
            }
        }
        reconnectAttempted = true

        Log.i(TAG, "reconnectUsbStreamIfNeeded: stream dead — checking for USB device")
        val device = usbAudioDevice.findUsbAudioDevice()
        if (device == null) {
            Log.w(TAG, "reconnectUsbStreamIfNeeded: no USB device found, marking as lost")
            reconnectAttempted = true  // prevent repeated scanning on every buffer
            isDeviceLost = true
            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
            return false
        }
        if (!usbAudioDevice.hasPermission(device)) {
            Log.w(TAG, "reconnectUsbStreamIfNeeded: USB device found but no permission")
            return false
        }

        Log.i(TAG, "reconnectUsbStreamIfNeeded: REBUILDING native USB stream for ${device.productName}")

        if (usbAudioStream != null) {
            releaseUsbStream()
        }

        configureUsbBitPerfect(currentSampleRate, currentChannelCount, currentEncoding)

        val rebuilt = usbAudioStream?.isAlive == true
        if (rebuilt) {
            Log.i(TAG, "reconnectUsbStreamIfNeeded: ✓ stream rebuilt successfully")
            reconnectAttempted = false
            isDeviceLost = false
            lastReconnectAttemptMs = 0L  // reset cooldown counter
        } else {
            Log.w(TAG, "reconnectUsbStreamIfNeeded: ✗ stream rebuild failed — marking as lost")
            isDeviceLost = true
            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
        }
        return rebuilt
    }

    /** Try to start a native FLAC engine. Falls back to ExoPlayer streaming thread. */
    @Synchronized
    private fun startNativeEngineIfFlac(stream: UsbAudioStream) {
        if (nativeEngine != null) return  // already created (synchronized method)

        usbStreamingThread?.stop()
        usbStreamingThread = null

        val path = currentTrackPath
        if (path != null && path.lowercase().endsWith(".flac")) {
            val engine = NativeAudioEngine()
            try {
                val fd = android.os.ParcelFileDescriptor.open(
                    File(path), android.os.ParcelFileDescriptor.MODE_READ_ONLY
                )
                val created = engine.createFromFd(fd.fd, stream.nativeHandle)
                fd.close()
                if (created && engine.start()) {
                    if (engine.getSampleRate() != currentSampleRate) {
                        Log.w(TAG, "Rate mismatch: FLAC=${engine.getSampleRate()} USB=$currentSampleRate" +
                                " — falling back to ExoPlayer pipeline")
                        engine.stop()
                        engine.destroy()
                    } else {
                        nativeEngine = engine
                        isNativeEngineActive = true
                        engineNeedsInitialSeek = true
                        engineEndNotified = false
                        activeEnginePath = path
                        trackBitDepth = engine.getBitsPerSample()
                        Log.i(TAG, "Native FLAC engine started (paused, awaiting seek) for: ${File(path).name} ${trackBitDepth}-bit")
                        return
                    }
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Native engine failed: ${e.message}")
            }
            engine.destroy()
        }

        usbStreamingThread = UsbStreamingThread(stream).also { it.start() }
        Log.i(TAG, "Using ExoPlayer pipeline (non-FLAC or engine failed)")
    }


    private fun releaseUsbStream() {
        val stream = usbAudioStream ?: return
        usbAudioStream = null

        stream.stop()

        nativeEngine?.stop()
        nativeEngine?.destroy()
        nativeEngine = null
        isNativeEngineActive = false

        usbStreamingThread?.stop()
        usbStreamingThread = null

        val drained = stream.drainUrbs()
        Log.i(TAG, "USB stream drained $drained URBs")

        stream.release()

        clearForcedRouting()
        unmuteDelegateIfNeeded()
        Log.i(TAG, "USB audio stream released (device kept open)")
    }


    private fun muteDelegateIfNeeded() {
        if (!delegateMuted) { super.setVolume(0f); delegateMuted = true }
    }

    private fun unmuteDelegateIfNeeded() {
        if (delegateMuted) { super.setVolume(pendingVolume); delegateMuted = false }
    }


    private fun forceMediaToSpeaker() {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val speaker = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            if (speaker != null) {
                delegate.setPreferredDevice(speaker)
                Log.i(TAG, "Delegate routed to speaker")
            }
        } catch (e: Exception) {
            Log.w(TAG, "forceMediaToSpeaker failed: ${e.message}")
        }
    }

    private fun clearForcedRouting() {
        try { delegate.setPreferredDevice(null) } catch (_: Exception) {}
    }


    @Volatile private var attachedPlayer: Player? = null
    private var integrationListener: Player.Listener? = null

    /**
     * Attach this sink to an ExoPlayer instance. Registers an internal
     * [Player.Listener] that handles:
     * - Extracting the file path from each [MediaItem]'s URI
     * - Cleaning up finished native engines on track transitions
     * - Creating new native engines for local FLAC files
     * - Advancing to the next track when the native engine reaches EOF
     *
     * Must be called on the main thread, after [ExoPlayer.Builder.build].
     */
    fun attachToPlayer(player: Player) {
        if (attachedPlayer === player) {
            Log.i(TAG, "attachToPlayer: already attached to this player — skipping")
            return
        }

        val oldListener = integrationListener
        val oldPlayer = attachedPlayer
        if (oldListener != null && oldPlayer != null) {
            oldPlayer.removeListener(oldListener)
        }

        val listener = PlayerIntegrationListener()
        player.addListener(listener)
        attachedPlayer = player
        integrationListener = listener
        Log.i(TAG, "attachToPlayer: integration listener registered")
    }

    /** Detach from the current player. Call before player.release(). */
    fun detachFromPlayer() {
        val listener = integrationListener
        val player = attachedPlayer
        if (listener != null && player != null) {
            player.removeListener(listener)
        }
        attachedPlayer = null
        integrationListener = null
    }

    /** Player position (us) captured in onMediaItemTransition. Used to calculate
     *  the correct window offset on restore (first handleBuffer pts is at the
     *  restored position, not at 0). */
    @Volatile
    private var initialPlayerPositionUs: Long = 0L

    private inner class PlayerIntegrationListener : Player.Listener {
        /** URI of the last fully-processed [onMediaItemTransition].
         *  Used for idempotency guard to prevent infinite re-processing
         *  when redundant play() or setMediaItem triggers a re-transition
         *  to the same actively-playing item. */
        private var lastProcessedMediaUri: Uri? = null

        /** Capture audio format from the player. Called from multiple
         *  lifecycle points to ensure the format is known even when
         *  AudioSink.configure() is not invoked by the renderer. */
        private fun captureFormat() {
            val tracks = attachedPlayer?.currentTracks ?: return
            for (group in tracks.groups) {
                if (group.type == C.TRACK_TYPE_AUDIO && group.length > 0) {
                    val fmt = group.getTrackFormat(0)
                    if (fmt.sampleRate > 0) currentSampleRate = fmt.sampleRate
                    if (fmt.channelCount > 0) currentChannelCount = fmt.channelCount
                    if (fmt.pcmEncoding != Format.NO_VALUE) currentEncoding = fmt.pcmEncoding
                    Log.i(TAG, "captureFormat: rate=$currentSampleRate ch=$currentChannelCount enc=$currentEncoding (from tracks)")
                    return
                }
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            if (mediaItem == null) return

            val uri = mediaItem.localConfiguration?.uri

            if (uri != null && uri == lastProcessedMediaUri) {
                val engineRunning = nativeEngine?.isRunning == true
                val playerReady = attachedPlayer?.playbackState == Player.STATE_READY
                if (engineRunning || playerReady) {
                    Log.i(TAG, "onMediaItemTransition: same URI — skipping (idempotency guard)")
                    return
                }
            }
            lastProcessedMediaUri = uri

            initialPlayerPositionUs = (attachedPlayer?.currentPosition ?: 0L) * 1000L
            Log.i(TAG, "onMediaItemTransition: initialPlayerPos=${initialPlayerPositionUs / 1000}ms")

            val engineFinished = cleanupFinishedEngine()

            val resolvedPath = resolveTrackPath(uri)
            currentTrackPath = resolvedPath
            Log.i(TAG, "onMediaItemTransition: uri=$uri path=$resolvedPath")

            captureFormat()

            if (resolvedPath != null) {
                createEngineIfNeeded()
            }

            if (engineFinished) {
                attachedPlayer?.seekTo(0)
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY) {
                captureFormat()
            }
        }
    }

    /**
     * Resolve a [MediaItem]'s URI to a local file path for the native engine.
     *
     * - `file:///path/to/song.flac` → `/path/to/song.flac`
     * - `/storage/.../song.flac` (bare path) → as-is
     * - `content://media/external/audio/123` → resolved via ContentResolver
     * - `http://` or `https://` → null (ExoPlayer pipeline handles these)
     */
    private fun resolveTrackPath(uri: Uri?): String? {
        if (uri == null) return null
        return when (uri.scheme) {
            "file" -> uri.path
            "content" -> resolveContentUri(uri)
            "http", "https" -> {
                Log.i(TAG, "resolveTrackPath: HTTP URI → ExoPlayer pipeline (no native engine)")
                null
            }
            null -> {
                val pathStr = uri.toString()
                if (pathStr.startsWith("/")) pathStr else null
            }
            else -> null
        }
    }

    private fun resolveContentUri(uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.Audio.Media.DATA),
                null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
                    if (idx >= 0) cursor.getString(idx) else null
                } else null
            }
        } catch (e: Exception) {
            Log.w(TAG, "resolveContentUri failed: ${e.message}")
            null
        }
    }

    companion object {
        private const val TAG = "UsbAudioSink"

        /**
         * Wraps a [LoadControl] to suppress ExoPlayer loading when the native
         * FLAC engine is decoding directly to USB. Call BEFORE [ExoPlayer.Builder.build].
         *
         * @param delegate       Your app's LoadControl (e.g., DefaultLoadControl).
         * @param isEngineActive Lambda returning true when native engine is active.
         *                       Typical: `{ usbSink?.isNativeEngineActive == true }`
         */
        @JvmStatic
        @OptIn(UnstableApi::class)
        fun wrapLoadControl(
            delegate: LoadControl,
            isEngineActive: () -> Boolean
        ): LoadControl = NativeEngineAwareLoadControl(delegate, isEngineActive)
    }
}
