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
        @JvmStatic private external fun nativeWritePcm24StaticImpl(
            ptr: Long, buffer: ByteArray, numFrames: Int
        ): Int
        @JvmStatic private external fun nativeIsActiveStaticImpl(ptr: Long): Boolean

        /** Tag for static companion logging. */
        private const val STATIC_TAG = "UsbDacPlugin.Static"

        fun nativeWritePcmFloatStatic(ptr: Long, buffer: FloatArray, numFrames: Int): Int {
            val totalSamples = buffer.size
            val totalBytes = totalSamples * 4  // 4 bytes per float
            Log.i(STATIC_TAG, "[JNI-AUDIO] path=FLOAT samples=$totalSamples bytes=$totalBytes numFrames=$numFrames")
            Log.i(STATIC_TAG, "USB_WRITE_ENTER: ptr=0x${ptr.toString(16)}, frames=$numFrames, samples=${buffer.size}")
            val written = nativeWritePcmFloatStaticImpl(ptr, buffer, numFrames)
            Log.i(STATIC_TAG, "USB_WRITE_EXIT: written=$written frames")
            if (written < 0) {
                Log.e(STATIC_TAG, "nativeWritePcmFloatStatic ERROR=$written " +
                        "(ptr=0x${ptr.toString(16)}, frames=$numFrames, bufSize=${buffer.size})")
            }
            return written
        }

        fun nativeWritePcmI16Static(ptr: Long, buffer: ShortArray, numFrames: Int): Int {
            val totalSamples = buffer.size
            val totalBytes = totalSamples * 2  // 2 bytes per short
            Log.i(STATIC_TAG, "[JNI-AUDIO] path=PCM16 samples=$totalSamples bytes=$totalBytes numFrames=$numFrames")
            Log.i(STATIC_TAG, "USB_WRITE_ENTER: ptr=0x${ptr.toString(16)}, frames=$numFrames, samples=${buffer.size}")
            val written = nativeWritePcmI16StaticImpl(ptr, buffer, numFrames)
            Log.i(STATIC_TAG, "USB_WRITE_EXIT: written=$written frames")
            if (written < 0) {
                Log.e(STATIC_TAG, "nativeWritePcmI16Static ERROR=$written " +
                        "(ptr=0x${ptr.toString(16)}, frames=$numFrames, bufSize=${buffer.size})")
            }
            return written
        }

        fun nativeWritePcm24Static(ptr: Long, buffer: ByteArray, numFrames: Int): Int {
            val totalBytes = buffer.size
            val totalSamples = totalBytes / 3  // 3 bytes per 24-bit sample
            Log.i(STATIC_TAG, "[JNI-AUDIO] path=PCM24 samples=$totalSamples bytes=$totalBytes numFrames=$numFrames")
            Log.i(STATIC_TAG, "USB_WRITE24_ENTER: ptr=0x${ptr.toString(16)}, frames=$numFrames, bytes=${buffer.size}")
            val written = nativeWritePcm24StaticImpl(ptr, buffer, numFrames)
            Log.i(STATIC_TAG, "USB_WRITE24_EXIT: written=$written frames")
            if (written < 0) {
                Log.e(STATIC_TAG, "nativeWritePcm24Static ERROR=$written " +
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
            val inst = instance
            val active = if (ptr != 0L) (inst?.nativeIsActive(ptr) ?: false) else false
            val reason = when {
                ptr == 0L -> "LIBUSB_DRIVER_NOT_INITIALIZED"
                !active -> "LIBUSB_DRIVER_NOT_STREAMING"
                else -> "LIBUSB_READY"
            }
            android.util.Log.i(STATIC_TAG, "[LIBUSB] driverConnected=${ptr != 0L}, " +
                    "driverReady=${ptr != 0L}, " +
                    "driverStreamingCapable=$active, " +
                    "reasonLibusbDisabled=$reason")
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

    /**
     * Pending MethodChannel result for [requestPermission].
     * Stored when the Dart side requests USB permission, then resolved
     * when the broadcast receiver fires (user taps Allow/Deny).
     * This makes the Dart await block until the user actually responds.
     */
    private var pendingPermissionResult: Result? = null
    private var pendingPermissionDeviceId: Int = -1

    // ── Broadcast Receivers ──

    /** Receiver for USB permission grants/denials. */
    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action ?: "null"
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            val receivedDevice: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)

            Log.i(TAG, "[USB] onReceive() entered")
            Log.i(TAG, "[USB]   PendingIntent action sent=ACTION_USB_PERMISSION")
            Log.i(TAG, "[USB]   PendingIntent action received=$action")
            Log.i(TAG, "[USB]   EXTRA_PERMISSION_GRANTED=$granted")
            val receivedDeviceId = receivedDevice?.deviceId ?: -1
            val receivedVendorId = receivedDevice?.vendorId ?: 0
            val receivedProductId = receivedDevice?.productId ?: 0
            val receivedProductName = receivedDevice?.productName ?: "null"
            Log.i(TAG, "[USB]   EXTRA_DEVICE=$receivedProductName (deviceId=$receivedDeviceId, VID=0x${receivedVendorId.toString(16)}, PID=0x${receivedProductId.toString(16)})")

            if (receivedDevice != null) {
                val deviceName = receivedDevice.productName ?: "Unknown"
                val hasPerm = usbManager?.hasPermission(receivedDevice) ?: false

                Log.i(TAG, "[USB] Permission callback received — device non-null")
                Log.i(TAG, "[USB]   Device: $deviceName (VID=0x${receivedDevice.vendorId.toString(16)}, PID=0x${receivedDevice.productId.toString(16)}, deviceId=${receivedDevice.deviceId})")
                Log.i(TAG, "[USB]   EXTRA_PERMISSION_GRANTED=$granted")
                Log.i(TAG, "[USB]   hasPermission(device)=$hasPerm")

                if (granted) {
                    Log.i(TAG, "[USB] Permission GRANTED for: $deviceName")
                    // IMPORTANT: Jangan panggil connectToDevice() + nativeStartDriver() di sini!
                    // libusb driver akan meng-claim USB interface, yang mencegah
                    // decent-player UsbAudioSink mengakses device yang sama.
                    // Cukup resolve permission — biarkan decent-player yang handle koneksi USB.
                    channel?.invokeMethod("onPermissionResult", mapOf(
                        "deviceId" to receivedDevice.deviceId,
                        "deviceName" to deviceName,
                        "vendorId" to receivedDevice.vendorId,
                        "productId" to receivedDevice.productId,
                        "granted" to true,
                        "hasPermission" to hasPerm
                    ))
                    Log.i(TAG, "[USB] Re-scanning device list after permission grant...")
                    refreshDeviceList()
                    safeResolvePermissionResult(true)
                } else {
                    channel?.invokeMethod("onPermissionResult", mapOf(
                        "deviceId" to receivedDevice.deviceId,
                        "deviceName" to deviceName,
                        "vendorId" to receivedDevice.vendorId,
                        "productId" to receivedDevice.productId,
                        "granted" to false,
                        "hasPermission" to hasPerm
                    ))
                    Log.w(TAG, "[USB] Permission DENIED for: $deviceName")
                    safeResolvePermissionResult(false)
                    channel?.invokeMethod("onError", mapOf(
                        "message" to "USB permission denied for $deviceName"
                    ))
                }
            } else {
                Log.w(TAG, "[USB] Permission callback received — EXTRA_DEVICE is NULL")
                Log.w(TAG, "[USB]   PendingIntent FLAG was: MUTABLE (allows system to attach extras)")
                Log.w(TAG, "[USB]   Attempting fallback: checking device list for matching pending request...")
                val lastRequestedDeviceId = pendingPermissionDeviceId
                if (lastRequestedDeviceId >= 0) {
                    val fallbackDevice = usbManager?.deviceList?.values?.firstOrNull { it.deviceId == lastRequestedDeviceId }
                    if (fallbackDevice != null) {
                        Log.i(TAG, "[USB]   Fallback device found: ${fallbackDevice.productName} (deviceId=${fallbackDevice.deviceId})")
                        if (granted) {
                            Log.i(TAG, "[USB]   Fallback: treating as GRANTED")
                            // Jangan panggil connectToDevice() + nativeStartDriver() —
                            // decent-player UsbAudioSink yang akan handle USB connection.
                            channel?.invokeMethod("onPermissionResult", mapOf(
                                "deviceId" to fallbackDevice.deviceId,
                                "deviceName" to (fallbackDevice.productName ?: "USB DAC"),
                                "vendorId" to fallbackDevice.vendorId,
                                "productId" to fallbackDevice.productId,
                                "granted" to true,
                                "hasPermission" to true
                            ))
                            refreshDeviceList()
                            safeResolvePermissionResult(true)
                        } else {
                            Log.w(TAG, "[USB]   Fallback: treating as DENIED")
                            channel?.invokeMethod("onPermissionResult", mapOf(
                                "deviceId" to fallbackDevice.deviceId,
                                "deviceName" to (fallbackDevice.productName ?: "USB DAC"),
                                "vendorId" to fallbackDevice.vendorId,
                                "productId" to fallbackDevice.productId,
                                "granted" to false,
                                "hasPermission" to false
                            ))
                            safeResolvePermissionResult(false)
                            channel?.invokeMethod("onError", mapOf(
                                "message" to "USB permission denied (fallback) for device #$lastRequestedDeviceId"
                            ))
                        }
                    } else {
                        Log.e(TAG, "[USB]   Fallback: deviceId=$lastRequestedDeviceId not found in device list")
                        safeResolvePermissionResult(false)
                    }
                } else {
                    Log.e(TAG, "[USB]   No pending request tracked — cannot resolve")
                    safeResolvePermissionResult(false)
                }
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

        // ── Register USB Permission Receiver ──
        // IMPORTANT: Uses RECEIVER_EXPORTED because UsbManager.requestPermission()
        // fires the PendingIntent from the SYSTEM process. On Android 14+,
        // RECEIVER_NOT_EXPORTED would BLOCK broadcasts from system-server,
        // preventing the USB permission callback from ever being received.
        val permissionFilter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= 34) {
            context.registerReceiver(usbPermissionReceiver, permissionFilter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(usbPermissionReceiver, permissionFilter)
        }
        Log.i(TAG, "[USB] Permission receiver registered (exported) — action=$ACTION_USB_PERMISSION")

        // ── Register Hotplug Receivers ──
        // Also RECEIVER_EXPORTED because USB attach/detach broadcasts come from the system.
        val hotplugFilter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            context.registerReceiver(usbHotplugReceiver, hotplugFilter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(usbHotplugReceiver, hotplugFilter)
        }
        Log.i(TAG, "[USB] Hotplug receiver registered (exported)")
    }

    /** Called when a USB device is plugged in. Scans for audio DACs and notifies Dart. */
    private fun handleDeviceAttached() {
        val audioDevices = findUsbAudioDevices()
        Log.i(TAG, "[USB] Device attached — found ${audioDevices.size} USB audio device(s)")

        // Log detailed debug info for each device found
        for (dev in audioDevices) {
            val hasPerm = usbManager?.hasPermission(dev) ?: false
            val serialDesc = if (hasPerm) {
                try { dev.serialNumber } catch (_: SecurityException) { "<denied>" }
            } else {
                "<no permission>"
            }
            Log.i(TAG, "[USB]   Device #${dev.deviceId}: ${dev.productName}" +
                    " (VID=0x${dev.vendorId.toString(16)}, PID=0x${dev.productId.toString(16)}" +
                    ", hasPermission=$hasPerm, serial=$serialDesc)")
        }

        // Notify Dart with the new device list — Dart side handles
        // permission requesting via UsbDacAudioManager (when user enables
        // USB DAC Routing in settings). We no longer auto-request permission
        // here to avoid racing with the Dart-side flow.
        channel?.invokeMethod("onDeviceAttached", mapOf(
            "devices" to audioDevices.map { serializeDevice(it) }
        ))

        // Note: Auto-reconnect is handled by UsbDacAudioManager on the Dart side.
        // The Kotlin side only handles the hardware event notification.
    }

    /**
     * Re-scan all USB audio devices and push the updated list to Dart.
     * Used after permission is granted so that device metadata (e.g., serialNumber)
     * is refreshed with full permission access.
     */
    private fun refreshDeviceList() {
        val audioDevices = findUsbAudioDevices()
        Log.i(TAG, "[USB] Device list refreshed: ${audioDevices.size} audio device(s)")
        channel?.invokeMethod("onDeviceListRefreshed", mapOf(
            "devices" to audioDevices.map { serializeDevice(it) }
        ))
    }

    /** Called when a USB device is unplugged. */
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
     *
     * Checks [UsbManager.hasPermission] before attempting to read
     * [UsbDevice.serialNumber] — on Android 14+, reading serialNumber
     * without permission throws SecurityException. If permission is not
     * granted yet, the serialNumber field is set to "" (empty).
     */
    private fun serializeDevice(device: UsbDevice): Map<String, Any?> {
        val hasPermission = usbManager?.hasPermission(device) ?: false

        Log.d(TAG, "[USB] serializeDevice start: #${device.deviceId} ${device.productName}" +
                " (VID=0x${device.vendorId.toString(16)}, PID=0x${device.productId.toString(16)}" +
                ", hasPermission=$hasPermission)")

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

        // Serial number requires USB permission.
        // Check hasPermission first — if not granted, skip gracefully.
        val serialNumber: String
        if (hasPermission) {
            serialNumber = try {
                device.serialNumber ?: ""
            } catch (e: SecurityException) {
                Log.d(TAG, "[USB] serializeDevice: serialNumber access threw SecurityException despite hasPermission=true: ${e.message}")
                ""
            }
            Log.d(TAG, "[USB] serializeDevice success: serialNumber='$serialNumber'")
        } else {
            Log.d(TAG, "[USB] serializeDevice: no permission yet — serialNumber left empty")
            serialNumber = ""
        }

        Log.d(TAG, "[USB] serializeDevice complete: #${device.deviceId} ${device.productName}")

        return mapOf(
            "deviceId" to device.deviceId,
            "productName" to (device.productName ?: "USB Audio Device"),
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "deviceProtocol" to device.deviceProtocol,
            "serialNumber" to serialNumber,
            "hasPermission" to hasPermission,
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
            val connection = usbManager?.openDevice(device)
            Log.i(TAG, "[USB-DRIVER]   openDevice returned: connection=${connection != null}")
            if (connection == null) {
                Log.e(TAG, "[USB-DRIVER] ✗ openDevice FAILED — null connection")
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
            Log.i(TAG, "[USB-DRIVER] === connectToDevice: destroy old driver ===")

            // Initialize native driver with the USB device FD
            destroyNativeDriver()
            Log.i(TAG, "[USB-DRIVER] === connectToDevice: STEP 1/2 — nativeCreateDriver() ===")
            val ptr = nativeCreateDriver()
            Log.i(TAG, "[USB-DRIVER]   nativeCreateDriver returned: ptr=0x${ptr.toString(16)}")
            if (ptr != 0L) {
                Log.i(TAG, "[USB-DRIVER] === connectToDevice: STEP 2/2 — nativeInitDriver(fd=$fd, " +
                        "sr=$sampleRate, ch=$channelCount, bits=$bitsPerSample) ===")
                val inited = nativeInitDriver(ptr, fd, sampleRate, channelCount, bitsPerSample)
                Log.i(TAG, "[USB-DRIVER]   nativeInitDriver returned: $inited")
                if (inited) {
                    nativeDriverPtr = ptr
                    Log.i(TAG, "[USB-DRIVER] ✓ USB DAC driver created and initialized successfully")
                    Log.i(TAG, "USB DAC connected: ${device.productName} " +
                            "(${sampleRate}Hz, ${channelCount}ch, ${bitsPerSample}bit)")

                    channel?.invokeMethod("onDeviceConnected", mapOf(
                        "deviceName" to (device.productName ?: "USB DAC"),
                        "sampleRate" to sampleRate,
                        "channelCount" to channelCount,
                        "bitDepth" to bitsPerSample
                    ))
                } else {
                    Log.e(TAG, "[USB-DRIVER] ✗ nativeInitDriver FAILED — driver not created")
                    nativeDestroyDriver(ptr)
                    connection.close()
                }
            } else {
                Log.e(TAG, "[USB-DRIVER] ✗ nativeCreateDriver returned 0 — driver not created")
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

    /**
     * Safely resolve the pending permission [Result].
     * Catches [IllegalStateException] in case the result was already resolved
     * (e.g., by a previous broadcast receiver firing, or Dart timeout).
     */
    private fun safeResolvePermissionResult(granted: Boolean) {
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        pendingPermissionDeviceId = -1
        try {
            result.success(granted)
        } catch (e: IllegalStateException) {
            // MethodChannel Result already resolved (e.g. Dart timed out)
            Log.w(TAG, "safeResolvePermissionResult: already resolved ($granted): ${e.message}")
        }
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

                Log.i(TAG, "[USB] requestPermission called for deviceId=$deviceId")

                if (targetDevice != null) {
                    val hasPerm = usbManager?.hasPermission(targetDevice) ?: false
                    Log.i(TAG, "[USB]   Target: ${targetDevice.productName} (VID=0x${targetDevice.vendorId.toString(16)}, PID=0x${targetDevice.productId.toString(16)})")
                    Log.i(TAG, "[USB]   hasPermission(device)=$hasPerm")

                    if (hasPerm) {
                        // Permission already granted — resolve immediately without dialog
                        // JANGAN panggil connectToDevice() + nativeStartDriver()!
                        // Biarkan decent-player UsbAudioSink yang handle USB connection.
                        Log.i(TAG, "[USB]   Permission already granted — resolving immediately (skipping libusb connect)")
                        refreshDeviceList()
                        result.success(true)
                    } else {
                        // Clear any stale pending result (safe: catches if already resolved)
                        safeResolvePermissionResult(false)
                        // Store the new result — will be resolved when broadcast receiver fires
                        pendingPermissionResult = result
                        pendingPermissionDeviceId = deviceId

                        // Request permission via explicit PendingIntent (Android 14+ requirement)
                        val permissionIntent = Intent(ACTION_USB_PERMISSION).apply {
                            `package` = context.packageName
                        }
                        val pendingPermissionIntent = PendingIntent.getBroadcast(
                            context,
                            0,
                            permissionIntent,
                            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                        )
                        usbManager?.requestPermission(targetDevice, pendingPermissionIntent)
                        Log.i(TAG, "[USB]   Permission request sent via PendingIntent — awaiting user response")
                        // ⚠️ result.success() is NOT called here!
                        // The MethodChannel call stays pending until the broadcast receiver
                        // fires (user taps Allow/Deny). This eliminates the race condition
                        // where Dart called connect() before the user responded.
                    }
                } else {
                    Log.e(TAG, "[USB]   Device #$deviceId not found in device list")
                    result.error("DEVICE_NOT_FOUND", "USB audio device not found", null)
                }
            }
            "hasPermission" -> {
                val deviceId = call.argument<Int>("deviceId") ?: -1
                val devices = usbManager?.deviceList?.values ?: emptyList()
                val targetDevice = devices.firstOrNull { it.deviceId == deviceId }
                if (targetDevice != null) {
                    val hasPerm = usbManager?.hasPermission(targetDevice) ?: false
                    Log.d(TAG, "[USB] hasPermission(deviceId=$deviceId) = $hasPerm")
                    result.success(hasPerm)
                } else {
                    result.success(false)
                }
            }
            "connect" -> {
                val deviceId = call.argument<Int>("deviceId") ?: -1
                val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                val channelCount = call.argument<Int>("channels") ?: 2
                val devices = usbManager?.deviceList?.values ?: emptyList()
                val targetDevice = devices.firstOrNull { it.deviceId == deviceId }
                if (targetDevice != null) {
                    try {
                        connectToDevice(targetDevice, sampleRate, channelCount, 16) // forced 16-bit for PCM16 isolation test
                        result.success(true)
                    } catch (e: SecurityException) {
                        Log.e(TAG, "connect: SecurityException — permission not granted: ${e.message}")
                        result.error("PERMISSION_DENIED", "USB permission not granted", null)
                    } catch (e: Exception) {
                        Log.e(TAG, "connect: unexpected error: ${e.message}")
                        result.error("CONNECT_FAILED", "Failed to connect: ${e.message}", null)
                    }
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
                Log.i(TAG, "[USB-STREAM] nativeStart() called from method channel 'start'")
                if (nativeDriverPtr != 0L) {
                    // Check if already streaming — the broadcast receiver may have already
                    // started the driver after the user granted USB permission.
                    // nativeStartDriver() returns false if called on an already-running driver,
                    // which would make Dart think startup failed and never route audio to libusb.
                    if (nativeIsActive(nativeDriverPtr)) {
                        Log.i(TAG, "[USB-STREAM] nativeStart called but already active — returning true")
                        result.success(true)
                    } else {
                        Log.i(TAG, "[USB-STREAM] nativeStartDriver called (from method channel 'start')")
                        val started = nativeStartDriver(nativeDriverPtr)
                        Log.i(TAG, "[USB-STREAM] nativeStartDriver result=$started (from 'start' channel)")
                        if (!started) {
                            Log.e(TAG, "start: nativeStartDriver returned false")
                        }
                        result.success(started)
                    }
                } else {
                    result.error("NOT_CONNECTED", "USB DAC not connected", null)
                }
            }
            "stop" -> {
                Log.i(TAG, "[USB-STREAM] nativeStop() called from method channel 'stop'")
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
                val connected = nativeDriverPtr != 0L
                val active = connected && nativeIsActive(nativeDriverPtr)
                val reason = when {
                    !connected -> "LIBUSB_DRIVER_NOT_INITIALIZED"
                    !active -> "LIBUSB_DRIVER_NOT_STREAMING"
                    else -> "LIBUSB_READY"
                }
                android.util.Log.i(TAG, "[LIBUSB] driverConnected=$connected, " +
                        "driverReady=$connected, " +
                        "driverStreamingCapable=$active, " +
                        "reasonLibusbDisabled=$reason")
                result.success(mapOf(
                    "connected" to connected,
                    "active" to active,
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
            Log.i(TAG, "[USB] Permission receiver unregistered")
        } catch (_: Exception) {}
        try {
            context.unregisterReceiver(usbHotplugReceiver)
            Log.i(TAG, "[USB] Hotplug receiver unregistered")
        } catch (_: Exception) {}
        disconnectDevice()
    }
}
