package com.meteor.kikoeruflutter

import android.content.Context
import android.hardware.usb.UsbManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.Metadata
import androidx.media3.common.text.CueGroup
import androidx.media3.decoder.ffmpeg.FfmpegAudioRenderer
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.metadata.MetadataOutput
import androidx.media3.exoplayer.text.TextOutput
import androidx.media3.exoplayer.video.VideoRendererEventListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android native Hi-Res Audio plugin.
 *
 * Uses AndroidX Media3 (ExoPlayer) for high-resolution audio playback
 * with custom AudioAttributes configuration for improved audio quality.
 * Supports USB DAC bypass via [AudioManager] device routing.
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

    private var exoPlayer: ExoPlayer? = null
    private var isPlaying = false
    private var currentSampleRate: Int = 0
    private var currentBitDepth: Int = 0
    private var currentChannels: Int = 0
    private var channel: MethodChannel? = null

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

    // AAudio exclusive AudioSink mode
    private var useAaudioSink = false

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
     * Set whether to use AAudio exclusive AudioSink.
     * When enabled, ExoPlayer will be recreated with a custom AudioSink
     * that routes decoded PCM audio to the AAudio exclusive stream.
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
            val baseFactory: DefaultRenderersFactory = if (useAaudioSink) {
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
                    channel?.invokeMethod("onExclusiveModeChanged", status)
                    android.util.Log.i("HiResAudio", "Playback stream exclusive status: $isExclusive")
                },
                /* bitPerfectMode */ bitPerfectMode)

                object : DefaultRenderersFactory(context) {
                    override fun buildAudioSink(
                        ctx: Context,
                        enableFloatOutput: Boolean,
                        enableAudioTrackPlaybackParams: Boolean
                    ): AudioSink? {
                        return aaudioSinkInstance
                    }
                }
            } else {
                android.util.Log.i("HiResAudio", "Creating ExoPlayer with FFmpeg ALAC")
                DefaultRenderersFactory(context)
            }

            // Enable ServiceLoader-based extension renderer discovery
            // This finds FfmpegAudioRenderer via META-INF/services/ and adds it
            // to the renderers list in PREFER mode (before MediaCodecAudioRenderer).
            baseFactory.setExtensionRendererMode(
                DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
            )

            // Wrap base factory to ALSO prepend FfmpegAudioRenderer explicitly.
            // This provides redundancy: if ServiceLoader fails, the explicit prepend
            // still works. If ServiceLoader succeeds, FfmpegAudioRenderer appears twice
            // but ExoPlayer picks the first one at index 0.
            val renderersFactory = RenderersFactory { handler, _, audioListener, _, _ ->
                android.util.Log.i("HiResAudio", "RenderersFactory.createRenderers() called — prepending FfmpegAudioRenderer")
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
                android.util.Log.i("HiResAudio", "Base factory returned ${baseRenderers.size} renderers")
                for ((i, r) in baseRenderers.withIndex()) {
                    android.util.Log.i("HiResAudio", "  Renderer[$i] = ${r::class.java.name}")
                }
                val ffmpeg = FfmpegAudioRenderer(handler, audioListener)
                android.util.Log.i("HiResAudio", "FfmpegAudioRenderer created, prepending at position 0")
                android.util.Log.i("HiResAudio", "FfmpegLibrary.isAvailable() = ${FfmpegAudioRenderer::class.java.name}: check supportsFormat")
                arrayOf<Renderer>(ffmpeg) + baseRenderers
            }

            exoPlayer = ExoPlayer.Builder(context, renderersFactory)
                .setAudioAttributes(audioAttributes, true)
                .setHandleAudioBecomingNoisy(true)
                .build()

            exoPlayer?.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    this@HiResAudioPlugin.isPlaying = isPlaying
                    channel?.invokeMethod("onPlaybackStateChanged", mapOf(
                        "isPlaying" to isPlaying
                    ))
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
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
                            channel?.invokeMethod("onFormatInfo", mapOf(
                                "sampleRate" to currentSampleRate,
                                "bitDepth" to currentBitDepth,
                                "channels" to currentChannels
                            ))
                        }
                        Player.STATE_ENDED -> {
                            isPlaying = false
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
                        Player.STATE_BUFFERING -> {
                            channel?.invokeMethod("onBuffering", mapOf(
                                "buffering" to true
                            ))
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    channel?.invokeMethod("onError", mapOf(
                        "message" to error.message,
                        "errorCode" to error.errorCodeName
                    ))
                }
            })
        }
        return exoPlayer!!
    }

    fun attachChannel(methodChannel: MethodChannel) {
        this.channel = methodChannel
        // Register audio device callback eagerly so output device detection
        // (headphones, USB DAC, Bluetooth) works from app start.
        registerUsbCallback()
        // Emit initial device state so activeOutputDeviceProvider has a value
        // immediately instead of showing 'loading'.
        channel?.invokeMethod("onOutputDeviceChanged", mapOf(
            "activeDeviceType" to getActiveOutputDeviceType()
        ))
    }

    /**
     * Ensure audioManager is initialized.
     */
    private fun ensureAudioManager() {
        if (audioManager == null) {
            audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        }
    }

    /**
     * Register the USB audio device callback.
     * Safe to call multiple times — `AudioManager.registerAudioDeviceCallback`
     * does not throw on duplicate registration, and the try/catch handles any edge cases.
     */
    private fun registerUsbCallback() {
        if (usbCallbackRegistered) {
            android.util.Log.v("HiResAudio", "USB callback already registered, skipping")
            return
        }
        ensureAudioManager()
        try {
            audioManager?.registerAudioDeviceCallback(usbDeviceCallback, null)
            usbCallbackRegistered = true
            android.util.Log.i("HiResAudio", "USB device callback registered (hotplug detection active)")
        } catch (_: Exception) {}
    }

    /**
     * Unregister the USB audio device callback.
     */
    private fun unregisterUsbCallback() {
        if (!usbCallbackRegistered) return
        try {
            audioManager?.unregisterAudioDeviceCallback(usbDeviceCallback)
            usbCallbackRegistered = false
            android.util.Log.i("HiResAudio", "USB device callback unregistered")
        } catch (_: Exception) {}
    }

    /**
     * Serialise the currently detected USB audio devices to a list of maps.
     */
    private fun serializeUsbDevices(): List<Map<String, Any?>> {
        return usbAudioDeviceList.map { device ->
            mapOf(
                "id" to device.id,
                "productName" to (device.productName ?: "USB Audio Device"),
                "address" to device.address,
                "type" to deviceTypeToString(device.type),
                "channelCounts" to (device.channelCounts?.maxOrNull() ?: 0),
                "sampleRates" to (device.sampleRates?.maxOrNull() ?: 0),
            )
        }
    }

    private fun deviceTypeToString(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_USB_DEVICE -> "usb_device"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "usb_headset"
            AudioDeviceInfo.TYPE_DOCK -> "dock"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
            else -> "other"
        }
    }

    /**
     * Apply PreferredMixerAttributes to request bit-perfect USB audio output.
     * Uses Android 14+ AudioMixerAttributes API with MIXER_BEHAVIOR_BIT_PERFECT.
     * Returns true if the system accepted the request.
     */
    private fun applyPreferredMixerAttributes(device: AudioDeviceInfo, sampleRate: Int, bitDepth: Int): Boolean {
        if (Build.VERSION.SDK_INT < 34) {
            android.util.Log.i("HiResAudio", "PreferredMixerAttributes requires API 34+, current: ${Build.VERSION.SDK_INT}")
            return false
        }

        return try {
            val encoding = when {
                bitDepth >= 32 -> android.media.AudioFormat.ENCODING_PCM_32BIT
                bitDepth >= 24 -> android.media.AudioFormat.ENCODING_PCM_24BIT_PACKED
                else -> android.media.AudioFormat.ENCODING_PCM_16BIT
            }

            val audioFormat = android.media.AudioFormat.Builder()
                .setEncoding(encoding)
                .setSampleRate(if (sampleRate > 0) sampleRate else 48000)
                .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_STEREO)
                .build()

            // Builder constructor takes AudioFormat, no separate setSchema()
            val mixerAttrs = android.media.AudioMixerAttributes.Builder(audioFormat)
                .setMixerBehavior(android.media.AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT)
                .build()

            val attrs = android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()

            // Returns true on success, false on failure
            val result = audioManager?.setPreferredMixerAttributes(attrs, device, mixerAttrs)
            val success = result == true
            mixerAttributesApplied = success
            if (success) {
                android.util.Log.i("HiResAudio",
                    "PreferredMixerAttributes applied: ${bitDepth}bit ${sampleRate}Hz BIT_PERFECT on ${device.productName}")
            } else {
                android.util.Log.w("HiResAudio",
                    "PreferredMixerAttributes rejected by system (code: $result)")
            }
            success
        } catch (e: Exception) {
            android.util.Log.w("HiResAudio", "PreferredMixerAttributes error: ${e.message}")
            false
        }
    }

    /**
     * Clear PreferredMixerAttributes on the previously routed USB device.
     * Sets the mixer to default behavior (non-bit-perfect) since the API
     * does not accept null for clearing.
     */
    private fun clearPreferredMixerAttributes(device: AudioDeviceInfo?) {
        if (Build.VERSION.SDK_INT < 34 || device == null || !mixerAttributesApplied) return
        try {
            val audioFormat = android.media.AudioFormat.Builder()
                .setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(48000)
                .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_STEREO)
                .build()

            val defaultAttrs = android.media.AudioMixerAttributes.Builder(audioFormat)
                .setMixerBehavior(android.media.AudioMixerAttributes.MIXER_BEHAVIOR_DEFAULT)
                .build()

            val attrs = android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            audioManager?.setPreferredMixerAttributes(attrs, device, defaultAttrs)
            mixerAttributesApplied = false
            android.util.Log.i("HiResAudio", "PreferredMixerAttributes cleared (set to default)")
        } catch (e: Exception) {
            android.util.Log.w("HiResAudio", "Clear PreferredMixerAttributes error: ${e.message}")
        }
    }

    /**
     * Route the ExoPlayer audio output to the specified USB audio device.
     * Also attempts to apply PreferredMixerAttributes for bit-perfect output.
     */
    private fun routeToUsbDevice(device: AudioDeviceInfo) {
        try {
            exoPlayer?.setPreferredAudioDevice(device)
            isRoutingToUsbDac = true
            lastRoutedDevice = device

            // Try to apply PreferredMixerAttributes (API 34+)
            val mixerSuccess = applyPreferredMixerAttributes(device, currentSampleRate, currentBitDepth)

            channel?.invokeMethod("onUsbRoutingChanged", mapOf(
                "routed" to true,
                "deviceName" to (device.productName ?: "USB DAC"),
                "mixerAttributesApplied" to mixerSuccess
            ))
        } catch (e: Exception) {
            channel?.invokeMethod("onError", mapOf(
                "message" to "Failed to route to USB DAC: ${e.message}"
            ))
        }
    }

    /**
     * Clear USB audio device routing (revert to system default).
     * Also clears PreferredMixerAttributes.
     */
    private fun clearUsbRouting() {
        clearPreferredMixerAttributes(lastRoutedDevice)
        lastRoutedDevice = null

        try {
            exoPlayer?.setPreferredAudioDevice(null)
        } catch (_: Exception) {}
        isRoutingToUsbDac = false
        channel?.invokeMethod("onUsbRoutingChanged", mapOf(
            "routed" to false,
            "deviceName" to "",
            "mixerAttributesApplied" to false
        ))
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> {
                result.success(true)
            }
            "play" -> {
                val url = call.argument<String>("url") ?: ""
                val sampleRate = call.argument<Int>("sampleRate") ?: 0
                val bitDepth = call.argument<Int>("bitDepth") ?: 0

                if (url.isEmpty()) {
                    result.error("INVALID_ARGS", "url is required", null)
                    return
                }

                currentSampleRate = sampleRate
                currentBitDepth = bitDepth
                lastPushedDurationMs = -1L // Reset for new track

                try {
                    val player = getOrCreatePlayer()

                    val mediaItem = MediaItem.Builder()
                        .setUri(Uri.parse(url))
                        .build()

                    player.setMediaItem(mediaItem)
                    // Pass sample rate hint to player for native rate detection
                    if (sampleRate > 0 && useAaudioSink) {
                        android.util.Log.i("HiResAudio", "Target sample rate: ${sampleRate}Hz")
                    }
                    player.prepare()
                    player.play()

                    // Start native position push at 50ms intervals
                    startPositionPush()

                    result.success(true)
                } catch (e: Exception) {
                    result.error("PLAY_ERROR", "Failed to play: ${e.message}", null)
                }
            }
            "pause" -> {
                stopPositionPush()
                exoPlayer?.pause()
                result.success(true)
            }
            "resume" -> {
                exoPlayer?.play()
                startPositionPush()
                result.success(true)
            }
            "stop" -> {
                stopPositionPush()
                exoPlayer?.stop()
                exoPlayer?.seekTo(0)
                isPlaying = false
                result.success(true)
            }
            "seekTo" -> {
                val positionMs = call.argument<Int>("positionMs") ?: 0
                exoPlayer?.seekTo(positionMs.toLong())
                result.success(true)
            }
            "getPosition" -> {
                val positionMs = exoPlayer?.currentPosition?.toInt() ?: 0
                result.success(positionMs)
            }
            "getDuration" -> {
                val durationMs = exoPlayer?.duration?.toInt() ?: 0
                result.success(durationMs)
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume") ?: 1.0
                exoPlayer?.volume = volume.toFloat()
                result.success(true)
            }
            "setSampleRate" -> {
                val sampleRate = call.argument<Int>("sampleRate") ?: 0
                currentSampleRate = sampleRate
                result.success(true)
            }
            // ── USB DAC Bypass methods ──
            "getUsbAudioDevices" -> {
                // Pastikan audioManager sudah diinisialisasi
                ensureAudioManager()
                // Register USB callback eagerly so hotplug events are detected
                // even without USB bypass mode enabled.
                registerUsbCallback()
                // Refresh USB device list
                usbAudioDeviceList.clear()
                val allDevices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                if (allDevices != null) {
                    usbAudioDeviceList.addAll(allDevices.filter {
                        it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                        it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                        it.type == AudioDeviceInfo.TYPE_DOCK
                    })
                }
                result.success(serializeUsbDevices())
            }
            "setUsbBypassMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val deviceId = call.argument<Int>("deviceId")
                usbBypassEnabled = enabled
                if (enabled) {
                    registerUsbCallback()
                    if (deviceId != null && deviceId > 0) {
                        // Route to the specified device
                        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        val targetDevice = devices?.firstOrNull {
                            (it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                             it.type == AudioDeviceInfo.TYPE_USB_HEADSET) &&
                            it.id == deviceId
                        }
                        if (targetDevice != null) {
                            routeToUsbDevice(targetDevice)
                        } else {
                            // Specified device not found, try first available
                            val fallback = devices?.firstOrNull {
                                it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
                            }
                            if (fallback != null) routeToUsbDevice(fallback)
                        }
                    } else {
                        // No specific device, auto-route to first available
                        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        val usbDevice = devices?.firstOrNull {
                            it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                            it.type == AudioDeviceInfo.TYPE_USB_HEADSET
                        }
                        if (usbDevice != null) {
                            routeToUsbDevice(usbDevice)
                        }
                    }
                } else {
                    clearUsbRouting()
                    unregisterUsbCallback()
                }
                result.success(true)
            }
            "routeToUsbDevice" -> {
                val deviceId = call.argument<Int>("deviceId") ?: -1
                val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                val targetDevice = devices?.firstOrNull {
                    it.id == deviceId && (it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                            it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                            it.type == AudioDeviceInfo.TYPE_DOCK)
                }
                if (targetDevice != null) {
                    routeToUsbDevice(targetDevice)
                    result.success(true)
                } else {
                    result.error("DEVICE_NOT_FOUND", "USB device not found", null)
                }
            }
            "clearUsbRouting" -> {
                clearUsbRouting()
                result.success(true)
            }
            "isUsbRouted" -> {
                result.success(isRoutingToUsbDac)
            }
            // ── PreferredMixerAttributes methods (Android 14+) ──
            "setPreferredMixerAttributes" -> {
                ensureAudioManager()
                val deviceId = call.argument<Int>("deviceId") ?: -1
                val sampleRate = call.argument<Int>("sampleRate") ?: 0
                val bitDepth = call.argument<Int>("bitDepth") ?: 0

                val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                val device = devices?.firstOrNull { it.id == deviceId }
                if (device != null) {
                    val success = applyPreferredMixerAttributes(device, sampleRate, bitDepth)
                    result.success(mapOf(
                        "success" to success,
                        "apiSupported" to (Build.VERSION.SDK_INT >= 34)
                    ))
                } else {
                    result.error("DEVICE_NOT_FOUND", "USB device not found", null)
                }
            }
            "clearPreferredMixerAttributes" -> {
                clearPreferredMixerAttributes(lastRoutedDevice)
                result.success(true)
            }
            "getPreferredMixerAttributes" -> {
                if (Build.VERSION.SDK_INT >= 34 && lastRoutedDevice != null) {
                    try {
                        val attrs = android.media.AudioAttributes.Builder()
                            .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
                        val current = audioManager?.getPreferredMixerAttributes(attrs, lastRoutedDevice!!)
                        if (current != null) {
                            val audioFormat = current.format
                            result.success(mapOf(
                                "hasAttributes" to true,
                                "sampleRate" to (audioFormat?.sampleRate ?: 0),
                                "encoding" to (audioFormat?.encoding ?: 0),
                                "channelMask" to (audioFormat?.channelMask ?: 0),
                                "bitPerfect" to (current.mixerBehavior == android.media.AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT)
                            ))
                        } else {
                            result.success(mapOf("hasAttributes" to false))
                        }
                    } catch (e: Exception) {
                        result.success(mapOf("hasAttributes" to false, "error" to (e.message ?: "")))
                    }
                } else {
                    result.success(mapOf(
                        "hasAttributes" to false,
                        "apiSupported" to (Build.VERSION.SDK_INT >= 34)
                    ))
                }
            }
            // ── Hardware Sample Rate methods ──
            "getOutputSampleRate" -> {
                // Returns the native sample rate used by Android's AudioTrack for the current output device
                val nativeRate = android.media.AudioTrack.getNativeOutputSampleRate(
                    android.media.AudioManager.STREAM_MUSIC
                )
                result.success(nativeRate)
            }
            "getHardwareSampleRate" -> {
                // Queries the active output device for its native sample rate
                ensureAudioManager()
                var hardwareRate = 0
                val devices = audioManager?.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
                val activeDevice = devices?.firstOrNull { it.isSource == false }
                if (activeDevice != null) {
                    // sampleRates returns the supported rates; pick the first one as native
                    val rates = activeDevice.sampleRates
                    if (rates != null && rates.isNotEmpty()) {
                        // Use the highest supported rate as the device's native rate
                        hardwareRate = rates.maxOrNull() ?: 0
                    }
                }
                if (hardwareRate <= 0) {
                    // Fallback to AudioTrack native sample rate
                    hardwareRate = android.media.AudioTrack.getNativeOutputSampleRate(
                        android.media.AudioManager.STREAM_MUSIC
                    )
                }
                result.success(hardwareRate)
            }
            "setUseAaudioSink" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                setUseAaudioSink(enabled)
                result.success(true)
            }
            "setBitPerfectMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                setBitPerfectMode(enabled)
                result.success(true)
            }
            "getActiveOutputDeviceType" -> {
                result.success(getActiveOutputDeviceType())
            }
            "release" -> {
                releasePlayer()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Release the ExoPlayer instance.
     */
    fun cleanup() {
        unregisterUsbCallback()
        clearUsbRouting()
        releasePlayer()
    }

    private fun releasePlayer() {
        stopPositionPush()
        try {
            exoPlayer?.stop()
            exoPlayer?.release()
        } catch (_: Exception) {}
        exoPlayer = null
        isPlaying = false
    }
}
