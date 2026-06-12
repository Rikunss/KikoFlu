package com.meteor.kikoeruflutter

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Audio Conversion plugin (Android).
 *
 * All WAV conversion is now handled by ffmpeg-kit Flutter plugin (Dart side).
 * This native plugin only provides encoder availability checks for backward
 * compatibility with any code that queries via MethodChannel.
 *
 * Channel: com.kikoeru.flutter/audio_conversion
 * Methods: checkEncoder (returns true for all formats — ffmpeg handles everything)
 */
class AudioConversionPlugin(private val flutterEngine: FlutterEngine) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.kikoeru.flutter/audio_conversion"

        fun register(flutterEngine: FlutterEngine) {
            val channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
            )
            channel.setMethodCallHandler(AudioConversionPlugin(flutterEngine))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkEncoder" -> {
                // ffmpeg-kit audio variant includes all audio encoders (FLAC, ALAC, MP3, Opus, AAC)
                // Always return true for all formats.
                result.success(true)
            }
            "convertWav" -> {
                // Conversion is handled by ffmpeg-kit on the Dart side.
                // This path should never be reached, but return a clear error just in case.
                result.error(
                    "DEPRECATED",
                    "WAV conversion is now handled by ffmpeg-kit (Dart side). " +
                    "Use ffmpeg_kit_flutter_new_audio FFmpegKit API directly.",
                    null
                )
            }
            else -> result.notImplemented()
        }
    }
}
