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

            // Apply deferred USB reconfiguration (cross-rate transition)
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
            // Clean up dead engine if exists
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
                // Engine starts paused with engineNeedsInitialSeek = true.
                // Temporarily unblock LoadControl so ExoPlayer sends at least one
                // handleBuffer — needed to capture presentationTimeUs and seek.
                // Without this, the LoadControl blocks immediately and the engine
                // stays paused forever (HTTP→local transition race).
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
    @Volatile private var usbDeviceLost: Boolean = false

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

        // Always capture the actual sample rate and channel count so
        // handleBuffer can create the USB stream lazily even when the
        // bit-perfect path was skipped (e.g. HTTP MP3 placeholder
        // format).
        val fmtSr = inputFormat.sampleRate.takeIf { it > 0 }
        val fmtCh = inputFormat.channelCount.takeIf { it > 0 }
        if (fmtSr != null) currentSampleRate = fmtSr
        if (fmtCh != null) currentChannelCount = fmtCh

        // If native engine is still playing the SAME track AND the rate didn't change,
        // don't touch it. This happens when ExoPlayer pre-buffers the next track ~10s
        // before EOF. But if the track or rate changed, destroy and reconfigure.
        if (nativeEngine?.isRunning == true) {
            val trackChanged = currentTrackPath != activeEnginePath
            if (!trackChanged) {
                // Same track, ExoPlayer pre-buffering — defer reconfiguration
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
            // Track changed (manual skip) — destroy engine and proceed
            Log.i(TAG, "configure: track changed, destroying engine")
        }
        // Track changed or engine finished — destroy old engine
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

                // ── Force delegate AudioTrack to use a safe sample rate ──
                // Android AudioTrack only supports certain sample rates for the
                // built-in speaker/headphone output (common max: 48000 Hz).
                // Ultra-high sample rates like 352800 Hz thrown an
                // IllegalStateException from AudioTrack.getMinBufferSize().
                //
                // The delegate is muted anyway (volume=0, routed to speaker)
                // — its only purpose is to keep ExoPlayer's clock alive and
                // prevent AudioFlinger from touching the USB DAC. The actual
                // audio goes through the USB isochronous stream at the native
                // source rate, which IS correct.
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

        // Bit-perfect not available yet (no device, no permission,
        // or placeholder format). Create a delegate AudioTrack for
        // ExoPlayer's clock. The USB stream is created lazily in
        // handleBuffer once the device and actual format are known.
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
        // USB DAC: if the stream doesn't exist yet, create it lazily.
        // This handles the case where configure() was called with a
        // placeholder format (sr=0 / ch=0) or the USB device wasn't
        // available yet — by the time the first audio buffer arrives,
        // the actual format should be known.
        if (config.bitPerfectEnabled && usbAudioStream?.isAlive != true) {
            val ok = reconnectUsbStreamIfNeeded()
            if (!ok) {
                // If format not yet known (configure() was never called),
                // try to read it from the ExoPlayer's currentTracks.
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
                    // reconnect guarded by reconnectAttempted — if it's set
                    // (previous failure), try a direct configureUsbBitPerfect
                    // since the format is now known.
                    if (usbAudioStream?.isAlive != true && !usbDeviceLost) {
                        if (lastReconnectAttemptMs > 0 &&
                            SystemClock.elapsedRealtime() - lastReconnectAttemptMs < RECONNECT_COOLDOWN_MS) {
                            // Still within cooldown window — skip this attempt silently
                            // to avoid log spam and excessive USB device-list scanning.
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

            // Fallback engine creation: if no engine and no streaming thread,
            // try creating one now (path and USB rate should both be correct by this point)
            if (nativeEngine == null && usbStreamingThread == null) {
                startNativeEngineIfFlac(stream)
                // Engine starts paused. The usbStartMediaTimeNeedsInit block below
                // will capture presentationTimeUs and seek to the correct position.
            }

            // Capture media timeline offset from first buffer (needed for position tracking)
            if (usbStartMediaTimeNeedsInit) {
                usbStartMediaTimeUs = maxOf(0L, presentationTimeUs)
                usbStartMediaTimeNeedsInit = false
                // Cancel startup safety timeout — handleBuffer arrived, engine will be
                // properly seeked and resumed.
                startupSafetyTimeout?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
                startupSafetyTimeout = null
                // Save window offset once per track (not reset by flush/seek).
                // windowOffset = ExoPlayer timeline position of track start (position 0).
                // On fresh start: initialPlayerPosition=0 → offset = pts (correct).
                // On restore at 158s: initialPlayerPosition=158s → offset = pts - 158s (correct).
                if (windowOffsetUs < 0) {
                    windowOffsetUs = presentationTimeUs - initialPlayerPositionUs
                }
                Log.i(TAG, "startMediaTimeUs=$usbStartMediaTimeUs windowOffset=$windowOffsetUs initialPos=${initialPlayerPositionUs / 1000}ms")

                // After a flush (seek) or initial start, seek the native engine
                // to the correct position and resume it.
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
                // Re-block LoadControl now that we have the position.
                // flush() temporarily unblocked it to allow this handleBuffer call.
                if (nativeEngine?.isRunning == true) {
                    isNativeEngineActive = true
                }
            }

            // Native FLAC engine handles decode+USB directly — ignore ExoPlayer data.
            val engine = nativeEngine
            if (engine != null) {
                if (engine.isRunning) {
                    buffer.position(buffer.limit())
                    return true
                }
                // Engine finished playing — clean up for next track.
                // Lazy creation at the top of handleBuffer will create a new engine
                // with the correct currentTrackPath on the next call.
                Log.i(TAG, "Native engine finished — cleaning up for next track")
                engine.destroy()
                nativeEngine = null
                isNativeEngineActive = false
                activeEnginePath = null
                windowOffsetUs = -1L
                usbStartMediaTimeNeedsInit = true
                // Return true for this buffer — next handleBuffer will create new engine
                buffer.position(buffer.limit())
                return true
            }

            val thread = usbStreamingThread ?: return true

            // Backpressure: if queue is nearly full, tell ExoPlayer to retry later.
            // This paces the renderer to the USB DAC's consumption rate without
            // depending on the delegate AudioTrack.
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

            // Advance buffer and return true — no delegate dependency.
            buffer.position(buffer.limit())
            return true
        }

        unmuteDelegateIfNeeded()
        return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
    }

    // ── Position tracking via USB framesWritten ────────────────────────

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

            // Detect engine finished — advance to next track internally.
            // ExoPlayer's renderer never reaches outputStreamEnded because
            // LoadControl blocked loading, so we skip externally via the Player ref.
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

            // Native engine: absolute FLAC position + window offset
            if (streamAlive && engineCreated && windowOffsetUs >= 0) {
                return windowOffsetUs + engine!!.getPositionUs()
            }

            // ExoPlayer pipeline fallback: relative framesWritten + startMediaTime
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
            // Engine still running → not ended
            if (engine != null && engine.isRunning) return false
            // Engine exists but stopped → it finished (EOF). Signal ended directly.
            // Cannot delegate to super because LoadControl blocked ExoPlayer's loading,
            // so the delegate never reached end-of-stream on its own.
            if (engine != null && !engine.isRunning) return true
        }
        return super.isEnded()
    }

    override fun hasPendingData(): Boolean {
        if (config.bitPerfectEnabled) {
            // Engine running → has pending data
            if (nativeEngine?.isRunning == true) return true
            if (usbStreamingThread?.hasPendingData() == true) return true
        }
        return super.hasPendingData()
    }

    override fun playToEndOfStream() {
        handledEndOfStream = true
        // Always propagate to delegate — ExoPlayer needs this signal to
        // detect end-of-stream and transition to the next track.
        super.playToEndOfStream()
    }

    override fun play() {
        super.play()
        isPlaying = true

        // USB DAC hot-plug reconnect: if the native stream was destroyed by
        // detach, rebuild it before resuming engine/thread (otherwise writes
        // fail with errno=25 on the stale fd).
        // Reset the flag so a retry is attempted even if handleBuffer already
        // tried and failed (USB may have been reconnected since then).
        reconnectAttempted = false
        reconnectUsbStreamIfNeeded()

        val resumed = if (!engineNeedsInitialSeek) { nativeEngine?.resume(); true } else false
        usbStreamingThread?.resumeStreaming()
        Log.i(TAG, "play() needsSeek=$engineNeedsInitialSeek resumed=$resumed")

        // ── Startup silence safety timeout ───────────────────────────────────
        // If the native engine was just created (engineNeedsInitialSeek = true),
        // it stays paused until handleBuffer() captures presentationTimeUs and
        // seeks the engine to the correct position. Under normal operation,
        // handleBuffer() arrives within milliseconds of play().
        //
        // However, if LoadControl blocks before the first buffer (e.g. race
        // between onMediaItemTransition and renderer init), handleBuffer() may
        // never arrive, leaving the engine paused forever → startup silence.
        //
        // Safety net: force-resume the engine after 500ms if no handleBuffer
        // arrived. The position at resume may be slightly wrong (offset by the
        // gap between ExoPlayer timeline and FLAC absolute position), but
        // audible audio immediately is better than permanent silence.
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
        // Cancel startup safety timeout when user pauses before first buffer arrives
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
        // Native engine handles its own flush/seek internally
        // ExoPlayer pipeline: flush queue + native stream
        usbStreamingThread?.flush()
        usbAudioStream?.flush()
        usbStartMediaTimeNeedsInit = true
        handledEndOfStream = false
        // Temporarily unblock LoadControl so ExoPlayer loads at least one chunk
        // after seek. handleBuffer will re-block once it captures presentationTimeUs.
        // Without this, the LoadControl blocks ALL post-seek loading and the engine
        // never knows where to seek to.
        if (nativeEngine?.isRunning == true) {
            isNativeEngineActive = false
        }
    }

    override fun reset() {
        super.reset()
        // Cancel any pending startup safety timeout on reset
        startupSafetyTimeout?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
        startupSafetyTimeout = null
        // USB stream survives reset — configure() manages its lifecycle.
        // ExoPlayer calls reset() frequently (track changes, seeks).
        // Killing USB here causes audio to briefly route to the speaker.
    }

    override fun release() {
        releaseUsbStream()
        super.release()
    }

    // ── USB bit-perfect configuration ───────────────────────────────

    private fun configureUsbBitPerfect(sampleRate: Int, channelCount: Int, encoding: Int) {
        // NOTE: engine is NOT destroyed here. configure() returns early if engine
        // is still running. If we reach here, the engine is already dead or null.

        // Cache check — avoid needless USB stream recreation.
        // Short-circuit when encoding changed (e.g. WAV 24-bit → MP3 16-bit
        // at the same sample rate) so the USB stream is rebuilt for the new
        // PCM format. Without this, the delegate AudioTrack may produce
        // silence when the USB DAC interface is claimed by UsbAudioSink.
        if (sampleRate == currentSampleRate && channelCount == currentChannelCount
            && encoding == currentEncoding && usbAudioStream?.isAlive == true) {
            Log.d(TAG, "USB stream cached for rate=$sampleRate ch=$channelCount — reusing")
            // Engine will be created lazily in handleBuffer when currentTrackPath is set
            return
        }

        if (usbAudioStream != null) releaseUsbStream()

        val usbDevice = usbAudioDevice.findUsbAudioDevice() ?: return
        var deviceInfo = usbAudioDevice.openDevice(usbDevice)
        if (deviceInfo == null) {
            Log.e(TAG, "Failed to open USB device")
            return
        }

        // Always use the DAC's highest supported bit depth (standard practice).
        // Sources with lower bit depth are zero-padded in the LSBs.
        val bitDepth = deviceInfo.bestBitDepth
        val altSetting = deviceInfo.bestAltSetting
        // Convert encoding constant to bit depth for accurate logging.
        // For FLAC files, trackBitDepth is set by NativeAudioEngine.getBitsPerSample().
        // For all other formats (WAV, etc.), derive from currentEncoding / encoding param.
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
            Log.e(TAG, "USB stream creation failed")
            stream.release()
            return
        }

        // ─── xHCI-verified transition sequence (from USB protocol analysis) ───
        //
        // 1. setAlt(0)       → xHCI Configure Endpoint (FREE old rings)
        // 2. SET_CUR          → write new sample rate to Clock Source
        // 3. GET_CUR          → verify clock accepted (CLOCK_VALID_CONTROL)
        // 4. setAlt(0) AGAIN  → defensive reset after clock change
        // 5. setAlt(N)        → xHCI Configure Endpoint (ALLOC new rings)
        // 6. wait ~47ms       → DAC PLL lock time
        // 7. start            → submit URBs

        // Step 1: setAlt(0) — FREE old ISO rings
        if (!usbAudioDevice.setAltSetting(0)) {
            Log.w(TAG, "setAlt(0) failed — stale fd, reopening device...")
            usbAudioDevice.closeDevice()
            stream.release()
            deviceInfo = usbAudioDevice.openDevice(usbDevice)
            if (deviceInfo == null) {
                Log.e(TAG, "Failed to reopen USB device")
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

        // Step 2: SET_CUR — write new sample rate
        usbAudioDevice.setSampleRate(sampleRate)

        // Step 3: GET_CUR(CLOCK_VALID_CONTROL) — verify clock is locked
        val clockValid = usbAudioDevice.readClockValid()
        Log.i(TAG, "Step 2-3: SET_CUR=$sampleRate, CLOCK_VALID=$clockValid")

        // Step 4: setAlt(0) AGAIN — defensive reset after clock change
        usbAudioDevice.setAltSetting(0)
        Log.i(TAG, "Step 4: setAlt(0) again — defensive reset")

        // Step 5: setAlt(N) — ALLOC new ISO rings
        val altResult = usbAudioDevice.setAltSetting(altSetting)
        Log.i(TAG, "Step 5: setAlt($altSetting): $altResult — new ISO ring allocated")

        // Step 6: wait ~47ms — DAC PLL lock time
        Thread.sleep(50)

        if (!stream.start()) {
            Log.e(TAG, "USB stream start failed")
            stream.release()
            return
        }

        usbAudioStream = stream
        reconnectAttempted = false  // fresh stream — reset for next detach cycle
        usbDeviceLost = false  // device is back online
        lastReconnectAttemptMs = 0L  // reset cooldown counter
        currentSampleRate = sampleRate
        currentChannelCount = channelCount
        muteDelegateIfNeeded()

        // Try to create engine now (works for first track where onMediaItemTransition
        // fired before configure). For subsequent tracks, createEngineIfNeeded() in
        // onMediaItemTransition handles it (path is correct by then).
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
        // Only attempt if bit-perfect is enabled and we have a known format
        if (!config.bitPerfectEnabled || currentSampleRate <= 0 || currentChannelCount <= 0) {
            return false
        }

        // Stream is alive — no reconnect needed
        if (usbAudioStream?.isAlive == true) {
            // Reset flags so future detach/reconnect cycles are detected
            reconnectAttempted = false
            usbDeviceLost = false
            lastReconnectAttemptMs = 0L  // reset cooldown counter
            return false
        }

        // Don't retry if we already tried for this disconnect episode
        // BUT if more than 10 seconds have passed since the last attempt,
        // retry anyway — the device may have been reconnected since then.
        if (reconnectAttempted) {
            if (usbDeviceLost && lastReconnectAttemptMs > 0 &&
                SystemClock.elapsedRealtime() - lastReconnectAttemptMs > 10_000L) {
                Log.i(TAG, "reconnectUsbStreamIfNeeded: 10s elapsed since last attempt — retrying")
                reconnectAttempted = false
                usbDeviceLost = false
            } else {
                return false
            }
        }
        reconnectAttempted = true

        // Check if a USB audio device is present and we have permission
        Log.i(TAG, "reconnectUsbStreamIfNeeded: stream dead — checking for USB device")
        val device = usbAudioDevice.findUsbAudioDevice()
        if (device == null) {
            Log.w(TAG, "reconnectUsbStreamIfNeeded: no USB device found, marking as lost")
            reconnectAttempted = true  // prevent repeated scanning on every buffer
            usbDeviceLost = true
            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
            return false
        }
        if (!usbAudioDevice.hasPermission(device)) {
            Log.w(TAG, "reconnectUsbStreamIfNeeded: USB device found but no permission")
            // Don't set usbDeviceLost — user may grant permission later
            return false
        }

        Log.i(TAG, "reconnectUsbStreamIfNeeded: REBUILDING native USB stream for ${device.productName}")

        // Release any stale stream (defensive — nativeHandle is already 0L)
        if (usbAudioStream != null) {
            releaseUsbStream()
        }

        // Rebuild from scratch using the same format as the current track
        configureUsbBitPerfect(currentSampleRate, currentChannelCount, currentEncoding)

        val rebuilt = usbAudioStream?.isAlive == true
        if (rebuilt) {
            Log.i(TAG, "reconnectUsbStreamIfNeeded: ✓ stream rebuilt successfully")
            // Reset flags so a future detach/reconnect cycle can re-trigger
            reconnectAttempted = false
            usbDeviceLost = false
            lastReconnectAttemptMs = 0L  // reset cooldown counter
        } else {
            Log.w(TAG, "reconnectUsbStreamIfNeeded: ✗ stream rebuild failed")
            lastReconnectAttemptMs = SystemClock.elapsedRealtime()
        }
        return rebuilt
    }

    /** Try to start a native FLAC engine. Falls back to ExoPlayer streaming thread. */
    @Synchronized
    private fun startNativeEngineIfFlac(stream: UsbAudioStream) {
        if (nativeEngine != null) return  // already created (synchronized method)

        // Stop existing streaming thread (mutually exclusive with native engine)
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
                    // Verify FLAC sample rate matches USB stream — prevents distortion
                    // when ExoPlayer's queue and onMediaItemTransition disagree about
                    // which track is playing (e.g., cross-album Recently Played lists).
                    if (engine.getSampleRate() != currentSampleRate) {
                        Log.w(TAG, "Rate mismatch: FLAC=${engine.getSampleRate()} USB=$currentSampleRate" +
                                " — falling back to ExoPlayer pipeline")
                        engine.stop()
                        engine.destroy()
                    } else {
                        // Thread starts paused (nativeStart sets paused=true).
                        // handleBuffer will set the seek position and resume the
                        // thread once presentationTimeUs is available — prevents
                        // duplicate frame decode before seek.
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

        // Fallback: ExoPlayer pipeline via streaming thread
        usbStreamingThread = UsbStreamingThread(stream).also { it.start() }
        Log.i(TAG, "Using ExoPlayer pipeline (non-FLAC or engine failed)")
    }

    // ── USB stream release ──────────────────────────────────────────

    private fun releaseUsbStream() {
        val stream = usbAudioStream ?: return
        usbAudioStream = null

        // Stop USB stream FIRST — sets ctx->running=false, which unblocks
        // submitPcmToUrbs inside the native engine's decode thread.
        // Without this, nativeEngine.stop() deadlocks on pthread_join.
        stream.stop()

        // Now safe to stop native engine (decode thread can exit)
        nativeEngine?.stop()
        nativeEngine?.destroy()
        nativeEngine = null
        isNativeEngineActive = false

        // Stop the streaming thread (drains queue, joins thread)
        usbStreamingThread?.stop()
        usbStreamingThread = null

        // Drain ALL in-flight URBs — MUST complete before setAlt(0)
        val drained = stream.drainUrbs()
        Log.i(TAG, "USB stream drained $drained URBs")

        // Release native context
        stream.release()

        // Keep device connection open between tracks (standard practice)
        clearForcedRouting()
        unmuteDelegateIfNeeded()
        Log.i(TAG, "USB audio stream released (device kept open)")
    }

    // ── Delegate volume management ──────────────────────────────────

    private fun muteDelegateIfNeeded() {
        if (!delegateMuted) { super.setVolume(0f); delegateMuted = true }
    }

    private fun unmuteDelegateIfNeeded() {
        if (delegateMuted) { super.setVolume(pendingVolume); delegateMuted = false }
    }

    // ── Audio routing helpers ───────────────────────────────────────

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

    // ── Player integration (attachToPlayer) ──────────────────────

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
        // Guard: already attached to this exact player instance — skip
        if (attachedPlayer === player) {
            Log.i(TAG, "attachToPlayer: already attached to this player — skipping")
            return
        }

        // Detach from previous player if any
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

            // ── Idempotency guard ─────────────────────────────────────────────
            // Skip re-processing when the same URI arrives while the current
            // track is still actively playing. Prevents the infinite loop:
            //   play() → onMediaItemTransition → seekTo(0)/createEngine
            //   → another onMediaItemTransition → ...
            //
            // We use two checks:
            //   1. URI matches last processed item (same track identity)
            //   2. Native engine is running (local FLAC actively decoding)
            //      OR player is in READY state (HTTP/ExoPlayer pipeline)
            //
            // Genuine repeat/loop (REASON_PLAYBACK_ENDED) is still allowed
            // because the engine would have finished (not running) and the
            // player transitions through IDLE → BUFFERING → READY.
            // ──────────────────────────────────────────────────────────────────
            if (uri != null && uri == lastProcessedMediaUri) {
                val engineRunning = nativeEngine?.isRunning == true
                val playerReady = attachedPlayer?.playbackState == Player.STATE_READY
                if (engineRunning || playerReady) {
                    Log.i(TAG, "onMediaItemTransition: same URI — skipping (idempotency guard)")
                    return
                }
            }
            lastProcessedMediaUri = uri

            // Capture player position BEFORE engine creation. On restore this is
            // the saved position (e.g., 158s). On fresh start this is 0.
            initialPlayerPositionUs = (attachedPlayer?.currentPosition ?: 0L) * 1000L
            Log.i(TAG, "onMediaItemTransition: initialPlayerPos=${initialPlayerPositionUs / 1000}ms")

            // 1. Clean up finished engine from previous track
            val engineFinished = cleanupFinishedEngine()

            // 2. Resolve file path from URI
            val resolvedPath = resolveTrackPath(uri)
            currentTrackPath = resolvedPath
            Log.i(TAG, "onMediaItemTransition: uri=$uri path=$resolvedPath")

            // 3. Capture audio format — needed for lazy USB stream creation
            //    when AudioSink.configure() is not called by the renderer
            //    (observed with FfmpegAudioRenderer for MP3 tracks).
            captureFormat()

            // 4. Create engine if local FLAC
            if (resolvedPath != null) {
                createEngineIfNeeded()
            }

            // 5. If previous engine finished, reset position for new track
            if (engineFinished) {
                attachedPlayer?.seekTo(0)
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY) {
                // Capture format again when player becomes ready — the
                // audioFormat may not be available in onMediaItemTransition
                // if the renderer hasn't initialized yet.
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
                // Bare path string (no scheme) — common in local music players
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
