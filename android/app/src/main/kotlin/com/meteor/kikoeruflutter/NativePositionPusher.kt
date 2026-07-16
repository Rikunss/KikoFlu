package com.meteor.kikoeruflutter

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Pushes position, buffered position, and duration from ExoPlayer to Dart
 * at 50ms intervals (~20 fps) using a dedicated Handler loop.
 *
 * This replaces Dart-side polling via MethodChannel (which adds roundtrip
 * latency), providing smooth progress bar updates matching just_audio's
 * native event rate.
 *
 * @param channelRef Provider for the active MethodChannel (may be null during teardown).
 */
class NativePositionPusher(
    private val channelRef: () -> MethodChannel?
) {

    private var handler: Handler? = null
    @Volatile
    private var active: Boolean = false
    private var lastPushedDurationMs: Long = -1L

    /** Reference to the ExoPlayer to read position/duration from. */
    private var playerRef: (() -> androidx.media3.exoplayer.ExoPlayer?)? = null

    /**
     * Attach to an ExoPlayer for position queries.
     */
    fun attachPlayer(playerProvider: () -> androidx.media3.exoplayer.ExoPlayer?) {
        playerRef = playerProvider
    }

    /**
     * Detach from the ExoPlayer (e.g., during teardown).
     */
    fun detachPlayer() {
        playerRef = null
    }

    private val runnable = object : Runnable {
        override fun run() {
            if (!active) return

            val player = playerRef?.invoke()
            if (player == null) {
                handler?.postDelayed(this, 50)
                return
            }

            val channel = channelRef()

            val posMs = player.currentPosition.toInt()
            channel?.invokeMethod("onPositionChanged", posMs)

            val bufPosMs = player.bufferedPosition.toInt()
            if (bufPosMs >= 0) {
                channel?.invokeMethod("onBufferedPositionChanged", bufPosMs)
            }

            val durMs = player.duration
            if (durMs > 0 && durMs != androidx.media3.common.C.TIME_UNSET && durMs != lastPushedDurationMs) {
                channel?.invokeMethod("onDurationChanged", durMs.toInt())
                lastPushedDurationMs = durMs
            }

            if (active) {
                handler?.postDelayed(this, 50)
            }
        }
    }

    /**
     * Start the position push loop. Safe to call multiple times.
     */
    fun start() {
        active = true
        if (handler == null) {
            handler = Handler(Looper.getMainLooper())
        }
        handler?.removeCallbacks(runnable)
        handler?.post(runnable)
    }

    /**
     * Stop the position push loop.
     */
    fun stop() {
        active = false
        handler?.removeCallbacks(runnable)
    }

    /**
     * Reset the duration cache so the next valid duration is pushed.
     */
    fun resetDurationCache() {
        lastPushedDurationMs = -1L
    }
}
