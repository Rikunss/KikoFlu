package com.meteor.kikoeruflutter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * USB DAC Plugin — Direct USB Audio Class (UAC) output via libusb.
 *
 * Provides bit-perfect audio playback to external USB DACs by:
 * 1. Using Android USB Host API (UsbManager) to enumerate and claim USB audio devices
 * 2. Passing the USB device file descriptor to the native C++ libusb driver via JNI
 * 3. The native driver handles isochronous USB audio streaming, bypassing Android mixer
 *
 * Required permissions:
 * - <uses-feature android:name="android.hardware.usb.host" />
 * - User must grant USB device access via system dialog
 *
 * Channel: com.kikoeru.flutter/usb_dac
 *
 * @see <a href="https://source.android.com/docs/core/audio/usb">Android USB Digital Audio</a>
 */
class UsbDacPlugin(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL = "com.kikoeru.flutter/usb_dac"
        private const val TAG = "UsbDacPlugin"

        /** Custom action for USB permission broadcast (not a standard UsbManager constant). */
        private const val ACTION_USB_PERMISSION = "com.meteor.kikoeruflutter.USB_PERMISSION"

        /** USB Audio Class (UAC) interface class code */
        private const val USB_CLASS_AUDIO = 0x01

        /** USB interface subclass: AUDIO_STREAMING */
        private const val USB_SUBCLASS_AUDIO_STREAMING = 0x02

        @Volatile
        private var instance: UsbDacPlugin? = null

        fun getInstance(context: Context): UsbDacPlugin {
            return instance ?: synchronized(this) {
                instance ?: UsbDacPlugin(context.applicationContext).also { instance = it }
            }
        }

        // ── Static JNI bridges (used by LibusbAudioSink) ──
        @JvmStatic private external fun nativeWritePcmFloatStaticImpl(
            ptr: Long, buffer: FloatArray, numFrames: Int
        ): Int
        @JvmStatic private external fun nativeWritePcmI16StaticImpl(
            ptr: Long, buffer: ShortArray, numFrames: Int
        ): Int
        @JvmStatic private external fun nativeIsActiveStaticImpl(ptr: Long): Boolean

        /** Tag for static companion logging. */
        private const val STATIC_TAG = "UsbDacPlugin.Static"

        fun nativeWritePcmFloatStatic(ptr: Long, buffer: FloatArray, numFrames: Int): Int {
            val written = nativeWritePcmFloatStaticImpl(ptr, buffer, numFrames)
            if (written < 0) {
                Log.e(STATIC_TAG, "nativeWritePcmFloatStatic ERROR=$written " +
                        "(ptr=0x${ptr.toString(16)}, frames=$numFrames, bufSize=${buffer.size})")
            }
            return written
        }

        fun nativeWritePcmI16Static(ptr: Long, buffer: ShortArray, numFrames: Int): Int {
            val written = nativeWritePcmI16StaticImpl(ptr, buffer, numFrames)
            if (written < 0) {
                Log.e(STATIC_TAG, "nativeWritePcmI16Static ERROR=$written " +
                        "(ptr=0x${ptr.toString(16)}, frames=$numFrames, bufSize=${buffer.size})")
            }
            return written
        }

        fun nativeIsActiveStatic(ptr: Long): Boolean {
            val active = nativeIsActiveStaticImpl(ptr)
            Log.v(STATIC_TAG, "nativeIsActiveStatic(ptr=0x${ptr.toString(16)}) = $active")
            return active
        }

        /**
         * Get the current native libusb driver pointer (0 if not connected).
         * Used by [LibusbAudioSink] to write PCM data directly to libusb.
         */
        @JvmStatic
        fun getCurrentDriverPtr(): Long {
            val ptr = instance?.nativeDriverPtr ?: 0L
            Log.v(STATIC_TAG, "getCurrentDriverPtr() = 0x${ptr.toString(16)}")
            return ptr
        }
    }

    // ── Native JNI methods (implemented in usb_dac_driver.cpp) ──
    private external fun nativeCreateDriver(): Long
    private external fun nativeInitDriver(
        nativePtr: Long, deviceFd: Int,
        sampleRate: Int, channelCount: Int, bitsPerSample: Int
    ): Boolean
    private external fun nativeStartDriver(nativePtr: Long): Boolean
    private external fun nativeStopDriver(nativePtr: Long)
    private external fun nativeDestroyDriver(nativePtr: Long)
    private external fun nativeWritePcmFloat(
        nativePtr: Long, buffer: FloatArray, numFrames: Int
    ): Int
    private external fun nativeWritePcmI16(
        nativePtr: Long, buffer: ShortArray, numFrames: Int
    ): Int
    private external fun nativeIsActive(nativePtr: Long): Boolean

    // ── State ──
    private var usbManager: UsbManager? = null
    private var nativeDriverPtr: Long = 0L
    private var channel: MethodChannel? = null
    private var claimedDevice: UsbDevice? = null
    private var usbConnection: UsbDeviceConnection? = null

    // ── Broadcast Receivers ──

    /** Receiver for USB permission grants/denials. */
    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)

            if (device != null && granted) {
                Log.i(TAG, "USB permission granted for: ${device.productName}")
                connectToDevice(device)
            } else if (device != null) {
                Log.w(TAG, "USB permission denied for: ${device.productName}")
                channel?.invokeMethod("onError", mapOf(
                    "message" to "USB permission denied for ${device.productName}"
                ))
            }
        }
    }

    /**
     * Receiver for USB device attach/detach events.
     * Fires when any USB device is plugged in or unplugged.
     */
    private val usbHotplugReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    Log.i(TAG, "USB device attached — scanning for audio devices")
                    handleDeviceAttached()
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    val deviceName = device?.productName ?: "Unknown"
                    Log.i(TAG, "USB device detached: $deviceName")
                    handleDeviceDetached()
                }
            }
        }
    }

    fun attachChannel(methodChannel: MethodChannel) {
        this.channel = methodChannel
        usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

        // Register permission receiver
        val permissionFilter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= 34) {
            context.registerReceiver(usbPermissionReceiver, permissionFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(usbPermissionReceiver, permissionFilter)
        }

        // Register hotplug receivers for auto-reconnect
        val hotplugFilter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            context.registerReceiver(usbHotplugReceiver, hotplugFilter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(usbHotplugReceiver, hotplugFilter)
        }
    }

    /** Called when a USB device is plugged in. Scans for audio DACs and notifies Dart. */
    private fun handleDeviceAttached() {
        val audioDevices = findUsbAudioDevices()
        Log.i(TAG, "Found ${audioDevices.size} USB audio device(s) after attach")

        // Notify Dart with the new device list
        channel?.invokeMethod("onDeviceAttached", mapOf(
            "devices" to audioDevices.map { serializeDevice(it) }
        ))

        // If we had a device before, auto-reconnect
        if (audioDevices.isNotEmpty() && claimedDevice == null) {
            Log.i(TAG, "No currently claimed device — attempting auto-connect to ${audioDevices.first().productName}")
            // Auto-request permission for the first audio device
            requestPermissionForDevice(audioDevices.first())
        }
    }

    /** Called when a USB device is detached. */
    private fun handleDeviceDetached() {
        // If this was our claimed device, clean up and notify
        if (claimedDevice != null) {
            Log.i(TAG, "Claimed device was detached — cleaning up")
            // Single call with canReconnect=true (disconnectDevice fires onDeviceDisconnected)
            disconnectDevice(canReconnect = true)
        } else {
            // Just notify Dart about the device list change
            val audioDevices = findUsbAudioDevices()
            channel?.invokeMethod("onDeviceAttached", mapOf(
                "devices" to audioDevices.map { serializeDevice(it) }
            ))
        }
    }

    private fun requestPermissionForDevice(device: UsbDevice) {
        val permissionIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_USB_PERMISSION),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        usbManager?.requestPermission(device, permissionIntent)
    }

    /**
     * Load the native libusb library.
     * Called once during plugin initialization.
     */
    fun loadNativeLibrary(): Boolean {
        return try {
            System.loadLibrary("usb_dac_driver")
            Log.i(TAG, "Native usb_dac_driver library loaded")
            true
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "Failed to load native library: ${e.message}")
            false
        }
    }

    /**
     * Find all connected USB audio devices (USB Audio Class).
     */
    private fun findUsbAudioDevices(): List<UsbDevice> {
        val usbManager = usbManager ?: return emptyList()
        val devices = usbManager.deviceList?.values?.filter { device ->
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                if (iface.interfaceClass == USB_CLASS_AUDIO) {
                    return@filter true
                }
            }
            false
        } ?: emptyList()
        return devices
    }

    /**
     * Serialize a USB device to a map for Dart.
     */
    private fun serializeDevice(device: UsbDevice): Map<String, Any?> {
        val audioInterface = (0 until device.interfaceCount)
            .map { device.getInterface(it) }
            .firstOrNull { it.interfaceClass == USB_CLASS_AUDIO }

        val endpoints = audioInterface?.let { iface ->
            (0 until iface.endpointCount).map { ep ->
                mapOf(
                    "address" to iface.getEndpoint(ep).address,
                    "type" to iface.getEndpoint(ep).type,
                    "maxPacketSize" to iface.getEndpoint(ep).maxPacketSize
                )
            }
        } ?: emptyList<Map<String, Any?>>()

        // Serial number requires USB permission — catch SecurityException gracefully.
        // On Android 14+, accessing serialNumber without permission throws
        // SecurityException even just for listing devices.
        val serialNumber = try {
            device.serialNumber ?: ""
        } catch (e: SecurityException) {
            Log.w(TAG, "serializeDevice: cannot read serialNumber (no USB permission): ${e.message}")
            ""
        }

        return mapOf(
            "deviceId" to device.deviceId,
            "productName" to (device.productName ?: "USB Audio Device"),
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "deviceProtocol" to device.deviceProtocol,
            "serialNumber" to serialNumber,
            "audioEndpoints" to endpoints
        )
    }

    /**
     * Connect to a USB audio device and initialize the native driver.
     * This claims the USB interface and passes the FD to the C++ driver.
     */
    private fun connectToDevice(device: UsbDevice, sampleRate: Int = 48000,
                                 channelCount: Int = 2, bitsPerSample: Int = 16) {
        // Guard against duplicate connection attempts.
        // The permission receiver (usbPermissionReceiver) may have already
        // created the driver. Return early to avoid re-opening the device.
        if (nativeDriverPtr != 0L) {
            Log.w(TAG, "connectToDevice called but already connected (ptr=0x${nativeDriverPtr.toString(16)}) — returning early")
            channel?.invokeMethod("onDeviceConnected", mapOf(
                "deviceName" to (device.productName ?: "USB DAC"),
                "sampleRate" to sampleRate,
                "channelCount" to channelCount,
                "bitDepth" to bitsPerSample
            ))
            return
        }

        try {
            val connection = usbManager?.openDevice(device) ?: run {
                Log.e(TAG, "Failed to open USB device")
                channel?.invokeMethod("onError", mapOf(
                    "message" to "Failed to open USB device"
                ))
                return
            }

            // Find the audio streaming interface
            val audioInterface = (0 until device.interfaceCount)
                .map { device.getInterface(it) }
                .firstOrNull {
                    it.interfaceClass == USB_CLASS_AUDIO &&
                    it.interfaceSubclass == USB_SUBCLASS_AUDIO_STREAMING
                } ?: run {
                // Try any audio interface
                (0 until device.interfaceCount)
                    .map { device.getInterface(it) }
                    .firstOrNull { it.interfaceClass == USB_CLASS_AUDIO }
            }

            if (audioInterface == null) {
                Log.e(TAG, "No audio interface found on USB device")
                connection.close()
                return
            }

            // Claim the interface (required for isochronous transfer)
            val claimed = connection.claimInterface(audioInterface, true)
            if (!claimed) {
                Log.e(TAG, "Failed to claim USB audio interface")
                connection.close()
                return
            }

            claimedDevice = device
            usbConnection = connection

            // Get the file descriptor from the connection
            val fd = connection.fileDescriptor

            // Initialize native driver with the USB device FD
            destroyNativeDriver()
            val ptr = nativeCreateDriver()
            if (ptr != 0L) {
                val inited = nativeInitDriver(ptr, fd, sampleRate, channelCount, bitsPerSample)
                if (inited) {
                    nativeDriverPtr = ptr
                    Log.i(TAG, "USB DAC connected: ${device.productName} " +
                            "(${sampleRate}Hz, ${channelCount}ch, ${bitsPerSample}bit)")

                    channel?.invokeMethod("onDeviceConnected", mapOf(
                        "deviceName" to (device.productName ?: "USB DAC"),
                        "sampleRate" to sampleRate,
                        "channelCount" to channelCount,
                        "bitDepth" to bitsPerSample
                    ))
                } else {
                    Log.e(TAG, "Failed to init native driver")
                    nativeDestroyDriver(ptr)
                    connection.close()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "USB connection error: ${e.message}")
            channel?.invokeMethod("onError", mapOf(
                "message" to "USB connection failed: ${e.message}"
            ))
        }
    }

    /**
     * Disconnect from the USB DAC and release resources.
     *
     * @param canReconnect Whether the system should attempt auto-reconnection.
     *                     Pass `true` when the device was unplugged but may be
     *                     plugged back in (e.g., ACTION_USB_DEVICE_DETACHED).
     *                     Pass `false` when the user explicitly disconnected.
     */
    private fun disconnectDevice(canReconnect: Boolean = false) {
        destroyNativeDriver()
        try {
            usbConnection?.close()
        } catch (_: Exception) {}

        // Capture device info BEFORE nulling references
        val name = claimedDevice?.productName ?: "USB DAC"
        val id = claimedDevice?.deviceId ?: 0
        claimedDevice = null
        usbConnection = null

        channel?.invokeMethod("onDeviceDisconnected", mapOf(
            "deviceName" to name,
            "deviceId" to id,
            "canReconnect" to canReconnect
        ))
        Log.i(TAG, "USB DAC disconnected (canReconnect=$canReconnect)")
    }

    private fun destroyNativeDriver() {
        if (nativeDriverPtr != 0L) {
            nativeStopDriver(nativeDriverPtr)
            nativeDestroyDriver(nativeDriverPtr)
            nativeDriverPtr = 0L
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> {
                // USB Host API requires Android 3.1+ (API 12+), which is always available
                result.success(true)
            }
            "getDevices" -> {
                val devices = findUsbAudioDevices()
                result.success(devices.map { serializeDevice(it) })
            }
            "requestPermission" -> {
                val deviceId = call.argument<Int>("deviceId") ?: -1
                val devices = usbManager?.deviceList?.values ?: emptyList()
                val targetDevice = devices.firstOrNull { it.deviceId == deviceId }
                if (targetDevice != null) {
                    // Request permission using PendingIntent — result arrives via broadcast receiver
                    val permissionIntent = PendingIntent.getBroadcast(
                        context,
                        0,
                        Intent(ACTION_USB_PERMISSION),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                    usbManager?.requestPermission(targetDevice, permissionIntent)
                    result.success(true)
                } else {
                    result.error("DEVICE_NOT_FOUND", "USB audio device not found", null)
                }
            }
            "connect" -> {
                val deviceId = call.argument<Int>("deviceId") ?: -1
                val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                val channelCount = call.argument<Int>("channels") ?: 2
                val bitDepth = call.argument<Int>("bitDepth") ?: 16

                val devices = usbManager?.deviceList?.values ?: emptyList()
                val targetDevice = devices.firstOrNull { it.deviceId == deviceId }
                if (targetDevice != null) {
                    connectToDevice(targetDevice, sampleRate, channelCount, bitDepth)
                    result.success(true)
                } else {
                    result.error("DEVICE_NOT_FOUND", "USB audio device not found", null)
                }
            }
            "disconnect" -> {
                disconnectDevice()
                result.success(true)
            }
            "isConnected" -> {
                result.success(nativeDriverPtr != 0L)
            }
            "start" -> {
                if (nativeDriverPtr != 0L) {
                    val started = nativeStartDriver(nativeDriverPtr)
                    result.success(started)
                } else {
                    result.error("NOT_CONNECTED", "USB DAC not connected", null)
                }
            }
            "stop" -> {
                if (nativeDriverPtr != 0L) {
                    nativeStopDriver(nativeDriverPtr)
                }
                result.success(true)
            }
            "writePcmFloat" -> {
                val buffer = call.argument<FloatArray>("buffer") ?: floatArrayOf()
                val numFrames = call.argument<Int>("numFrames") ?: 0
                if (nativeDriverPtr != 0L && buffer.isNotEmpty() && numFrames > 0) {
                    val written = nativeWritePcmFloat(nativeDriverPtr, buffer, numFrames)
                    result.success(written)
                } else {
                    result.success(0)
                }
            }
            "writePcmI16" -> {
                val buffer = call.argument<ShortArray>("buffer") ?: shortArrayOf()
                val numFrames = call.argument<Int>("numFrames") ?: 0
                if (nativeDriverPtr != 0L && buffer.isNotEmpty() && numFrames > 0) {
                    val written = nativeWritePcmI16(nativeDriverPtr, buffer, numFrames)
                    result.success(written)
                } else {
                    result.success(0)
                }
            }
            "getStatus" -> {
                result.success(mapOf(
                    "connected" to (nativeDriverPtr != 0L),
                    "active" to (nativeDriverPtr != 0L && nativeIsActive(nativeDriverPtr)),
                    "deviceName" to (claimedDevice?.productName ?: "")
                ))
            }
            "release" -> {
                disconnectDevice()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Clean up resources when the plugin is destroyed.
     */
    fun cleanup() {
        try {
            context.unregisterReceiver(usbPermissionReceiver)
        } catch (_: Exception) {}
        try {
            context.unregisterReceiver(usbHotplugReceiver)
        } catch (_: Exception) {}
        disconnectDevice()
    }
}
