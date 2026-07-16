package com.meteor.kikoeruflutter

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import androidx.media3.common.MediaItem
import com.decent.usbaudio.UsbAudioDevice as DecentUsbAudioDevice

/**
 * Android native Hi-Res Audio plugin — thin facade.
 *
 * Delegates ExoPlayer lifecycle to [ExoPlayerManager], USB routing to
 * [UsbAudioRouter], and position pushing to [NativePositionPusher].
 *
 * Communicates with Dart side via MethodChannel "com.kikoeru.flutter/hires_audio".
 */
class HiResAudioPlugin private constructor(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL = "com.kikoeru.flutter/hires_audio"

        @Volatile
        private var instance: HiResAudioPlugin? = null

        fun getInstance(context: Context): HiResAudioPlugin {
            return instance ?: synchronized(this) {
                instance ?: HiResAudioPlugin(context.applicationContext).also { instance = it }
            }
        }
    }

    private val playerManager = ExoPlayerManager(context)
    private val usbRouter = UsbAudioRouter(context)
    private val positionPusher = NativePositionPusher { channel }

    private var channel: MethodChannel? = null
    private var isPlaying = false
    private var lastPlayUrl: String? = null
    private var lastPlayPositionMs: Long = 0L

    private val prefs: SharedPreferences = context.getSharedPreferences(
        "kikoeru_hires_prefs",
        Context.MODE_PRIVATE
    )
    private val KEY_USB_LIBUSB_ROUTING = "usb_libusb_routing_enabled"

    init {
        positionPusher.attachPlayer { playerManager.exoPlayer }
    }

    fun attachChannel(methodChannel: MethodChannel) {
        this.channel = methodChannel
        usbRouter.attach(methodChannel, playerManager)
        setupPlayerCallbacks()
    }


    fun autoRouteToUsbDac(device: android.hardware.usb.UsbDevice) {
        usbRouter.autoRouteToUsbDac(device)
    }

    fun onUsbDeviceDetached() {
        val pos = playerManager.exoPlayer?.currentPosition?.toLong() ?: 0L
        if (pos > 0) {
            android.util.Log.i("HiResAudio",
                "USB DAC detached — saving position ${pos}ms before release")
            lastPlayPositionMs = pos
        }
        usbRouter.onUsbDeviceDetached()
    }

    fun setUseAaudioSink(enabled: Boolean) {
        playerManager.setUseAaudioSink(enabled)
    }

    fun setBitPerfectMode(enabled: Boolean) {
        playerManager.updateBitPerfectMode(enabled)
    }

    fun setUseFfmpeg(enabled: Boolean) {
        playerManager.setUseFfmpeg(enabled)
    }

    fun setUseLibusbSink(enabled: Boolean) {
        playerManager.setUseLibusbSink(enabled)
        prefs.edit().putBoolean(KEY_USB_LIBUSB_ROUTING, enabled).apply()
        android.util.Log.i("HiResAudio",
            "USB libusb routing preference saved: $enabled")
    }

    /**
     * Whether the user has enabled USB DAC (libusb) routing in settings.
     * Read from SharedPreferences so [MainActivity] can decide whether
     * to show the USB permission dialog on device attach/startup.
     */
    fun isLibusbRoutingEnabled(): Boolean {
        return prefs.getBoolean(KEY_USB_LIBUSB_ROUTING, false)
    }


    private fun setupPlayerCallbacks() {
        playerManager.onPlaybackStateChanged = { playing ->
            this.isPlaying = playing
            channel?.invokeMethod("onPlaybackStateChanged", mapOf(
                "isPlaying" to playing
            ))
        }
        playerManager.onTrackEnded = {
            channel?.invokeMethod("onPlaybackStateChanged", mapOf(
                "isPlaying" to false
            ))
            channel?.invokeMethod("onTrackEnded", true)
        }
        playerManager.onFormatInfo = { sampleRate, bitDepth, channels ->
            channel?.invokeMethod("onFormatInfo", mapOf(
                "sampleRate" to sampleRate,
                "bitDepth" to bitDepth,
                "channels" to channels
            ))
        }
        playerManager.onBuffering = { buffering ->
            channel?.invokeMethod("onBuffering", mapOf(
                "buffering" to buffering
            ))
        }
        playerManager.onPlayerError = { message, errorCode ->
            channel?.invokeMethod("onError", mapOf(
                "message" to message,
                "errorCode" to errorCode
            ))
        }
        playerManager.onExclusiveStatusChanged = { status ->
            channel?.invokeMethod("onExclusiveModeChanged", status)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> {
                result.success(true)
            }
            "play" -> {
                android.util.Log.i("HiResAudio", "→ Dart play() called")
                val url = call.argument<String>("url") ?: ""
                val sampleRate = call.argument<Int>("sampleRate") ?: 0
                val bitDepth = call.argument<Int>("bitDepth") ?: 0
                val startPositionMs = call.argument<Int>("startPositionMs") ?: 0

                if (url.isEmpty()) {
                    result.error("INVALID_ARGS", "url is required", null)
                    return
                }

                val positionToUse: Long = when {
                    startPositionMs > 0 -> startPositionMs.toLong()
                    lastPlayPositionMs > 0 && url == lastPlayUrl -> lastPlayPositionMs
                    else -> 0L
                }

                playerManager.currentSampleRate = sampleRate
                playerManager.currentBitDepth = bitDepth
                lastPlayUrl = url
                lastPlayPositionMs = positionToUse
                positionPusher.resetDurationCache()

                try {
                    setupPlayerCallbacks()
                    playerManager.releasePlayer()
                    val player = playerManager.getOrCreatePlayer()

                    val mediaItem = MediaItem.Builder()
                        .setUri(Uri.parse(url))
                        .build()

                    player.setMediaItem(mediaItem)
                    if (sampleRate > 0 && playerManager.useAaudioSink) {
                        android.util.Log.i("HiResAudio", "Target sample rate: ${sampleRate}Hz")
                    }
                    player.prepare()
                    if (positionToUse > 0) {
                        android.util.Log.i(
                            "HiResAudio",
                            "Starting from ${positionToUse}ms (explicit=$startPositionMs, saved=${lastPlayPositionMs})"
                        )
                        player.seekTo(positionToUse)
                    }
                    player.play()

                    positionPusher.start()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("PLAY_ERROR", "Failed to play: ${e.message}", null)
                }
            }
            "pause" -> {
                android.util.Log.i("HiResAudio", "→ Dart pause() called (exoPlayer=${playerManager.exoPlayer != null})")
                val pos = playerManager.exoPlayer?.currentPosition?.toLong() ?: 0L
                if (pos > 0) {
                    lastPlayPositionMs = pos
                }
                positionPusher.stop()
                playerManager.exoPlayer?.pause()
                result.success(true)
            }
            "resume" -> {
                android.util.Log.i(
                    "HiResAudio",
                    "→ Dart resume() called (exoPlayer=${playerManager.exoPlayer != null}, lastPlayUrl=${lastPlayUrl != null}, lastPlayPositionMs=${lastPlayPositionMs}ms)"
                )
                if (playerManager.exoPlayer != null) {
                    playerManager.exoPlayer?.play()
                    positionPusher.start()
                    result.success(true)
                } else if (lastPlayUrl != null) {
                    kotlin.runCatching {
                        setupPlayerCallbacks()
                        playerManager.releasePlayer()
                        val player = playerManager.getOrCreatePlayer()

                        val mediaItem = MediaItem.Builder()
                            .setUri(Uri.parse(lastPlayUrl!!))
                            .build()

                        player.setMediaItem(mediaItem)
                        player.prepare()
                        if (lastPlayPositionMs > 0) {
                            android.util.Log.i(
                                "HiResAudio",
                                "Resuming cold path from ${lastPlayPositionMs}ms"
                            )
                            player.seekTo(lastPlayPositionMs)
                        }
                        player.play()
                        positionPusher.start()
                        result.success(true)
                    }.onFailure { e ->
                        result.error("PLAY_ERROR", "Failed to resume: ${e.message}", null)
                    }
                } else {
                    result.error("NO_URL", "No URL to resume", null)
                }
            }
            "stop" -> {
                positionPusher.stop()
                playerManager.exoPlayer?.stop()
                playerManager.exoPlayer?.seekTo(0)
                isPlaying = false
                result.success(true)
            }
            "seekTo" -> {
                val positionMs = call.argument<Int>("positionMs") ?: 0
                playerManager.exoPlayer?.seekTo(positionMs.toLong())
                result.success(true)
            }
            "getPosition" -> {
                val positionMs = playerManager.exoPlayer?.currentPosition?.toInt() ?: 0
                result.success(positionMs)
            }
            "getDuration" -> {
                val durationMs = playerManager.exoPlayer?.duration?.toInt() ?: 0
                result.success(durationMs)
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume") ?: 1.0
                playerManager.exoPlayer?.volume = volume.toFloat()
                result.success(true)
            }
            "setSampleRate" -> {
                playerManager.currentSampleRate = call.argument<Int>("sampleRate") ?: 0
                result.success(true)
            }
            "getUsbAudioDevices" -> {
                result.success(usbRouter.refreshUsbDevices())
            }
            "setUsbBypassMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val deviceId = call.argument<Int>("deviceId")
                usbRouter.setUsbBypassMode(enabled, deviceId)
                result.success(true)
            }
            "routeToUsbDevice" -> {
                val deviceId = call.argument<Int>("deviceId") ?: -1
                val success = usbRouter.routeToDeviceById(deviceId)
                if (success) {
                    result.success(true)
                } else {
                    result.error("DEVICE_NOT_FOUND", "USB device not found", null)
                }
            }
            "clearUsbRouting" -> {
                usbRouter.clearUsbRouting()
                result.success(true)
            }
            "isUsbRouted" -> {
                result.success(usbRouter.isRoutingToUsbDac)
            }
            "setPreferredMixerAttributes" -> {
                val deviceId = call.argument<Int>("deviceId") ?: -1
                val sampleRate = call.argument<Int>("sampleRate") ?: 0
                val bitDepth = call.argument<Int>("bitDepth") ?: 0
                result.success(usbRouter.applyMixerAttributes(deviceId, sampleRate, bitDepth))
            }
            "clearPreferredMixerAttributes" -> {
                usbRouter.clearMixerAttributes()
                result.success(true)
            }
            "getPreferredMixerAttributes" -> {
                result.success(usbRouter.getMixerAttributes())
            }
            "getOutputSampleRate" -> {
                val nativeRate = android.media.AudioTrack.getNativeOutputSampleRate(
                    android.media.AudioManager.STREAM_MUSIC
                )
                result.success(nativeRate)
            }
            "getHardwareSampleRate" -> {
                var hardwareRate = 0
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                val devices = audioManager?.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
                val activeDevice = devices?.firstOrNull { it.isSource == false }
                if (activeDevice != null) {
                    val rates = activeDevice.sampleRates
                    if (rates != null && rates.isNotEmpty()) {
                        hardwareRate = rates.maxOrNull() ?: 0
                    }
                }
                if (hardwareRate <= 0) {
                    hardwareRate = android.media.AudioTrack.getNativeOutputSampleRate(
                        android.media.AudioManager.STREAM_MUSIC
                    )
                }
                result.success(hardwareRate)
            }
            "setUseFfmpeg" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                setUseFfmpeg(enabled)
                result.success(true)
            }
            "setUseLibusbSink" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                setUseLibusbSink(enabled)
                result.success(true)
            }
            "setUseAaudioSink" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                playerManager.setUseAaudioSink(enabled)
                result.success(true)
            }
            "setBitPerfectMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                playerManager.updateBitPerfectMode(enabled)
                result.success(true)
            }
            "getActiveOutputDeviceType" -> {
                result.success(usbRouter.getActiveOutputDeviceType())
            }
            "release" -> {
                playerManager.releasePlayer()
                result.success(true)
            }
            "requestUsbPermission" -> {
                val granted = usbRouter.requestUsbPermission()
                if (granted) {
                    result.success(true)
                } else {
                    val device = DecentUsbAudioDevice.getInstance(context).findUsbAudioDevice()
                    if (device != null) {
                        result.success(false) // Permission requested asynchronously
                    } else {
                        result.error("NO_DEVICE", "No USB audio device found", null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun cleanup() {
        positionPusher.stop()
        usbRouter.cleanup()
        playerManager.releasePlayer()
    }
}
