package com.meteor.kikoeruflutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android exclusive audio mode plugin.
 *
 * Provides true exclusive-mode audio by:
 * 1. Locking system media volume at max (using AudioManager)
 * 2. Using AAudio (Android NDK C API) to request AAUDIO_SHARING_MODE_EXCLUSIVE,
 *    bypassing the Android AudioFlinger mixer for bit-perfect output
 * 3. Reporting accurate exclusive-mode status (exclusive vs shared fallback)
 *
 * AAudio is part of the Android NDK and linked via the native C++ library
 * "aaudio_exclusive" (see android/app/src/main/cpp/).
 *
 * Communicates via MethodChannel "com.kikoeru.flutter/exclusive_audio".
 */
class ExclusiveAudioPlugin private constructor(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL = "com.kikoeru.flutter/exclusive_audio"

        @Volatile
        private var instance: ExclusiveAudioPlugin? = null

        // Load the native AAudio library
        init {
            try {
                System.loadLibrary("aaudio_exclusive")
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.w("ExclusiveAudio", "Failed to load native library: ${e.message}")
            }
        }

        fun getInstance(context: Context): ExclusiveAudioPlugin {
            return instance ?: synchronized(this) {
                instance ?: ExclusiveAudioPlugin(context.applicationContext).also { instance = it }
            }
        }

        // ── Static JNI bridges (used by AaudioAudioSink) ──
        fun nativeCreatePlayerStatic(): Long = nativeCreatePlayerStaticImpl()

        fun nativeInitPlayerStatic(ptr: Long, sr: Int, ch: Int, bits: Int, deviceId: Int = 0): Boolean =
            nativeInitPlayerStaticImpl(ptr, sr, ch, bits, deviceId)

        fun nativeStartPlayerStatic(ptr: Long): Boolean = nativeStartPlayerStaticImpl(ptr)

        fun nativeStopPlayerStatic(ptr: Long) = nativeStopPlayerStaticImpl(ptr)

        fun nativeDestroyPlayerStatic(ptr: Long) = nativeDestroyPlayerStaticImpl(ptr)

        fun nativeIsExclusiveStatic(ptr: Long): Boolean = nativeIsExclusiveStaticImpl(ptr)

        fun nativeGetSampleRateStatic(ptr: Long): Int = nativeGetSampleRateStaticImpl(ptr)

        fun nativeWritePcmFloatStatic(ptr: Long, buf: FloatArray, numFrames: Int): Int =
            nativeWritePcmFloatStaticImpl(ptr, buf, numFrames)

        fun nativeWritePcmI16Static(ptr: Long, buf: ShortArray, numFrames: Int): Int =
            nativeWritePcmI16StaticImpl(ptr, buf, numFrames)

        fun nativeGetFramesWrittenStatic(ptr: Long): Long = nativeGetFramesWrittenStaticImpl(ptr)

        fun nativeResetFramesWritten(ptr: Long) = nativeResetFramesWrittenStaticImpl(ptr)

        // Private native implementations (called by public statics)
        @JvmStatic private external fun nativeCreatePlayerStaticImpl(): Long
        @JvmStatic private external fun nativeInitPlayerStaticImpl(ptr: Long, sr: Int, ch: Int, bits: Int, deviceId: Int): Boolean
        @JvmStatic private external fun nativeStartPlayerStaticImpl(ptr: Long): Boolean
        @JvmStatic private external fun nativeStopPlayerStaticImpl(ptr: Long)
        @JvmStatic private external fun nativeDestroyPlayerStaticImpl(ptr: Long)
        @JvmStatic private external fun nativeIsExclusiveStaticImpl(ptr: Long): Boolean
        @JvmStatic private external fun nativeGetSampleRateStaticImpl(ptr: Long): Int
        @JvmStatic private external fun nativeWritePcmFloatStaticImpl(ptr: Long, buf: FloatArray, numFrames: Int): Int
        @JvmStatic private external fun nativeWritePcmI16StaticImpl(ptr: Long, buf: ShortArray, numFrames: Int): Int
        @JvmStatic private external fun nativeGetFramesWrittenStaticImpl(ptr: Long): Long
        @JvmStatic private external fun nativeResetFramesWrittenStaticImpl(ptr: Long)

        /**
         * Get the current USB DAC device ID being used for AAudio stream targeting.
         * 0 = default device (system default).
         */
        @JvmStatic
        fun getAaudioDeviceId(): Int = instance?.aaudioDeviceId ?: 0
    }

    // ── JNI external functions (implemented in jni_bridge.cpp) ──
    private external fun nativeCreatePlayer(): Long
    private external fun nativeInitPlayer(nativePtr: Long, sampleRate: Int, channels: Int, bitsPerSample: Int, deviceId: Int): Boolean
    private external fun nativeStartPlayer(nativePtr: Long): Boolean
    private external fun nativeStopPlayer(nativePtr: Long)
    private external fun nativeDestroyPlayer(nativePtr: Long)
    private external fun nativeIsExclusive(nativePtr: Long): Boolean
    private external fun nativeGetSampleRate(nativePtr: Long): Int
    private external fun nativeGetLatencyMs(nativePtr: Long): Double

    // Native player state
    private var nativePlayerPtr: Long = 0L
    private var aaudioExclusiveGranted = false
    private var aaudioStreamActive = false

    // USB DAC device ID for AAudio stream target
    @Volatile
    private var aaudioDeviceId: Int = 0

    // Debounce: track when the last AAudio pre-check was performed
    // to avoid rapid successive stream open/close cycles.
    private var lastPreCheckTimeMs: Long = 0L

    private var channel: MethodChannel? = null
    private var audioManager: AudioManager? = null
    @Volatile
    private var exclusiveModeEnabled = false
    private var volumeLocked = false
    private var originalMusicVolume = -1
    private var isAaudioAvailable = false

    // Volume lock — periodically restore system volume
    private var volumeLockThread: Thread? = null
    @Volatile
    private var volumeLockRunning = false

    // Broadcast receiver for volume changes
    private val volumeChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == "android.media.VOLUME_CHANGED_ACTION" && exclusiveModeEnabled) {
                restoreMaxVolume()
            }
        }
    }

    // Audio device callback for USB hotplug — auto-detect and auto-target
    private val exclusiveDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
            if (!exclusiveModeEnabled) return
            val usbDevices = addedDevices.filter {
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
            }
            if (usbDevices.isNotEmpty()) {
                val device = usbDevices.first()
                val name = device.productName ?: "USB DAC"
                val id = device.id
                android.util.Log.i("ExclusiveAudio", "USB DAC auto-detected: $name (#$id)")
                // Auto-target AAudio to this USB DAC
                setAaudioDeviceId(id)
                channel?.invokeMethod("onUsbDeviceAttached", mapOf(
                    "deviceName" to name,
                    "deviceId" to id,
                ))
            }
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
            if (!exclusiveModeEnabled) return
            val usbDevices = removedDevices.filter {
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
            }
            if (usbDevices.isNotEmpty()) {
                val wasTargeted = usbDevices.any { it.id == aaudioDeviceId }
                android.util.Log.i("ExclusiveAudio", "USB DAC detached: wasTargeted=$wasTargeted")
                // Reset to default device if the removed device was our target
                if (wasTargeted) {
                    setAaudioDeviceId(0)
                }
                channel?.invokeMethod("onUsbDeviceDetached", mapOf(
                    "deviceId" to usbDevices.first().id
                ))
            }
        }
    }

    fun attachChannel(methodChannel: MethodChannel) {
        this.channel = methodChannel
    }

    private fun ensureAudioManager() {
        if (audioManager == null) {
            audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        }
    }

    /**
     * Check whether the device supports AAudio (Android 8.1+ / API 27+).
     */
    private fun checkAaudioSupport(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1
    }

    /**
     * Set the USB DAC device ID for AAudio stream targeting.
     * The AAudio stream will be re-initialized to target this device.
     * Skips if the device ID is unchanged (prevents duplicate pre-checks
     * when multiple callers race to set the same device).
     */
    fun setAaudioDeviceId(deviceId: Int) {
        // Skip if same device — prevents duplicate AAudio pre-checks
        // when both auto-route and exclusive mode toggle race to set the same ID.
        if (deviceId == aaudioDeviceId) {
            android.util.Log.v("ExclusiveAudio", "setAaudioDeviceId: already set to #$deviceId, skipping")
            return
        }
        aaudioDeviceId = deviceId
        if (exclusiveModeEnabled) {
            // Re-init the test AAudio stream with the new device ID
            initAaudioPlayer()

            // Also recreate the AudioSink's native player with the new device ID
            // so that actual playback content switches to the new USB DAC
            // WITHOUT needing to restart ExoPlayer.
            AaudioAudioSink.currentSink?.recreateWithDeviceId(deviceId)
        }
    }

    private fun initAaudioPlayer() {
        // Debounce: skip if called within 500ms of the last pre-check.
        // Prevents rapid duplicate stream creation when multiple code paths
        // (auto-target, bypass enable, exclusive toggle) fire in quick succession.
        val nowMs = System.currentTimeMillis()
        if (nowMs - lastPreCheckTimeMs < 500) {
            android.util.Log.v("ExclusiveAudio", "initAaudioPlayer: debounced (${nowMs - lastPreCheckTimeMs}ms since last)")
            return
        }
        lastPreCheckTimeMs = nowMs

        if (nativePlayerPtr != 0L) {
            destroyAaudioPlayer()
        }

        if (!checkAaudioSupport()) return

        try {
            nativePlayerPtr = nativeCreatePlayer()
            if (nativePlayerPtr == 0L) {
                android.util.Log.w("ExclusiveAudio", "Failed to create native AAudio player (pre-check)")
                return
            }

            // Open a temporary test stream to check if exclusive mode is available.
            // Always use FLOAT format for best compatibility with device sample rate.
            // The stream is CLOSED immediately after detection — it does NOT coexist
            // with the actual playback stream created by AaudioAudioSink.
            val testSuccess = nativeInitPlayer(nativePlayerPtr, 48000, 2, 32, aaudioDeviceId)
            if (testSuccess) {
                aaudioExclusiveGranted = nativeIsExclusive(nativePlayerPtr)
                val actualRate = nativeGetSampleRate(nativePlayerPtr)
                aaudioStreamActive = true

                android.util.Log.i("ExclusiveAudio",
                    "[PRE-CHECK] AAudio test stream: exclusive=$aaudioExclusiveGranted, rate=${actualRate}Hz")

                // Immediately close the test stream — this must happen BEFORE playback starts
                // so the playback stream can be granted exclusive access.
                nativeStopPlayer(nativePlayerPtr)
                nativeDestroyPlayer(nativePlayerPtr)
                nativePlayerPtr = 0L
                aaudioExclusiveGranted = false
                aaudioStreamActive = false
            } else {
                android.util.Log.w("ExclusiveAudio", "Failed to init test AAudio stream (pre-check)")
                nativeDestroyPlayer(nativePlayerPtr)
                nativePlayerPtr = 0L
                aaudioExclusiveGranted = false
                aaudioStreamActive = false
            }
        } catch (e: Exception) {
            android.util.Log.e("ExclusiveAudio", "AAudio pre-check error: ${e.message}")
            nativePlayerPtr = 0L
            aaudioExclusiveGranted = false
            aaudioStreamActive = false
        }
    }

    /**
     * Destroy the native AAudio player and release resources.
     */
    private fun destroyAaudioPlayer() {
        if (nativePlayerPtr != 0L) {
            try {
                nativeStopPlayer(nativePlayerPtr)
                nativeDestroyPlayer(nativePlayerPtr)
            } catch (e: Exception) {
                android.util.Log.w("ExclusiveAudio", "Error destroying native player: ${e.message}")
            }
            nativePlayerPtr = 0L
            aaudioExclusiveGranted = false
            aaudioStreamActive = false
        }
    }

    /**
     * Restore system media volume to maximum.
     */
    private fun restoreMaxVolume() {
        try {
            ensureAudioManager()
            val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: return
            val currentVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: return
            if (currentVol < maxVol) {
                audioManager?.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0)
            }
        } catch (_: Exception) {}
    }

    /**
     * Start periodic volume lock thread.
     */
    private fun startVolumeLock() {
        if (volumeLockRunning) return
        volumeLockRunning = true

        volumeLockThread = Thread {
            while (volumeLockRunning && exclusiveModeEnabled) {
                restoreMaxVolume()
                try {
                    Thread.sleep(500)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }.apply {
            isDaemon = true
            name = "exclusive-volume-lock"
            start()
        }
    }

    /**
     * Stop volume lock thread.
     */
    private fun stopVolumeLock() {
        volumeLockRunning = false
        volumeLockThread?.interrupt()
        volumeLockThread = null
    }

    /**
     * Register broadcast receiver for volume changes.
     */
    private fun registerVolumeReceiver() {
        try {
            val filter = IntentFilter("android.media.VOLUME_CHANGED_ACTION")
            context.registerReceiver(volumeChangeReceiver, filter)
        } catch (_: Exception) {}
    }

    /**
     * Unregister volume change receiver.
     */
    private fun unregisterVolumeReceiver() {
        try {
            context.unregisterReceiver(volumeChangeReceiver)
        } catch (_: Exception) {}
    }

    /**
     * Register audio device callback for USB hotplug.
     */
    private fun registerAudioDeviceCallback() {
        ensureAudioManager()
        try {
            audioManager?.registerAudioDeviceCallback(exclusiveDeviceCallback, null)
        } catch (_: Exception) {}
    }

    /**
     * Unregister audio device callback.
     */
    private fun unregisterAudioDeviceCallback() {
        try {
            audioManager?.unregisterAudioDeviceCallback(exclusiveDeviceCallback)
        } catch (_: Exception) {}
    }

/**
      * Auto-detect the first connected USB DAC and target the AAudio stream to it.
      * Called on enable and on USB device attach.
      * Only auto-targets if no device was already explicitly selected (deviceId == 0).
      */
    private fun autoTargetFirstUsbDevice() {
        // Skip auto-target if a device was already explicitly selected
        if (aaudioDeviceId > 0) {
            android.util.Log.i("ExclusiveAudio", "Device already explicitly set (#$aaudioDeviceId), skipping auto-target")
            return
        }
        try {
            ensureAudioManager()
            val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val usbDevice = devices?.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
            }
            if (usbDevice != null) {
                val name = usbDevice.productName ?: "USB DAC"
                android.util.Log.i("ExclusiveAudio", "Auto-targeting USB DAC: $name (#${usbDevice.id})")
                setAaudioDeviceId(usbDevice.id)
            }
        } catch (e: Exception) {
            android.util.Log.w("ExclusiveAudio", "Auto-target USB failed: ${e.message}")
        }
    }

    /**
     * Enable exclusive audio mode.
     *
     * What this does:
     * 1. Saves current system volume, then locks to max
     * 2. Starts periodic volume restore thread
     * 3. Registers broadcast receiver for instantaneous volume change detection
     * 4. Registers USB device callback for hotplug detection
     * 5. Auto-detects connected USB DAC and targets AAudio stream
     * 6. Initializes AAudio native player with exclusive mode request
     * 7. Reports whether AAudio exclusive mode was granted
     */
    private fun enableExclusiveMode() {
        ensureAudioManager()

        // Save current volume for restoration on disable
        originalMusicVolume = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: -1

        // Check AAudio support
        isAaudioAvailable = checkAaudioSupport()

        // Lock volume to max
        restoreMaxVolume()
        volumeLocked = true

        // Start monitoring
        startVolumeLock()
        registerVolumeReceiver()
        registerAudioDeviceCallback()

        // Auto-detect and target USB DAC if connected
        autoTargetFirstUsbDevice()

        // Initialize AAudio native player (open exclusive stream)
        initAaudioPlayer()
        val aaudioActive = aaudioStreamActive
        val mixerBypassed = aaudioExclusiveGranted

        exclusiveModeEnabled = true

        channel?.invokeMethod("onExclusiveModeChanged", mapOf(
            "enabled" to true,
            "volumeLocked" to true,
            "aaudioAvailable" to isAaudioAvailable,
            "aaudioActive" to aaudioActive,
            "aaudioExclusive" to aaudioExclusiveGranted,
            "mixerBypassed" to mixerBypassed,
        ))
    }

    /**
     * Disable exclusive audio mode and restore system volume.
     */
    private fun disableExclusiveMode() {
        exclusiveModeEnabled = false
        volumeLocked = false

        // Stop monitoring
        stopVolumeLock()
        unregisterVolumeReceiver()
        unregisterAudioDeviceCallback()

        // Destroy AAudio native player
        destroyAaudioPlayer()

        // Restore original volume
        if (originalMusicVolume >= 0) {
            try {
                audioManager?.setStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    originalMusicVolume,
                    0
                )
            } catch (_: Exception) {}
        }

        channel?.invokeMethod("onExclusiveModeChanged", mapOf(
            "enabled" to false,
            "volumeLocked" to false,
            "aaudioAvailable" to isAaudioAvailable,
            "aaudioActive" to false,
            "mixerBypassed" to false,
        ))
    }

    /**
     * Build a status report map.
     */
    private fun getStatusMap(): Map<String, Any?> {
        ensureAudioManager()
        val currentVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0
        val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 0
        val latencyMs = if (nativePlayerPtr != 0L) {
            try { nativeGetLatencyMs(nativePlayerPtr) } catch (_: Exception) { 0.0 }
        } else 0.0

        return mapOf(
            "enabled" to exclusiveModeEnabled,
            "volumeLocked" to volumeLocked,
            "currentVolume" to currentVol,
            "maxVolume" to maxVol,
            "aaudioAvailable" to isAaudioAvailable,
            "aaudioActive" to aaudioStreamActive,
            "aaudioExclusive" to aaudioExclusiveGranted,
            "mixerBypassed" to aaudioExclusiveGranted,
            "aaudioSampleRate" to (if (nativePlayerPtr != 0L) {
                try { nativeGetSampleRate(nativePlayerPtr) } catch (_: Exception) { 0 }
            } else 0),
            "aaudioLatencyMs" to latencyMs,
            "androidSdk" to Build.VERSION.SDK_INT,
        )
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> {
                result.success(true)
            }
            "enable" -> {
                enableExclusiveMode()
                result.success(true)
            }
            "disable" -> {
                disableExclusiveMode()
                result.success(true)
            }
            "isActive" -> {
                result.success(exclusiveModeEnabled)
            }
            "getStatus" -> {
                result.success(getStatusMap())
            }
            "onVolumeKeyPressed" -> {
                restoreMaxVolume()
                result.success(true)
            }
            "setAaudioDeviceId" -> {
                val deviceId = call.argument<Int>("deviceId") ?: 0
                setAaudioDeviceId(deviceId)
                result.success(true)
            }
            "getSystemVolume" -> {
                ensureAudioManager()
                val currentVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0
                val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 0
                result.success(mapOf(
                    "currentVolume" to currentVol,
                    "maxVolume" to maxVol,
                ))
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Clean up when the plugin is destroyed.
     */
    fun cleanup() {
        if (exclusiveModeEnabled) {
            disableExclusiveMode()
        }
        destroyAaudioPlayer()
    }
}
