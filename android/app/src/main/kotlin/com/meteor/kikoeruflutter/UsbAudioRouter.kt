package com.meteor.kikoeruflutter

import android.content.Context
import android.hardware.usb.UsbDevice
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel
import com.decent.usbaudio.UsbAudioDevice as DecentUsbAudioDevice

/**
 * Manages USB audio device discovery, routing, and bit-perfect configuration.
 *
 * Responsibilities:
 * - USB device hotplug detection via [AudioManager.registerAudioDeviceCallback]
 * - Legacy AudioManager-based USB routing (setPreferredAudioDevice)
 * - PreferredMixerAttributes (Android 14+ MIXER_BEHAVIOR_BIT_PERFECT API)
 * - decent-player UsbAudioSink auto-routing on USB plug
 * - USB permission request via [DecentUsbAudioDevice]
 */
class UsbAudioRouter(private val context: Context) {

    var usbBypassEnabled: Boolean = false
    var isRoutingToUsbDac: Boolean = false
        private set
    private var audioManager: AudioManager? = null
    private val usbAudioDeviceList = mutableListOf<AudioDeviceInfo>()

    var lastPlayUrl: String? = null
    var lastPlayPositionMs: Long = 0L

    private var lastRoutedDevice: AudioDeviceInfo? = null
    @Volatile
    private var mixerAttributesApplied: Boolean = false

    @Volatile
    private var usbCallbackRegistered: Boolean = false

    /** Reference to the plugin's method channel for event callbacks. */
    private var channel: MethodChannel? = null

    /** Reference to the player manager — used for player operations like setPreferredAudioDevice. */
    private var playerManager: ExoPlayerManager? = null

    /** Decent-player UsbAudioDevice singleton. */
    private val decentUsbAudioDevice = DecentUsbAudioDevice.getInstance(context)

    fun attach(channel: MethodChannel, playerManager: ExoPlayerManager) {
        this.channel = channel
        this.playerManager = playerManager
        registerUsbCallback()
        channel.invokeMethod("onOutputDeviceChanged", mapOf(
            "activeDeviceType" to getActiveOutputDeviceType()
        ))
    }

    fun detach() {
        unregisterUsbCallback()
        this.channel = null
        this.playerManager = null
    }

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
                if (usbBypassEnabled && !isRoutingToUsbDac) {
                    routeToUsbDevice(usbDevices.first())
                }
            }
            channel?.invokeMethod("onOutputDeviceChanged", mapOf(
                "activeDeviceType" to getActiveOutputDeviceType()
            ))
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
            val wasRouting = isRoutingToUsbDac
            usbAudioDeviceList.removeAll(removedDevices.toList())
            if (wasRouting) {
                isRoutingToUsbDac = false
            }
            channel?.invokeMethod("onUsbDevicesChanged", mapOf(
                "devices" to serializeUsbDevices()
            ))
            channel?.invokeMethod("onOutputDeviceChanged", mapOf(
                "activeDeviceType" to getActiveOutputDeviceType()
            ))
        }
    }

    /**
     * Determine the current best output audio device type.
     * Priority: USB > Wired Headphones > Bluetooth > Built-in Speaker
     */
    fun getActiveOutputDeviceType(): String {
        ensureAudioManager()
        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS) ?: return "unknown"

        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_DOCK -> {
                    if (isRoutingToUsbDac) return "usb_dac"
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
     * Serialise the currently detected USB audio devices to a list of maps.
     */
    fun serializeUsbDevices(): List<Map<String, Any?>> {
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

            val mixerAttrs = android.media.AudioMixerAttributes.Builder(audioFormat)
                .setMixerBehavior(android.media.AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT)
                .build()

            val attrs = android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()

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
     */
    private fun routeToUsbDevice(device: AudioDeviceInfo) {
        try {
            val player = playerManager?.exoPlayer
            player?.setPreferredAudioDevice(device)
            isRoutingToUsbDac = true
            lastRoutedDevice = device

            val mixerSuccess = applyPreferredMixerAttributes(
                device,
                playerManager?.currentSampleRate ?: 0,
                playerManager?.currentBitDepth ?: 0
            )

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
     */
    fun clearUsbRouting() {
        clearPreferredMixerAttributes(lastRoutedDevice)
        lastRoutedDevice = null

        try {
            playerManager?.exoPlayer?.setPreferredAudioDevice(null)
        } catch (_: Exception) {}
        isRoutingToUsbDac = false
        channel?.invokeMethod("onUsbRoutingChanged", mapOf(
            "routed" to false,
            "deviceName" to "",
            "mixerAttributesApplied" to false
        ))
    }

    /**
     * Auto-route to the given USB DAC device using UsbAudioSink.
     *
     * Called from [MainActivity]'s USB receiver after permission is granted.
     */
    fun autoRouteToUsbDac(device: UsbDevice) {
        val wasAlreadyRouted = playerManager?.useDecentSink ?: false
        playerManager?.useDecentSink = true
        if (!wasAlreadyRouted) {
            playerManager?.releasePlayer()
        }
        isRoutingToUsbDac = true
        android.util.Log.i("HiResAudio",
            "USB DAC auto-routed: ${device.productName} via UsbAudioSink" +
            if (wasAlreadyRouted) " (already routed, reusing player)" else "")
        channel?.invokeMethod("onUsbRoutingChanged", mapOf(
            "routed" to true,
            "deviceName" to (device.productName ?: "USB DAC"),
            "mixerAttributesApplied" to false
        ))
        channel?.invokeMethod("onOutputDeviceChanged", mapOf(
            "activeDeviceType" to "usb_dac"
        ))
        channel?.invokeMethod("onUsbDacAutoRouted", mapOf(
            "deviceName" to (device.productName ?: "USB DAC"),
            "vendorId" to device.vendorId,
            "productId" to device.productId
        ))
    }

    /**
     * Called when the USB DAC is physically disconnected.
     */
    fun onUsbDeviceDetached() {
        val wasRouting = isRoutingToUsbDac
        isRoutingToUsbDac = false
        playerManager?.useDecentSink = false

        android.util.Log.i("HiResAudio",
            "USB DAC physically detached — routing cleared, useDecentSink=false")

        if (wasRouting) {
            channel?.invokeMethod("onUsbRoutingChanged", mapOf(
                "routed" to false,
                "deviceName" to "",
                "mixerAttributesApplied" to false
            ))
            channel?.invokeMethod("onOutputDeviceChanged", mapOf(
                "activeDeviceType" to getActiveOutputDeviceType()
            ))
        }
    }

    /**
     * Route to a specific USB audio device by its ID.
     */
    fun routeToDeviceById(deviceId: Int): Boolean {
        ensureAudioManager()
        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val targetDevice = devices?.firstOrNull {
            it.id == deviceId && (it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_DOCK)
        }
        return if (targetDevice != null) {
            routeToUsbDevice(targetDevice)
            true
        } else {
            false
        }
    }

    /**
     * Enable USB bypass mode and route to the specified device (or first available).
     */
    fun setUsbBypassMode(enabled: Boolean, deviceId: Int?) {
        usbBypassEnabled = enabled
        if (enabled) {
            registerUsbCallback()
            if (deviceId != null && deviceId > 0) {
                val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                val targetDevice = devices?.firstOrNull {
                    (it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                     it.type == AudioDeviceInfo.TYPE_USB_HEADSET) &&
                    it.id == deviceId
                }
                if (targetDevice != null) {
                    routeToUsbDevice(targetDevice)
                } else {
                    val fallback = devices?.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                        it.type == AudioDeviceInfo.TYPE_USB_HEADSET
                    }
                    if (fallback != null) routeToUsbDevice(fallback)
                }
            } else {
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
    }

    /**
     * Refresh USB device list.
     */
    fun refreshUsbDevices(): List<Map<String, Any?>> {
        ensureAudioManager()
        registerUsbCallback()
        usbAudioDeviceList.clear()
        val allDevices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        if (allDevices != null) {
            usbAudioDeviceList.addAll(allDevices.filter {
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_DOCK
            })
        }
        return serializeUsbDevices()
    }

    /**
     * Request USB device permission for the connected USB DAC.
     */
    fun requestUsbPermission(): Boolean {
        val device = decentUsbAudioDevice.findUsbAudioDevice()
        if (device != null) {
            if (decentUsbAudioDevice.hasPermission(device)) {
                decentUsbAudioDevice.openDevice(device)
                return true
            } else {
                val currentChannel = channel
                decentUsbAudioDevice.requestPermission(device) { granted ->
                    if (granted) {
                        android.util.Log.i("HiResAudio",
                            "USB permission granted for ${device.productName}")
                        currentChannel?.invokeMethod("onOutputDeviceChanged", mapOf(
                            "activeDeviceType" to getActiveOutputDeviceType()
                        ))
                    }
                }
                return false
            }
        }
        return false
    }


    /**
     * Apply preferred mixer attributes for a specific USB device.
     */
    fun applyMixerAttributes(deviceId: Int, sampleRate: Int, bitDepth: Int): Map<String, Any?> {
        ensureAudioManager()
        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val device = devices?.firstOrNull { it.id == deviceId }
        if (device != null) {
            val success = applyPreferredMixerAttributes(device, sampleRate, bitDepth)
            return mapOf(
                "success" to success,
                "apiSupported" to (Build.VERSION.SDK_INT >= 34)
            )
        }
        return mapOf("success" to false, "error" to "DEVICE_NOT_FOUND")
    }

    /**
     * Clear preferred mixer attributes on the last routed device.
     */
    fun clearMixerAttributes() {
        clearPreferredMixerAttributes(lastRoutedDevice)
    }

    /**
     * Get the current preferred mixer attributes for the last routed device.
     */
    fun getMixerAttributes(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT >= 34 && lastRoutedDevice != null) {
            try {
                val attrs = android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
                val current = audioManager?.getPreferredMixerAttributes(attrs, lastRoutedDevice!!)
                if (current != null) {
                    val audioFormat = current.format
                    return mapOf(
                        "hasAttributes" to true,
                        "sampleRate" to (audioFormat?.sampleRate ?: 0),
                        "encoding" to (audioFormat?.encoding ?: 0),
                        "channelMask" to (audioFormat?.channelMask ?: 0),
                        "bitPerfect" to (current.mixerBehavior == android.media.AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT)
                    )
                }
            } catch (e: Exception) {
                return mapOf("hasAttributes" to false, "error" to (e.message ?: ""))
            }
        }
        return mapOf("hasAttributes" to false, "apiSupported" to (Build.VERSION.SDK_INT >= 34))
    }

    fun cleanup() {
        unregisterUsbCallback()
        clearUsbRouting()
    }


    private fun ensureAudioManager() {
        if (audioManager == null) {
            audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        }
    }

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

    private fun unregisterUsbCallback() {
        if (!usbCallbackRegistered) return
        try {
            audioManager?.unregisterAudioDeviceCallback(usbDeviceCallback)
            usbCallbackRegistered = false
            android.util.Log.i("HiResAudio", "USB device callback unregistered")
        } catch (_: Exception) {}
    }
}
