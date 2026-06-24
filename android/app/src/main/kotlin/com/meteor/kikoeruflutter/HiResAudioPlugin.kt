package com.meteor.kikoeruflutter

import android.content.Context
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

    // ── Delegated managers ───────────────────────────────────────────────
    private val playerManager = ExoPlayerManager(context)
    private val usbRouter = UsbAudioRouter(context)
    private val positionPusher = NativePositionPusher { channel }

    private var channel: MethodChannel? = null
    private var isPlaying = false
    private var lastPlayUrl: String? = null
    private var lastPlayPositionMs: Long = 0L

<<<<<<< HEAD
    // ── Native position push (Handler loop every 50ms) ──
    // Instead of Dart polling via MethodChannel (which adds roundtrip latency),
    // Kotlin pushes position & duration to Dart at 50ms intervals (~20 fps)
    // for smooth progress bar updates matching just_audio's native event rate.
    private var positionPushHandler: Handler? = null
    @Volatile
    private var positionPushActive = false
    // Tracks last pushed duration to avoid duplicate MethodChannel calls
    private var lastPushedDurationMs = -1L
    private val positionPushRunnable = object : Runnable {
        override fun run() {
            // Guard: don't execute if push was stopped
            if (!positionPushActive) return
            val player = exoPlayer ?: run {
                positionPushHandler?.postDelayed(this, 50)
                return
            }

            // Push position — always, no guard needed
            val posMs = player.currentPosition.toInt()
            channel?.invokeMethod("onPositionChanged", posMs)

            // Push buffered position — used by Dart-side StreamingSpeedTracker
            // to estimate download speed. ExoPlayer reports the position up to
            // which media data is available for playback without re-buffering.
            val bufPosMs = player.bufferedPosition.toInt()
            if (bufPosMs >= 0) {
                channel?.invokeMethod("onBufferedPositionChanged", bufPosMs)
            }

            // Push duration every tick — ExoPlayer eventually reports a valid value
            val durMs = player.duration
            if (durMs > 0 && durMs != androidx.media3.common.C.TIME_UNSET && durMs != lastPushedDurationMs) {
                channel?.invokeMethod("onDurationChanged", durMs.toInt())
                lastPushedDurationMs = durMs
            }

            // Schedule next tick in 50ms (only if still active)
            if (positionPushActive) {
                positionPushHandler?.postDelayed(this, 50)
            }
        }
    }

    private fun startPositionPush() {
        positionPushActive = true
        if (positionPushHandler == null) {
            positionPushHandler = Handler(Looper.getMainLooper())
        }
        positionPushHandler?.removeCallbacks(positionPushRunnable)
        // Immediate first tick, then every 50ms
        positionPushHandler?.post(positionPushRunnable)
    }

    private fun stopPositionPush() {
        positionPushActive = false
        positionPushHandler?.removeCallbacks(positionPushRunnable)
    }

    // ── Audio Sink Selection ──
    // Priority: libusb > AAudio > Default
    // libusb (LibusbAudioSink) is the true bit-perfect path via USB DAC.
    // AAudio (AaudioAudioSink) is the mixer-bypass path for built-in audio.
    // Default (DefaultAudioSink) uses Android AudioTrack.

    /// When true, use [LibusbAudioSink] for direct USB DAC output.
    /// Has priority over [useAaudioSink].
    private var useLibusbSink = false

    /// When true, use [AaudioAudioSink] for AAudio exclusive mode.
    /// Only used when [useLibusbSink] is false.
    private var useAaudioSink = false

    /// When false, FfmpegAudioRenderer is NOT prepended to the renderer list.
    /// For low-bitrate lossy formats (MP3 <256kbps, AAC <192kbps, etc.),
    /// the default MediaCodecAudioRenderer (hardware decoder) is used instead
    /// of the FFmpeg software decoder to reduce CPU usage / battery drain.
    /// Default is true (FFmpeg enabled).
    @Volatile
    private var useFfmpeg = true

    /// When true, the AAudio AudioSink will skip digital volume gain
    /// to preserve bit-perfect PCM output. Requires exclusive mode.
    @Volatile
    private var bitPerfectMode = false

    // USB DAC bypass
    private var usbBypassEnabled = false
    private var isRoutingToUsbDac = false
    private var audioManager: AudioManager? = null
    private val usbAudioDeviceList = mutableListOf<AudioDeviceInfo>()

    // PreferredMixerAttributes (Android 14+ API for bit-perfect USB audio)
    private var lastRoutedDevice: AudioDeviceInfo? = null
    @Volatile
    private var mixerAttributesApplied = false

    @Volatile
    private var usbCallbackRegistered = false

    // AudioDeviceCallback for USB hotplug detection
    private val usbDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
            val usbDevices = addedDevices.filter {
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_DOCK
            }
            if (usbDevices.isNotEmpty()) {
                usbAudioDeviceList.addAll(usbDevices)
                channel?.invokeMethod("onUsbDevicesChanged", mapOf(
                    "devices" to serializeUsbDevices()
                ))
                // Auto-route if bypass is enabled and no current routing
                if (usbBypassEnabled && !isRoutingToUsbDac) {
                    routeToUsbDevice(usbDevices.first())
                }
            }
            // Fire general output device change for ALL audio device changes
            // (headphones, Bluetooth, USB, speaker changes, etc.)
            channel?.invokeMethod("onOutputDeviceChanged", mapOf(
                "activeDeviceType" to getActiveOutputDeviceType()
            ))
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
            val wasRouting = isRoutingToUsbDac
            usbAudioDeviceList.removeAll(removedDevices.toList())
            if (wasRouting) {
                isRoutingToUsbDac = false
                // Audio will fall back to system default automatically
            }
            channel?.invokeMethod("onUsbDevicesChanged", mapOf(
                "devices" to serializeUsbDevices()
            ))
            // Fire general output device change for ALL audio device changes
            channel?.invokeMethod("onOutputDeviceChanged", mapOf(
                "activeDeviceType" to getActiveOutputDeviceType()
            ))
        }
    }

    /**
     * Determine the current best output audio device type.
     * Priority: USB > Wired Headphones > Bluetooth > Built-in Speaker
     */
    private fun getActiveOutputDeviceType(): String {
        ensureAudioManager()
        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS) ?: return "unknown"

        // Priority order: USB > Wired > Bluetooth > Built-in
        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_DOCK -> {
                    if (usbBypassEnabled && isRoutingToUsbDac) return "usb_dac"
                    return "usb_detected"
                }
            }
        }
        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> return "wired_headphones"
            }
        }
        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> return "bluetooth"
            }
        }
        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> return "builtin"
            }
        }
        return "unknown"
    }

    /**
     * Set whether to use libusb AudioSink for direct USB DAC output.
     * When enabled, ExoPlayer will be recreated with [LibusbAudioSink]
     * which routes decoded PCM audio directly to the USB DAC via libusb,
     * bypassing the Android audio mixer entirely for true bit-perfect output.
     *
     * Has priority over [setUseAaudioSink] — if both are enabled, libusb wins.
     * Only takes effect on the NEXT ExoPlayer creation (next play() call).
     */
    fun setUseLibusbSink(enabled: Boolean) {
        if (useLibusbSink == enabled) return
        useLibusbSink = enabled
        // Force player recreation on next play() call
        releasePlayer()
        android.util.Log.i("HiResAudio", "Libusb AudioSink ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Set whether to use AAudio exclusive AudioSink.
     * When enabled, ExoPlayer will be recreated with a custom AudioSink
     * that routes decoded PCM audio to the AAudio exclusive stream.
     *
     * Only takes effect when [useLibusbSink] is false (libusb has priority).
     */
    fun setUseAaudioSink(enabled: Boolean) {
        if (useAaudioSink == enabled) return
        useAaudioSink = enabled
        // Force player recreation on next play() call
        releasePlayer()
        android.util.Log.i("HiResAudio", "AAudio AudioSink ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Enable or disable bit-perfect mode in the AAudio AudioSink.
     * When enabled, the AudioSink skips ALL digital volume gain on PCM data,
     * ensuring the audio output is bit-identical to the source file.
     * NOTE: Only takes effect on the NEXT ExoPlayer creation (next play() call).
     */
    /**
     * Set whether to use the FFmpeg software decoder.
     *
     * When false, ExoPlayer uses the default MediaCodecAudioRenderer (hardware)
     * for supported formats, which uses dedicated DSP blocks and saves CPU/battery.
     * When true, FfmpegAudioRenderer is prepended to the renderer list.
     *
     * Only takes effect on the NEXT ExoPlayer creation (next play() call).
     */
    fun setUseFfmpeg(enabled: Boolean) {
        if (useFfmpeg == enabled) return
        useFfmpeg = enabled
        releasePlayer()
        android.util.Log.i("HiResAudio", "FFmpeg decoder ${if (enabled) "enabled" else "disabled"}")
    }

    fun setBitPerfectMode(enabled: Boolean) {
        if (bitPerfectMode == enabled) return
        bitPerfectMode = enabled
        android.util.Log.i("HiResAudio", "Bit-perfect mode ${if (enabled) "enabled" else "disabled"}")
    }

    @OptIn(UnstableApi::class)
    private fun getOrCreatePlayer(): ExoPlayer {
        if (exoPlayer == null) {
            val audioAttributes = androidx.media3.common.AudioAttributes.Builder()
                .setUsage(androidx.media3.common.C.USAGE_MEDIA)
                .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
                .build()

            // ── RenderersFactory: prepend FfmpegAudioRenderer for ALAC FFmpeg decoding ──
            // Approach 1: Enable ServiceLoader-based extension discovery (EXTENSION_RENDERER_MODE_PREFER)
            //   DefaultRenderersFactory uses ServiceLoader to find Renderer implementations
            //   via META-INF/services/androidx.media3.exoplayer.Renderer. We registered
            //   FfmpegAudioRenderer there so it gets auto-discovered.
            // Approach 2: Wrap DefaultRenderersFactory via RenderersFactory SAM to explicitly
            //   prepend FfmpegAudioRenderer at position 0 in the renderers array.
            // ──────────────────────────────────────────────────────────────────────────────
            // ── AudioSink selection ──
            // Log native libusb driver state at sink-selection time
            // (getCurrentDriverPtr() internally logs [LIBUSB] driverConnected/ready/streamingCapable)
            UsbDacPlugin.getCurrentDriverPtr()
            android.util.Log.i("HiResAudio",
                "[AUDIO-SINK] Selecting AudioSink: " +
                "useLibusbSink=$useLibusbSink, useAaudioSink=$useAaudioSink")
            android.util.Log.i("HiResAudio",
                "[AUDIO-SINK] Priority: libusb > AAudio > Default. " +
                "Selected: ${if (useLibusbSink) "LIBUSB (LibusbAudioSink)" else if (useAaudioSink) "AAUDIO (AaudioAudioSink)" else "DEFAULT (DefaultAudioSink)"}")

            val baseFactory: DefaultRenderersFactory = when {
                // Priority 1: libusb USB DAC direct (true bit-perfect, all Android versions with USB OTG)
                useLibusbSink -> {
                    android.util.Log.i("USBPCM", "CREATING_EXOPLAYER_WITH_LIBUSB_SINK")
                    android.util.Log.i("USBPCM", "BUILD_AUDIO_SINK_RETURNING_LIBUSB")
                    android.util.Log.i("USBPCM", "AudioSink class=LibusbAudioSink")
                    android.util.Log.i("HiResAudio", "[AUDIO-SINK] CREATING_EXOPLAYER_WITH_LIBUSB_SINK")
                    android.util.Log.i("HiResAudio", "[AUDIO-SINK] >>> Creating ExoPlayer with LibusbAudioSink (bit-perfect USB DAC path)")
                    android.util.Log.i("HiResAudio", "Creating ExoPlayer with LibusbAudioSink + FFmpeg ALAC")
                    val libusbSinkInstance = LibusbAudioSink()
                    android.util.Log.i("AUDIO-SINK", "BUILD_AUDIO_SINK_RETURNING_LIBUSB instance=${libusbSinkInstance.javaClass.name}")
                    android.util.Log.i("AUDIO-SINK", "audioSink.javaClass.name=${libusbSinkInstance.javaClass.name}")

                    object : DefaultRenderersFactory(context) {
                        override fun buildAudioSink(
                            ctx: Context,
                            enableFloatOutput: Boolean,
                            enableAudioTrackPlaybackParams: Boolean
                        ): AudioSink? {
                            android.util.Log.i("AUDIO-SINK", "BUILD_AUDIO_SINK_RETURNING_LIBUSB instance=${libusbSinkInstance.javaClass.name}")
                            return libusbSinkInstance
                        }
                    }
                }
                // Priority 2: AAudio exclusive AudioSink (mixer bypass, flagship devices)
                useAaudioSink -> {
                    android.util.Log.i("HiResAudio", "[AUDIO-SINK] >>> Creating ExoPlayer with AaudioAudioSink (AAudio exclusive/shared path)")
                    android.util.Log.i("HiResAudio", "Creating ExoPlayer with AAudio AudioSink + FFmpeg ALAC")
                    val aaudioSinkInstance = AaudioAudioSink({ sr, ch, bits, deviceId ->
                        val ptr = ExclusiveAudioPlugin.nativeCreatePlayerStatic()
                        if (ptr != 0L) {
                            val inited = ExclusiveAudioPlugin.nativeInitPlayerStatic(ptr, sr, ch, bits, deviceId)
                            if (!inited) {
                                ExclusiveAudioPlugin.nativeDestroyPlayerStatic(ptr)
                                0L
                            } else ptr
                        } else 0L
                    },
                    /* onExclusiveStatusChanged */ { isExclusive ->
                        val status = mapOf(
                            "enabled" to useAaudioSink,
                            "volumeLocked" to false,
                            "aaudioAvailable" to true,
                            "aaudioActive" to true,
                            "aaudioExclusive" to isExclusive,
                            "mixerBypassed" to isExclusive,
                            "aaudioSampleRate" to 0,
                            "aaudioLatencyMs" to 0.0,
                            "currentVolume" to 0,
                            "maxVolume" to 0,
                            "androidSdk" to android.os.Build.VERSION.SDK_INT
                        )
                        android.util.Log.i("HiResAudio", "[THREAD] currentThread=${Thread.currentThread().name} — onExclusiveStatusChanged")
                        android.util.Log.i("HiResAudio", "[THREAD] invoking Flutter channel 'onExclusiveModeChanged'")
                        // This callback is invoked from ExoPlayer's playback thread,
                        // but MethodChannel.invokeMethod() requires the main thread.
                        // Post to main thread handler to avoid @UiThread violation.
                        Handler(Looper.getMainLooper()).post {
                            android.util.Log.i("HiResAudio", "[THREAD] switched to main thread — sending 'onExclusiveModeChanged'")
                            channel?.invokeMethod("onExclusiveModeChanged", status)
                        }
                        android.util.Log.i("HiResAudio", "Playback stream exclusive status: $isExclusive")
                    },
                    /* bitPerfectMode */ bitPerfectMode)

object : DefaultRenderersFactory(context) {
                         override fun buildAudioSink(
                             ctx: Context,
                             enableFloatOutput: Boolean,
                             enableAudioTrackPlaybackParams: Boolean
                         ): AudioSink? {
                             android.util.Log.i("AUDIO-SINK", "BUILD_AUDIO_SINK_RETURNING_AAUDIO instance=${aaudioSinkInstance.javaClass.name}")
                             return aaudioSinkInstance
                         }
                     }
                }
                // Priority 3: Default AudioSink (standard Android audio)
                else -> {
                    android.util.Log.i("HiResAudio", "[AUDIO-SINK] >>> Creating ExoPlayer with DefaultAudioSink (standard Android AudioTrack)")
                    android.util.Log.i("HiResAudio", "Creating ExoPlayer with FFmpeg ALAC")
                    object : DefaultRenderersFactory(context) {
                        override fun buildAudioSink(
                            ctx: Context,
                            enableFloatOutput: Boolean,
                            enableAudioTrackPlaybackParams: Boolean
                        ): AudioSink? {
                            android.util.Log.i("AUDIO-SINK", "BUILD_AUDIO_SINK_RETURNING_DEFAULT (DefaultAudioSink)")
                            return null // Let the base factory create DefaultAudioSink
                        }
                    }
                }
            }

            // Conditionally enable FFmpeg extension renderer discovery.
            // When useFfmpeg is true: PREFER mode → FFmpeg before MediaCodec.
            // When useFfmpeg is false: OFF mode → only built-in decoders (MediaCodec).
            // This saves CPU/battery for low-bitrate lossy formats (MP3 <256kbps, etc.)
            // that don't benefit from FFmpeg software decoding.
            if (useFfmpeg) {
                baseFactory.setExtensionRendererMode(
                    DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
                )
            } else {
                baseFactory.setExtensionRendererMode(
                    DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF
                )
            }

            // Wrap base factory, optionally prepending FfmpegAudioRenderer.
            // When useFfmpeg is false, NO FFmpeg renderer is added — ExoPlayer
            // falls back to the default MediaCodecAudioRenderer (hardware decoder).
            val renderersFactory = RenderersFactory { handler, _, audioListener, _, _ ->
                val baseRenderers = baseFactory.createRenderers(
                    handler,
                    object : VideoRendererEventListener {},
                    audioListener,
                    object : TextOutput {
                        override fun onCues(cueGroup: CueGroup) {}
                    },
                    object : MetadataOutput {
                        override fun onMetadata(metadata: Metadata) {}
                    }
                )
                if (useFfmpeg) {
                    android.util.Log.i("HiResAudio", "RenderersFactory: prepending FfmpegAudioRenderer")
                    for ((i, r) in baseRenderers.withIndex()) {
                        android.util.Log.i("HiResAudio", "  Renderer[$i] = ${r::class.java.name}")
                    }
                    val ffmpeg = FfmpegAudioRenderer(handler, audioListener)
                    arrayOf<Renderer>(ffmpeg) + baseRenderers
                } else {
                    android.util.Log.i("HiResAudio", "RenderersFactory: FFmpeg disabled, using hardware decoders only")
                    baseRenderers
                }
            }

            exoPlayer = ExoPlayer.Builder(context, renderersFactory)
                .setAudioAttributes(audioAttributes, true)
                .setHandleAudioBecomingNoisy(true)
                .build()

            exoPlayer?.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    this@HiResAudioPlugin.isPlaying = isPlaying
                    android.util.Log.i("HiResAudio", "[THREAD] currentThread=${Thread.currentThread().name} — onIsPlayingChanged")
                    android.util.Log.i("HiResAudio", "[THREAD] invoking Flutter channel 'onPlaybackStateChanged'")
                    // Player.Listener callbacks run on ExoPlayer's playback thread.
                    // MethodChannel requires the main thread — post to main thread.
                    Handler(Looper.getMainLooper()).post {
                        android.util.Log.i("HiResAudio", "[THREAD] switched to main thread — sending 'onPlaybackStateChanged'")
                        channel?.invokeMethod("onPlaybackStateChanged", mapOf(
                            "isPlaying" to isPlaying
                        ))
                    }
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    android.util.Log.i("HiResAudio", "[THREAD] currentThread=${Thread.currentThread().name} — onPlaybackStateChanged=$playbackState")
                    when (playbackState) {
                        Player.STATE_READY -> {
                            val audioFormat = exoPlayer?.audioFormat
                            if (audioFormat != null) {
                                currentSampleRate = audioFormat.sampleRate
                                currentBitDepth = when (audioFormat.pcmEncoding) {
                                    androidx.media3.common.C.ENCODING_PCM_16BIT -> 16
                                    androidx.media3.common.C.ENCODING_PCM_24BIT -> 24
                                    androidx.media3.common.C.ENCODING_PCM_32BIT -> 32
                                    androidx.media3.common.C.ENCODING_PCM_FLOAT -> 32
                                    else -> 0
                                }
                                currentChannels = audioFormat.channelCount
                            }
                            android.util.Log.i("HiResAudio", "[THREAD] invoking Flutter channel 'onFormatInfo'")
                            // Player.Listener callbacks run on ExoPlayer's playback thread.
                            // MethodChannel requires the main thread — post to main thread.
                            Handler(Looper.getMainLooper()).post {
                                android.util.Log.i("HiResAudio", "[THREAD] switched to main thread — sending 'onFormatInfo'")
                                channel?.invokeMethod("onFormatInfo", mapOf(
                                    "sampleRate" to currentSampleRate,
                                    "bitDepth" to currentBitDepth,
                                    "channels" to currentChannels
                                ))
                            }
                        }
                        Player.STATE_ENDED -> {
                            isPlaying = false
                            android.util.Log.i("HiResAudio", "[THREAD] invoking Flutter channels 'onPlaybackStateChanged' + 'onTrackEnded'")
                            // Player.Listener callbacks run on ExoPlayer's playback thread.
                            // MethodChannel requires the main thread — post to main thread.
                            Handler(Looper.getMainLooper()).post {
                                android.util.Log.i("HiResAudio", "[THREAD] switched to main thread — sending 'onPlaybackStateChanged' + 'onTrackEnded'")
                                channel?.invokeMethod("onPlaybackStateChanged", mapOf(
                                    "isPlaying" to false
                                ))
                                // Push dedicated track-ended event — this is the ONLY reliable
                                // way to detect track completion. onIsPlayingChanged(false) can
                                // fire for transient reasons (audio focus, format change) and
                                // should NOT be used for completion detection to avoid false
                                // positives that destroy the AudioTrack mid-playback.
                                channel?.invokeMethod("onTrackEnded", true)
                            }
                        }
                        Player.STATE_BUFFERING -> {
                            android.util.Log.i("HiResAudio", "[THREAD] invoking Flutter channel 'onBuffering'")
                            // Player.Listener callbacks run on ExoPlayer's playback thread.
                            // MethodChannel requires the main thread — post to main thread.
                            Handler(Looper.getMainLooper()).post {
                                android.util.Log.i("HiResAudio", "[THREAD] switched to main thread — sending 'onBuffering'")
                                channel?.invokeMethod("onBuffering", mapOf(
                                    "buffering" to true
                                ))
                            }
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    android.util.Log.i("HiResAudio", "[THREAD] currentThread=${Thread.currentThread().name} — onPlayerError")
                    android.util.Log.i("HiResAudio", "[THREAD] invoking Flutter channel 'onError'")
                    // Player.Listener callbacks run on ExoPlayer's playback thread.
                    // MethodChannel requires the main thread — post to main thread.
                    Handler(Looper.getMainLooper()).post {
                        android.util.Log.i("HiResAudio", "[THREAD] switched to main thread — sending 'onError'")
                        channel?.invokeMethod("onError", mapOf(
                            "message" to error.message,
                            "errorCode" to error.errorCodeName
                        ))
                    }
                }
            })
        }
        return exoPlayer!!
=======
    init {
        positionPusher.attachPlayer { playerManager.exoPlayer }
>>>>>>> 96f3b38
    }

    fun attachChannel(methodChannel: MethodChannel) {
        this.channel = methodChannel
        usbRouter.attach(methodChannel, playerManager)
        // Set up player callbacks once on attach (not on every play() call)
        setupPlayerCallbacks()
    }

    // ── Public API called from MainActivity ──

    fun autoRouteToUsbDac(device: android.hardware.usb.UsbDevice) {
        usbRouter.autoRouteToUsbDac(device)
    }

    fun onUsbDeviceDetached() {
        usbRouter.onUsbDeviceDetached()
    }

    fun setUseAaudioSink(enabled: Boolean) {
        playerManager.setUseAaudioSink(enabled)
    }

    fun setBitPerfectMode(enabled: Boolean) {
        playerManager.updateBitPerfectMode(enabled)
    }

    // ── Player event callbacks — forward to MethodChannel ──

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

                if (url.isEmpty()) {
                    result.error("INVALID_ARGS", "url is required", null)
                    return
                }

                playerManager.currentSampleRate = sampleRate
                playerManager.currentBitDepth = bitDepth
                lastPlayUrl = url
                positionPusher.resetDurationCache()

                try {
                    setupPlayerCallbacks()
                    playerManager.releasePlayer()
                    lastPlayPositionMs = 0L
                    val player = playerManager.getOrCreatePlayer()

                    val mediaItem = MediaItem.Builder()
                        .setUri(Uri.parse(url))
                        .build()

                    player.setMediaItem(mediaItem)
                    if (sampleRate > 0 && playerManager.useAaudioSink) {
                        android.util.Log.i("HiResAudio", "Target sample rate: ${sampleRate}Hz")
                    }
                    player.prepare()
                    player.play()

                    positionPusher.start()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("PLAY_ERROR", "Failed to play: ${e.message}", null)
                }
            }
            "pause" -> {
                android.util.Log.i("HiResAudio", "→ Dart pause() called (exoPlayer=${playerManager.exoPlayer != null})")
                positionPusher.stop()
                playerManager.exoPlayer?.pause()
                result.success(true)
            }
            "resume" -> {
                android.util.Log.i("HiResAudio", "→ Dart resume() called (exoPlayer=${playerManager.exoPlayer != null}, lastPlayUrl=${lastPlayUrl != null})")
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
                            android.util.Log.i("HiResAudio", "Resuming from ${lastPlayPositionMs}ms")
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
            // ── USB DAC Bypass methods ──
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
            // ── PreferredMixerAttributes methods (Android 14+) ──
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
            // ── Hardware Sample Rate methods ──
            "getOutputSampleRate" -> {
                val nativeRate = android.media.AudioTrack.getNativeOutputSampleRate(
                    android.media.AudioManager.STREAM_MUSIC
                )
                result.success(nativeRate)
            }
            "getHardwareSampleRate" -> {
                // Query the active output device for its native sample rate
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
            "setUseLibusbSink" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                if (playerManager.useDecentSink == enabled) {
                    result.success(true)
                    return
                }
                playerManager.useDecentSink = enabled
                playerManager.releasePlayer()
                android.util.Log.i("HiResAudio", "Decent-player UsbAudioSink ${if (enabled) "enabled" else "disabled"}")
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
<<<<<<< HEAD
        unregisterUsbCallback()
        clearUsbRouting()
        releasePlayer()
    }

    private fun releasePlayer() {
        android.util.Log.i("HiResAudio", "[PLAYER-LIFECYCLE] releasePlayer() called — exoPlayer=$exoPlayer, isPlaying=$isPlaying")
        stopPositionPush()
        try {
            exoPlayer?.stop()
            android.util.Log.i("HiResAudio", "[PLAYER-LIFECYCLE] exoPlayer?.stop() completed")
            exoPlayer?.release()
            android.util.Log.i("HiResAudio", "[PLAYER-LIFECYCLE] exoPlayer?.release() completed")
        } catch (e: Exception) {
            android.util.Log.w("HiResAudio", "[PLAYER-LIFECYCLE] releasePlayer exception: ${e.message}")
        }
        exoPlayer = null
        isPlaying = false
        android.util.Log.i("HiResAudio", "[PLAYER-LIFECYCLE] releasePlayer() complete — exoPlayer=null")
=======
        positionPusher.stop()
        usbRouter.cleanup()
        playerManager.releasePlayer()
>>>>>>> 96f3b38
    }
}
