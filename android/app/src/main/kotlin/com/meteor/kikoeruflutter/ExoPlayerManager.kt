package com.meteor.kikoeruflutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Metadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.decoder.ffmpeg.FfmpegAudioRenderer
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.metadata.MetadataOutput
import androidx.media3.exoplayer.text.TextOutput
import androidx.media3.exoplayer.video.VideoRendererEventListener
import com.decent.usbaudio.media3.UsbAudioSink
import com.decent.usbaudio.media3.UsbAudioSinkConfig
import io.flutter.plugin.common.MethodChannel

/**
 * Manages ExoPlayer lifecycle and renderers factory.
 *
 * Handles player creation (with UsbAudioSink, AAudio or default pipeline),
 * release, and event listening. Reports player state changes back via a
 * [MethodChannel] callback.
 */
class ExoPlayerManager(private val context: Context) {

    var exoPlayer: ExoPlayer? = null
        private set
    var isPlaying: Boolean = false
        private set
    var currentSampleRate: Int = 0
    var currentBitDepth: Int = 0
    var currentChannels: Int = 0

    // AAudio exclusive AudioSink mode
    var useAaudioSink: Boolean = false
        private set

    /// When true, the AAudio AudioSink will skip digital volume gain
    /// to preserve bit-perfect PCM output. Requires exclusive mode.
    @Volatile
    var bitPerfectMode: Boolean = false

    // ── decent-player: Bit-perfect USB DAC via UsbAudioSink ──
    var useDecentSink: Boolean = false
    var currentUsbSink: UsbAudioSink? = null
    @Volatile
    var libflacAvailable: Boolean = false

    /** Callback invoked by the Player.Listener on state changes. */
    var onFormatInfo: ((sampleRate: Int, bitDepth: Int, channels: Int) -> Unit)? = null
    var onPlaybackStateChanged: ((isPlaying: Boolean) -> Unit)? = null
    var onTrackEnded: (() -> Unit)? = null
    var onBuffering: ((buffering: Boolean) -> Unit)? = null
    var onPlayerError: ((message: String?, errorCode: String?) -> Unit)? = null
    /** Callback for AAudio exclusive mode status changes. The map contains
     *  the full status payload (enabled, volumeLocked, aaudioAvailable, etc.). */
    var onExclusiveStatusChanged: ((status: Map<String, Any?>) -> Unit)? = null

    /** Custom BroadcastReceiver for ACTION_AUDIO_BECOMING_NOISY.
     *  Unlike ExoPlayer's built-in handler which always pauses on any
     *  ACTION_AUDIO_BECOMING_NOISY broadcast, this receiver
     *  CONDITIONALLY ignores the broadcast when USB DAC (useDecentSink)
     *  or AAudio exclusive sink (useAaudioSink) is active.
     *
     *  Why: When the app goes to background on some Android devices,
     *  the system may temporarily re-evaluate USB audio routing and send
     *  a spurious ACTION_AUDIO_BECOMING_NOISY. With ExoPlayer's default
     *  handler, this causes an unwanted auto-pause. Our custom handler
     *  only pauses for genuine headphone/BT unplug events (when USB DAC
     *  and AAudio sink are NOT in use).
     */
    private var audioBecomingNoisyReceiver: BroadcastReceiver? = null

    init {
        // Detect libFLAC at runtime — decent-media3-decoder-flac provides this
        libflacAvailable = try {
            Class.forName("androidx.media3.decoder.flac.LibflacAudioRenderer")
            true
        } catch (_: ClassNotFoundException) { false }
    }

    /**
     * Set whether to use AAudio exclusive AudioSink.
     * When enabled, ExoPlayer will be recreated with a custom AudioSink
     * that routes decoded PCM audio to the AAudio exclusive stream.
     */
    fun setUseAaudioSink(enabled: Boolean) {
        if (useAaudioSink == enabled) return
        useAaudioSink = enabled
        releasePlayer()
        android.util.Log.i("HiResAudio", "AAudio AudioSink ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Enable or disable bit-perfect mode in the AAudio AudioSink.
     * When enabled, the AudioSink skips ALL digital volume gain on PCM data,
     * ensuring the audio output is bit-identical to the source file.
     * NOTE: Only takes effect on the NEXT ExoPlayer creation (next play() call).
     */
    fun updateBitPerfectMode(enabled: Boolean) {
        if (bitPerfectMode == enabled) return
        bitPerfectMode = enabled
        android.util.Log.i("HiResAudio", "Bit-perfect mode ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Enable or disable FFmpeg software decoder.
     * When enabled, FfmpegAudioRenderer is prepended to the renderer list.
     * When disabled, only hardware decoders are used (MediaCodec).
     * Only takes effect on the NEXT ExoPlayer creation.
     */
    fun setUseFfmpeg(enabled: Boolean) {
        // ExoPlayerManager always uses FFmpeg by default
        // This is kept for interface compatibility
        android.util.Log.i("HiResAudio", "FFmpeg decoder ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Enable or disable the decent-player UsbAudioSink for true bit-perfect
     * USB audio via usbdevfs direct access.
     */
    fun setUseLibusbSink(enabled: Boolean) {
        if (useDecentSink == enabled) return
        useDecentSink = enabled
        releasePlayer()
        android.util.Log.i("HiResAudio", "UsbAudioSink ${if (enabled) "enabled" else "disabled"}")
    }

    @OptIn(UnstableApi::class)
    fun getOrCreatePlayer(): ExoPlayer {
        if (exoPlayer == null) {
            val audioAttributes = androidx.media3.common.AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build()

            val baseFactory: DefaultRenderersFactory = when {
                // Priority 1: decent-player UsbAudioSink (bit-perfect via usbdevfs)
                useDecentSink -> {
                    android.util.Log.i("HiResAudio", "Creating ExoPlayer with UsbAudioSink + FFmpeg")

                    object : DefaultRenderersFactory(context) {
                        override fun buildAudioSink(
                            ctx: Context,
                            enableFloatOutput: Boolean,
                            enableAudioTrackPlaybackParams: Boolean
                        ): AudioSink? {
                            val config = UsbAudioSinkConfig(
                                bitPerfectEnabled = true,
                                forceRouteToSpeaker = true
                            )
                            val delegate = DefaultAudioSink.Builder(ctx)
                                .setAudioCapabilities(AudioCapabilities.getCapabilities(ctx))
                                .build()
                            return UsbAudioSink(delegate, ctx, config).also {
                                currentUsbSink = it
                                android.util.Log.i("HiResAudio", "UsbAudioSink created (delegate=${delegate::class.simpleName})")
                            }
                        }
                    }
                }
                // Priority 2: AAudio exclusive AudioSink
                useAaudioSink -> {
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
                        // Post to main thread — ExoPlayer calls configure() from background thread
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            onExclusiveStatusChanged?.invoke(status)
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
                            return aaudioSinkInstance
                        }
                    }
                }
                // Default: standard FFmpeg pipeline
                else -> {
                    android.util.Log.i("HiResAudio", "Creating ExoPlayer with FFmpeg ALAC")
                    DefaultRenderersFactory(context)
                }
            }

            // Enable ServiceLoader-based extension renderer discovery
            baseFactory.setExtensionRendererMode(
                DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
            )

            // Wrap base factory to prepend FfmpegAudioRenderer explicitly
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
                // Use the same decent-player UsbAudioSink that base factory renderers got
                // from buildAudioSink(), so the prepended FfmpegAudioRenderer also routes
                // through the USB DAC instead of creating its own DefaultAudioSink.
                val ffmpegSink = currentUsbSink ?: DefaultAudioSink.Builder(context).build()
                val ffmpeg = FfmpegAudioRenderer(handler, audioListener, ffmpegSink)
                android.util.Log.i("HiResAudio", "FfmpegAudioRenderer created (sink=UsbAudioSink), prepending at position 0")
                arrayOf<Renderer>(ffmpeg) + baseRenderers
            }

            exoPlayer = ExoPlayer.Builder(context, renderersFactory)
                .setAudioAttributes(audioAttributes, true)
                // NOTE: We do NOT use setHandleAudioBecomingNoisy(true) here
                // because ExoPlayer's built-in handler pauses on ALL
                // ACTION_AUDIO_BECOMING_NOISY broadcasts indiscriminately.
                // With USB DAC / AAudio exclusive sink, Android sometimes
                // sends spurious noisy broadcasts when the app goes to
                // background (false positive).
                // Instead, we register our own conditional receiver below.
                .build()

            // Attach the decent-player UsbAudioSink to the player for USB DAC routing
            if (currentUsbSink is UsbAudioSink) {
                (currentUsbSink as UsbAudioSink).attachToPlayer(exoPlayer!!)
            }

            // Register conditional ACTION_AUDIO_BECOMING_NOISY receiver
            registerAudioBecomingNoisyReceiver()

            exoPlayer?.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    this@ExoPlayerManager.isPlaying = isPlaying
                    onPlaybackStateChanged?.invoke(isPlaying)
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_READY -> {
                            val audioFormat = exoPlayer?.audioFormat
                            if (audioFormat != null) {
                                currentSampleRate = audioFormat.sampleRate
                                currentBitDepth = when (audioFormat.pcmEncoding) {
                                    C.ENCODING_PCM_16BIT -> 16
                                    C.ENCODING_PCM_24BIT -> 24
                                    C.ENCODING_PCM_32BIT -> 32
                                    C.ENCODING_PCM_FLOAT -> 32
                                    else -> 0
                                }
                                currentChannels = audioFormat.channelCount
                            }
                            onFormatInfo?.invoke(currentSampleRate, currentBitDepth, currentChannels)
                        }
                        Player.STATE_ENDED -> {
                            isPlaying = false
                            onPlaybackStateChanged?.invoke(false)
                            onTrackEnded?.invoke()
                        }
                        Player.STATE_BUFFERING -> {
                            onBuffering?.invoke(true)
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    onPlayerError?.invoke(error.message, error.errorCodeName)
                }
            })
        }
        return exoPlayer!!
    }

    /**
     * Release the ExoPlayer instance and save the current playback position.
     */
    fun releasePlayer(): Long {
        unregisterAudioBecomingNoisyReceiver()
        val pos = exoPlayer?.currentPosition ?: 0L
        try {
            exoPlayer?.stop()
            exoPlayer?.release()
        } catch (_: Exception) {}
        exoPlayer = null
        isPlaying = false
        return pos
    }

    // ── Conditional ACTION_AUDIO_BECOMING_NOISY handler ──

    /**
     * Register a BroadcastReceiver for [AudioManager.ACTION_AUDIO_BECOMING_NOISY]
     * that only pauses ExoPlayer when NO bit-perfect audio path is active.
     *
     * When [useDecentSink] (libusb USB DAC) or [useAaudioSink] (AAudio exclusive)
     * is true, the broadcast is IGNORED to prevent false-positive auto-pause
     * when the app goes to background.
     */
    private fun registerAudioBecomingNoisyReceiver() {
        if (audioBecomingNoisyReceiver != null) return // already registered

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != AudioManager.ACTION_AUDIO_BECOMING_NOISY) return

                // ── USB DAC / AAudio exclusive sink active? → Ignore ──
                // These audio paths bypass the Android mixer, so
                // ACTION_AUDIO_BECOMING_NOISY is likely a false positive
                // triggered by system re-routing when app goes to background.
                if (useDecentSink || useAaudioSink) {
                    android.util.Log.i("HiResAudio",
                        "ACTION_AUDIO_BECOMING_NOISY IGNORED — " +
                        "USB DAC (useDecentSink=$useDecentSink) or " +
                        "AAudio (useAaudioSink=$useAaudioSink) is active")
                    return
                }

                // ── Normal audio path → Pause (genuine headphone unplug) ──
                android.util.Log.i("HiResAudio",
                    "ACTION_AUDIO_BECOMING_NOISY — pausing ExoPlayer " +
                    "(normal audio path, no USB DAC/AAudio)")
                exoPlayer?.pause()
            }
        }

        try {
            val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            context.registerReceiver(receiver, filter)
            audioBecomingNoisyReceiver = receiver
            android.util.Log.i("HiResAudio",
                "Conditional ACTION_AUDIO_BECOMING_NOISY receiver registered")
        } catch (e: Exception) {
            android.util.Log.w("HiResAudio",
                "Failed to register ACTION_AUDIO_BECOMING_NOISY receiver: ${e.message}")
        }
    }

    /**
     * Unregister the ACTION_AUDIO_BECOMING_NOISY receiver.
     * Called from [releasePlayer] and from cleanup path.
     */
    private fun unregisterAudioBecomingNoisyReceiver() {
        val receiver = audioBecomingNoisyReceiver ?: return
        audioBecomingNoisyReceiver = null
        try {
            context.unregisterReceiver(receiver)
            android.util.Log.i("HiResAudio",
                "ACTION_AUDIO_BECOMING_NOISY receiver unregistered")
        } catch (e: Exception) {
            android.util.Log.w("HiResAudio",
                "Failed to unregister ACTION_AUDIO_BECOMING_NOISY receiver: ${e.message}")
        }
    }
}
