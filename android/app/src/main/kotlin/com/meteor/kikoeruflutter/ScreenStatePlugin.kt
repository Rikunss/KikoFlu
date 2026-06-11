package com.meteor.kikoeruflutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Plugin that listens for Android screen on/off broadcasts and forwards them
 * to the Dart side via MethodChannel, so the app can auto-relock when the
 * screen turns off (even if the app stays in [android.app.Activity.RESUMED]
 * state due to a media notification).
 *
 * Usage: call [register] in [MainActivity.configureFlutterEngine].
 */
class ScreenStatePlugin private constructor(private val context: Context) {

    companion object {
        const val CHANNEL = "com.kikoeru.flutter/screen_state"

        private const val METHOD_SCREEN_OFF = "screenOff"

        @Volatile
        private var instance: ScreenStatePlugin? = null

        fun getInstance(context: Context): ScreenStatePlugin {
            return instance ?: synchronized(this) {
                instance ?: ScreenStatePlugin(context.applicationContext).also { instance = it }
            }
        }
    }

    private var channel: MethodChannel? = null
    private var isRegistered = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_SCREEN_OFF) {
                channel?.invokeMethod(METHOD_SCREEN_OFF, null)
            }
        }
    }

    /**
     * Attach the method channel and register the broadcast receiver.
     * Should be called from [MainActivity.configureFlutterEngine].
     */
    fun attachChannel(flutterEngine: FlutterEngine) {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        if (!isRegistered) {
            val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
            context.registerReceiver(screenReceiver, filter)
            isRegistered = true
            android.util.Log.d("ScreenStatePlugin", "Screen broadcast receiver registered")
        }
    }

    /**
     * Clean up — unregister the broadcast receiver.
     */
    fun cleanup() {
        if (isRegistered) {
            try {
                context.unregisterReceiver(screenReceiver)
            } catch (_: Exception) {
                // Already unregistered
            }
            isRegistered = false
            android.util.Log.d("ScreenStatePlugin", "Screen broadcast receiver unregistered")
        }
    }
}
