package com.meteor.kikoeruflutter

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.service.quicksettings.TileService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private var floatingLyricPlugin: FloatingLyricPlugin? = null
    private var equalizerPlugin: EqualizerPlugin? = null
    private var hiResAudioPlugin: HiResAudioPlugin? = null
    private var exclusiveAudioPlugin: ExclusiveAudioPlugin? = null
    private var screenStatePlugin: ScreenStatePlugin? = null
    private var usbDacPlugin: UsbDacPlugin? = null
    
    // Home widget action channel — used to forward widget button presses to Dart
    companion object {
        const val WIDGET_CHANNEL = "com.kikoeru.flutter/home_widget_actions"
        const val ACTION_TOGGLE_PLAYBACK = "togglePlayback"
        const val ACTION_SKIP_NEXT = "skipNext"
        const val ACTION_SKIP_PREV = "skipPrev"
    }
    private var widgetChannel: MethodChannel? = null
    private var appLockTileChannel: MethodChannel? = null
    private var tileReceiver: BroadcastReceiver? = null
    private var usbReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Register runtime receiver for USB_DEVICE_ATTACHED (without the manifest
        // intent-filter, which triggers the Android chooser dialog).
        // The DAC is NOT claimed here — only when user enables routing in settings.
        registerUsbReceiver()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Forward widget intents
        handleWidgetIntent(intent)
    }

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

        // 注册 Screen State 插件 (screen off/on detection for auto-relock)
        screenStatePlugin = ScreenStatePlugin.getInstance(this)
        screenStatePlugin?.attachChannel(flutterEngine)

        // 注册 Audio Conversion 插件 (WAV → FLAC)
        AudioConversionPlugin.register(flutterEngine)

        // 注册 SAF 文件工具（用于导入 content:// URI 的文件夹）
        SafFileUtils.register(flutterEngine, this)

        // 注册 USB DAC 插件 (bit-perfect USB audio output via libusb)
        usbDacPlugin = UsbDacPlugin.getInstance(this)
        usbDacPlugin?.loadNativeLibrary()
        val usbDacChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UsbDacPlugin.CHANNEL
        )
        usbDacPlugin?.attachChannel(usbDacChannel)
        usbDacChannel.setMethodCallHandler(usbDacPlugin)

        // Set up channel for App Lock Quick Settings tile
        appLockTileChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.kikoeru.flutter/app_lock_tile"
        ).apply {
            setMethodCallHandler { call, _ ->
                if (call.method == "updateAppLockTile") {
                    requestTileUpdate()
                }
            }
        }
        registerTileReceiver()

        // Forward pending widget intents
        handleWidgetIntent(intent)
    }

    /**
     * Requests the system to refresh the App Lock Quick Settings tile.
     * This triggers [AppLockTileService.onStartListening], which re-reads
     * SharedPreferences and updates the tile icon/subtitle/state.
     *
     * [TileService.requestListeningState] is available on API 33+.
     * On older devices the tile updates the next time it becomes visible.
     */
    private fun requestTileUpdate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            TileService.requestListeningState(
                this,
                ComponentName(this, AppLockTileService::class.java)
            )
        }
    }

    private fun registerTileReceiver() {
        tileReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == AppLockTileService.ACTION_TOGGLE) {
                    val enabled = intent.getBooleanExtra(AppLockTileService.EXTRA_ENABLED, false)
                    appLockTileChannel?.invokeMethod("tileToggled", enabled)
                }
            }
        }
        // RECEIVER_EXPORTED requires API 33+; use two-arg overload on older devices
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(tileReceiver, IntentFilter(AppLockTileService.ACTION_TOGGLE), Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(tileReceiver, IntentFilter(AppLockTileService.ACTION_TOGGLE))
        }
    }

    private fun registerUsbReceiver() {
        usbReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val action = intent.action
                val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE) ?: return

                // Only handle USB Audio Class devices with an AudioStreaming interface
                val isAudioDevice = (0 until device.interfaceCount).any { i ->
                    val iface = device.getInterface(i)
                    iface.interfaceClass == UsbConstants.USB_CLASS_AUDIO &&
                        iface.interfaceSubclass == 2
                }
                if (!isAudioDevice) return

                when (action) {
                    UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                        // Show the USB permission dialog so the user can grant access.
                        // On grant, auto-enable UsbAudioSink routing so the next playback
                        // goes through the USB DAC without requiring manual toggle in settings.
                        val usbAudioDevice = com.decent.usbaudio.UsbAudioDevice.getInstance(context)
                        usbAudioDevice.requestPermission(device) { granted ->
                            if (granted) {
                                android.util.Log.i("MainActivity",
                                    "USB DAC permission granted for ${device.productName}")
                                val plugin = this@MainActivity.hiResAudioPlugin
                                if (plugin != null) {
                                    plugin.autoRouteToUsbDac(device)
                                }
                            }
                        }
                    }
                    UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                        android.util.Log.i("MainActivity",
                            "USB DAC detached: ${device.productName}")
                        // Invalidate the cached USB device connection so the next
                        // openDevice() gets a fresh fd for the new physical session.
                        com.decent.usbaudio.UsbAudioDevice.getInstance(context).closeDevice()
                        val plugin = this@MainActivity.hiResAudioPlugin
                        if (plugin != null) {
                            plugin.onUsbDeviceDetached()
                        }
                    }
                }
            }
        }
        val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED).apply {
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(usbReceiver, filter)
        }
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
        usbDacPlugin?.cleanup()
        screenStatePlugin?.cleanup()
        tileReceiver?.let { unregisterReceiver(it) }
        usbReceiver?.let { unregisterReceiver(it) }
        super.onDestroy()
    }
}
