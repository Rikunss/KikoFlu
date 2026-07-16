package com.meteor.kikoeruflutter

import android.content.Context
import android.media.audiofx.Equalizer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android native Equalizer plugin
 * Uses android.media.audiofx.Equalizer to provide hardware EQ
 * Communicates with Dart side via MethodChannel
 */
class EqualizerPlugin private constructor(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL = "com.kikoeru.flutter/equalizer"

        @Volatile
        private var instance: EqualizerPlugin? = null

        fun getInstance(context: Context): EqualizerPlugin {
            return instance ?: synchronized(this) {
                instance ?: EqualizerPlugin(context.applicationContext).also { instance = it }
            }
        }
    }

    private var equalizer: Equalizer? = null
    private var audioSessionId: Int = 0
    private var hasValidSessionId: Boolean = false

    /**
     * Set the audio session ID from just_audio
     * Must be called before using EQ
     */
    fun setAudioSessionId(sessionId: Int) {
        if (audioSessionId == sessionId && hasValidSessionId) return
        audioSessionId = sessionId
        hasValidSessionId = sessionId > 0
        releaseEqualizer()
    }

    private fun getOrCreateEqualizer(): Equalizer? {
        if (equalizer == null && hasValidSessionId) {
            try {
                equalizer = Equalizer(0, audioSessionId)
                equalizer?.enabled = false
            } catch (e: Exception) {
                println("[EqualizerPlugin] Failed to create Equalizer: ${e.message}")
            }
        }
        return equalizer
    }

    private fun releaseEqualizer() {
        try {
            equalizer?.enabled = false
            equalizer?.release()
        } catch (_: Exception) {}
        equalizer = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> {
                result.success(true)
            }
            "getBands" -> {
                val eq = getOrCreateEqualizer()
                if (eq != null) {
                    try {
                        val numberOfBands = eq.numberOfBands.toInt()
                        val bands = mutableListOf<Double>()
                        for (i in 0 until numberOfBands) {
                            val freq = eq.getCenterFreq(i.toShort()) / 1000.0 // Convert mHz to Hz
                            bands.add(freq)
                        }
                        result.success(bands)
                    } catch (e: Exception) {
                        result.error("EQ_ERROR", "Failed to get bands: ${e.message}", null)
                    }
                } else {
                    result.success(listOf(31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0))
                }
            }
            "setAudioSessionId" -> {
                val sessionId = call.argument<Int>("sessionId") ?: 0
                setAudioSessionId(sessionId)
                result.success(true)
            }
            "setGains" -> {
                val gainsArg = call.argument<List<Double>>("gains")
                if (gainsArg == null) {
                    result.error("INVALID_ARGS", "gains list required", null)
                    return
                }

                val eq = getOrCreateEqualizer()
                if (eq != null) {
                    try {
                        val numberOfBands = eq.numberOfBands.toInt()
                        val bandLevelRange = eq.getBandLevelRange()
                        for (i in 0 until numberOfBands.coerceAtMost(gainsArg.size)) {
                            val millibels = ((gainsArg[i] * 100).toInt())
                                .coerceIn(bandLevelRange[0].toInt(), bandLevelRange[1].toInt())
                                .toShort()
                            eq.setBandLevel(i.toShort(), millibels)
                        }
                        eq.enabled = true
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EQ_ERROR", "Failed to set gains: ${e.message}", null)
                    }
                } else {
                    result.error("EQ_NOT_READY", "Equalizer not initialized. Audio session not ready.", null)
                }
            }
            "reset" -> {
                val eq = getOrCreateEqualizer()
                if (eq != null) {
                    try {
                        eq.enabled = false
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EQ_ERROR", "Failed to reset: ${e.message}", null)
                    }
                } else {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Cleanup resources
     */
    fun cleanup() {
        releaseEqualizer()
    }
}
