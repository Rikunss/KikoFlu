package com.meteor.kikoeruflutter

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private var floatingLyricPlugin: FloatingLyricPlugin? = null
    private var equalizerPlugin: EqualizerPlugin? = null
    private var hiResAudioPlugin: HiResAudioPlugin? = null
    private var exclusiveAudioPlugin: ExclusiveAudioPlugin? = null
    
    // Home widget action channel — used to forward widget button presses to Dart
    companion object {
        const val WIDGET_CHANNEL = "com.kikoeru.flutter/home_widget_actions"
        const val ACTION_TOGGLE_PLAYBACK = "togglePlayback"
        const val ACTION_SKIP_NEXT = "skipNext"
        const val ACTION_SKIP_PREV = "skipPrev"
    }
    private var widgetChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Handle home widget intents (sent from widget provider)
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL
        )
        
        // 注册悬浮字幕插件
        floatingLyricPlugin = FloatingLyricPlugin.getInstance(this)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FloatingLyricPlugin.CHANNEL
        )
        floatingLyricPlugin?.attachChannel(channel)
        channel.setMethodCallHandler(floatingLyricPlugin)

        // 注册 Equalizer 插件
        equalizerPlugin = EqualizerPlugin.getInstance(this)
        val eqChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EqualizerPlugin.CHANNEL
        )
        eqChannel.setMethodCallHandler(equalizerPlugin)

        // 注册 Hi-Res Audio 插件
        hiResAudioPlugin = HiResAudioPlugin.getInstance(this)
        val hiResChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HiResAudioPlugin.CHANNEL
        )
        hiResAudioPlugin?.attachChannel(hiResChannel)
        hiResChannel.setMethodCallHandler(hiResAudioPlugin)

        // 注册 Exclusive Audio 插件
        exclusiveAudioPlugin = ExclusiveAudioPlugin.getInstance(this)
        val exclusiveChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ExclusiveAudioPlugin.CHANNEL
        )
        exclusiveAudioPlugin?.attachChannel(exclusiveChannel)
        exclusiveChannel.setMethodCallHandler(exclusiveAudioPlugin)

        // Forward pending widget intents
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent) {
        val channel = widgetChannel ?: return
        when (intent.action) {
            KikoFluWidgetProvider.ACTION_PLAY_PAUSE,
            "com.meteor.kikoeruflutter.TOGGLE_PLAYBACK" -> {
                channel.invokeMethod(ACTION_TOGGLE_PLAYBACK, null)
            }
            KikoFluWidgetProvider.ACTION_NEXT,
            "com.meteor.kikoeruflutter.SKIP_NEXT" -> {
                channel.invokeMethod(ACTION_SKIP_NEXT, null)
            }
            KikoFluWidgetProvider.ACTION_PREV,
            "com.meteor.kikoeruflutter.SKIP_PREV" -> {
                channel.invokeMethod(ACTION_SKIP_PREV, null)
            }
        }
    }

    override fun onDestroy() {
        // 不在 Activity 销毁时清理悬浮窗，以便在后台（如侧滑返回桌面）时保持显示
        // floatingLyricPlugin?.cleanup()
        equalizerPlugin?.cleanup()
        hiResAudioPlugin?.cleanup()
        exclusiveAudioPlugin?.cleanup()
        super.onDestroy()
    }
}
