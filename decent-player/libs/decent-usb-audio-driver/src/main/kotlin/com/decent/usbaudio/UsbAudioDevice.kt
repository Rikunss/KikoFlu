package com.decent.usbaudio

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


/**
 * Manages the lifecycle of a USB Audio Class device for bit-perfect output.
 *
 * Responsibilities:
 * - Discover connected USB audio devices
 * - Request user permission via [UsbManager.requestPermission]
 * - Open the device and extract endpoint/interface info
 * - Provide the file descriptor and endpoint addresses to [UsbAudioStream]
 *
 * This class does NOT perform audio I/O — that's handled by the native layer
 * via [UsbAudioStream].
 *
 * @author DecentPlayer project
 */
class UsbAudioDevice private constructor(private val context: Context) {

    private var usbManager: UsbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private var connection: UsbDeviceConnection? = null
    private var currentDevice: UsbDevice? = null
    private var claimedInterface: UsbInterface? = null

    companion object {
        private const val TAG = "UsbAudioDevice"
        private const val ACTION_USB_PERMISSION_SUFFIX = ".USB_AUDIO_PERMISSION"

        @Volatile
        private var instance: UsbAudioDevice? = null

        /**
         * Get the singleton instance. All callers share the same connection
         * share the same connection and fd, preventing ENODEV from competing opens.
         */
        fun getInstance(context: Context): UsbAudioDevice {
            return instance ?: synchronized(this) {
                instance ?: UsbAudioDevice(context.applicationContext).also { instance = it }
            }
        }
    }


    /**
     * Find the first connected USB audio output device.
     *
     * Scans all USB devices for one with an AudioStreaming interface
     * (class=1, subclass=2) that has an isochronous OUT endpoint.
     *
     * @return The USB device, or null if none found.
     */
    fun findUsbAudioDevice(): UsbDevice? {
        for (device in usbManager.deviceList.values) {
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                if (iface.interfaceClass == UsbConstants.USB_CLASS_AUDIO &&
                    iface.interfaceSubclass == 2) {
                    Log.i(TAG, "Found USB audio device: ${device.productName} " +
                            "(vendor=0x${device.vendorId.toString(16)}, " +
                            "product=0x${device.productId.toString(16)})")
                    return device
                }
            }
        }
        Log.d(TAG, "No USB audio device found")
        return null
    }

    /**
     * Check if we already have permission to access the device.
     */
    fun hasPermission(device: UsbDevice): Boolean {
        return usbManager.hasPermission(device)
    }

    /**
     * Request permission from the user to access the USB device.
     *
     * @param device   The USB device to request access for.
     * @param callback Called with true if permission granted, false otherwise.
     */
    fun requestPermission(device: UsbDevice, callback: (Boolean) -> Unit) {
        if (usbManager.hasPermission(device)) {
            Log.i(TAG, "Permission already granted for ${device.productName}")
            callback(true)
            return
        }

        val intent = Intent(context.packageName + ACTION_USB_PERMISSION_SUFFIX)
        intent.setPackage(context.packageName)
        val permissionIntent = PendingIntent.getBroadcast(
                context, 0,
                intent,
                PendingIntent.FLAG_MUTABLE
        )

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action == context.packageName + ACTION_USB_PERMISSION_SUFFIX) {
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    Log.i(TAG, "USB permission result: granted=$granted for ${device.productName}")
                    context.unregisterReceiver(this)
                    callback(granted)
                }
            }
        }

        val filter = IntentFilter(context.packageName + ACTION_USB_PERMISSION_SUFFIX)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }

        usbManager.requestPermission(device, permissionIntent)
        Log.i(TAG, "Permission requested for ${device.productName}")
    }

    /**
     * Open the USB device and extract all information needed for audio I/O.
     *
     * Finds the AudioStreaming interface, locates the isochronous OUT and
     * feedback IN endpoints, and returns everything the native layer needs.
     *
     * @param device The USB audio device to open.
     * @return Device info with fd and endpoint addresses, or null on failure.
     */
    /** Cached device info from the last successful openDevice() call. */
    private var cachedDeviceInfo: UsbAudioDeviceInfo? = null

    fun openDevice(device: UsbDevice): UsbAudioDeviceInfo? {
        if (!usbManager.hasPermission(device)) {
            Log.e(TAG, "Cannot open device ${device.productName}: USB permission not granted")
            return null
        }
        val cached = cachedDeviceInfo
        if (cached != null && connection != null) {
            Log.i(TAG, "Device already open, reusing fd=${cached.fd}")
            return cached
        }
        closeDevice()
        val conn = usbManager.openDevice(device)
        if (conn == null) {
            Log.e(TAG, "Failed to open device ${device.productName}")
            return null
        }

        var streamingInterface: UsbInterface? = null
        var endpointOut = -1
        var endpointFeedback = -1
        var maxPacketSize = 0
        var altSettingCount = 0

        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_AUDIO &&
                iface.interfaceSubclass == 2) {
                altSettingCount++

                if (iface.endpointCount > 0 && streamingInterface == null) {
                    streamingInterface = iface

                    for (e in 0 until iface.endpointCount) {
                        val ep = iface.getEndpoint(e)
                        when {
                            ep.type == UsbConstants.USB_ENDPOINT_XFER_ISOC &&
                                    ep.direction == UsbConstants.USB_DIR_OUT -> {
                                endpointOut = ep.address
                                maxPacketSize = ep.maxPacketSize
                                Log.i(TAG, "Found ISO OUT endpoint: address=0x${ep.address.toString(16)}, " +
                                        "maxPacket=$maxPacketSize, interval=${ep.interval}")
                            }
                            ep.type == UsbConstants.USB_ENDPOINT_XFER_ISOC &&
                                    ep.direction == UsbConstants.USB_DIR_IN -> {
                                endpointFeedback = ep.address
                                Log.i(TAG, "Found ISO IN (feedback) endpoint: address=0x${ep.address.toString(16)}, " +
                                        "interval=${ep.interval}")
                            }
                        }
                    }
                }
            }
        }

        if (streamingInterface == null || endpointOut < 0) {
            Log.e(TAG, "No suitable AudioStreaming interface/endpoint found")
            conn.close()
            return null
        }

        var audioControlInterfaceId = 0
        val controlInterface = (0 until device.interfaceCount)
                .map { device.getInterface(it) }
                .firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_AUDIO && it.interfaceSubclass == 1 }

        if (controlInterface != null) {
            audioControlInterfaceId = controlInterface.id
            val claimed = conn.claimInterface(controlInterface, true)
            Log.i(TAG, "Claimed AudioControl interface ${controlInterface.id} force=true: $claimed")
        }

        val claimed = conn.claimInterface(streamingInterface, true)
        Log.i(TAG, "Claimed AudioStreaming interface ${streamingInterface.id} force=true: $claimed " +
                "(alt=${streamingInterface.alternateSetting}, endpoints=${streamingInterface.endpointCount})")
        if (!claimed) {
            Log.e(TAG, "Failed to claim streaming interface — kernel driver may still be active")
            conn.close()
            return null
        }
        claimedInterface = streamingInterface

        val zeroAlt = (0 until device.interfaceCount)
                .map { device.getInterface(it) }
                .firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_AUDIO &&
                        it.interfaceSubclass == 2 && it.alternateSetting == 0 }
        if (zeroAlt != null) {
            conn.setInterface(zeroAlt)
            Log.i(TAG, "Reset streaming to alt=0 (zero-bandwidth)")
        }
        Thread.sleep(100)

        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_AUDIO && iface.interfaceSubclass == 2) {
                Log.d(TAG, "  AudioStreaming alt=${iface.alternateSetting}: " +
                        "id=${iface.id}, endpoints=${iface.endpointCount}")
            }
        }

        val fd = conn.fileDescriptor
        val interfaceId = streamingInterface.id

        Log.i(TAG, "Device opened: ${device.productName}, fd=$fd, " +
                "iface=$interfaceId, epOut=0x${endpointOut.toString(16)}, " +
                "epFb=0x${endpointFeedback.toString(16)}, " +
                "maxPacket=$maxPacketSize, altSettings=$altSettingCount")

        connection = conn
        currentDevice = device

        val clockSourceId = parseClockSourceId(conn)
        val (bestAlt, bestBits) = parseBestAltSetting(conn)
        Log.i(TAG, "Auto-detected: clockSourceId=0x${clockSourceId.toString(16)}, " +
                "bestAlt=$bestAlt, bestBits=$bestBits")

        dumpRawDescriptors(conn)

        val info = UsbAudioDeviceInfo(
                connection = conn,
                fd = fd,
                deviceName = device.productName ?: "USB Audio Device",
                interfaceId = interfaceId,
                endpointOutAddress = endpointOut,
                endpointFeedbackAddress = endpointFeedback,
                maxPacketSize = maxPacketSize,
                altSettingCount = altSettingCount,
                clockSourceId = clockSourceId,
                bestAltSetting = bestAlt,
                bestBitDepth = bestBits,
                audioControlInterfaceId = audioControlInterfaceId
        )
        cachedDeviceInfo = info
        return info
    }

    /**
     * Perform a USB device reset via native ioctl, then close and reopen.
     * This clears any stale clock/endpoint state left by the kernel driver.
     * After reset, the DAC reinitializes and will accept our SET_CUR.
     */
    fun resetAndReopen() {
        val conn = connection ?: return
        val fd = conn.fileDescriptor

        Log.i(TAG, "Performing REAL USBDEVFS_RESET on fd=$fd...")

        val ret = UsbAudioStream.nativeUsbReset(fd)
        Log.i(TAG, "USBDEVFS_RESET result: $ret")

        cachedDeviceInfo = null
        claimedInterface = null
    }

    /**
     * Parse raw USB descriptors to find the UAC2 Clock Source entity ID.
     * This is the entity that controls the DAC's sample rate.
     *
     * Scans the AudioControl interface descriptors for a CLOCK_SOURCE
     * descriptor (bDescriptorSubtype = 0x0A) and returns its bClockID.
     *
     * @return Clock Source entity ID, or -1 if not found.
     */
    private fun parseClockSourceId(conn: UsbDeviceConnection): Int {
        val raw = conn.rawDescriptors ?: return -1

        var i = 0
        var inAudioControl = false

        while (i + 1 < raw.size) {
            val bLength = raw[i].toInt() and 0xFF
            if (bLength < 2) break
            if (i + bLength > raw.size) break

            val bDescriptorType = raw[i + 1].toInt() and 0xFF

            if (bDescriptorType == 0x04 && bLength >= 9) {
                val bInterfaceClass = raw[i + 5].toInt() and 0xFF
                val bInterfaceSubClass = raw[i + 6].toInt() and 0xFF
                inAudioControl = (bInterfaceClass == 1 && bInterfaceSubClass == 1)
            }

            if (inAudioControl && bDescriptorType == 0x24 && bLength >= 3) {
                val bDescriptorSubtype = raw[i + 2].toInt() and 0xFF
                if (bDescriptorSubtype == 0x0A && bLength >= 5) {
                    val bClockID = raw[i + 3].toInt() and 0xFF
                    Log.i(TAG, "parseClockSourceId: found CLOCK_SOURCE bClockID=0x${bClockID.toString(16)}")
                    return bClockID
                }
            }

            i += bLength
        }

        Log.w(TAG, "parseClockSourceId: no CLOCK_SOURCE descriptor found")
        return -1
    }

    /**
     * Parse raw USB descriptors to find the best (highest bit depth) alt setting
     * for the AudioStreaming interface.
     *
     * Scans AS Format Type I descriptors (CS_INTERFACE 0x02) for bBitResolution
     * and returns the alt setting with the highest value.
     *
     * @return Pair(altSetting, bitDepth), or Pair(1, 16) as default.
     */
    /** Parsed alt setting: (altNumber, bitResolution) */
    private var parsedAltSettings: List<Pair<Int, Int>> = emptyList()

    private fun parseBestAltSetting(conn: UsbDeviceConnection): Pair<Int, Int> {
        val raw = conn.rawDescriptors ?: return Pair(1, 16)
        val altSettings = mutableListOf<Pair<Int, Int>>()

        var i = 0
        var currentAlt = 0
        var inAudioStreaming = false
        var bestAlt = 1
        var bestBits = 16

        while (i + 1 < raw.size) {
            val bLength = raw[i].toInt() and 0xFF
            if (bLength < 2) break
            if (i + bLength > raw.size) break

            val bDescriptorType = raw[i + 1].toInt() and 0xFF

            if (bDescriptorType == 0x04 && bLength >= 9) {
                val bInterfaceClass = raw[i + 5].toInt() and 0xFF
                val bInterfaceSubClass = raw[i + 6].toInt() and 0xFF
                val bAlternateSetting = raw[i + 3].toInt() and 0xFF
                inAudioStreaming = (bInterfaceClass == 1 && bInterfaceSubClass == 2)
                if (inAudioStreaming) currentAlt = bAlternateSetting
            }

            if (inAudioStreaming && bDescriptorType == 0x24 && bLength >= 6) {
                val bDescriptorSubtype = raw[i + 2].toInt() and 0xFF
                if (bDescriptorSubtype == 0x02) {
                    val bSubslotSize = raw[i + 4].toInt() and 0xFF
                    val bBitResolution = raw[i + 5].toInt() and 0xFF
                    Log.i(TAG, "parseBestAltSetting: alt=$currentAlt subslotSize=$bSubslotSize bitResolution=$bBitResolution")

                    if (currentAlt > 0) {
                        altSettings.add(Pair(currentAlt, bBitResolution))
                    }
                    if (bBitResolution > bestBits && currentAlt > 0) {
                        bestBits = bBitResolution
                        bestAlt = currentAlt
                    }
                }
            }

            i += bLength
        }

        parsedAltSettings = altSettings
        Log.i(TAG, "parseBestAltSetting: best alt=$bestAlt bits=$bestBits, all=$altSettings")
        return Pair(bestAlt, bestBits)
    }

    /**
     * Find the alt setting that matches the given source bit depth exactly.
     * If no exact match, returns the next higher bit depth.
     * Fallback: returns the best (highest) alt setting.
     *
     * @return Pair(altSetting, bitDepth)
     */
    fun findAltSettingForBitDepth(targetBitDepth: Int): Pair<Int, Int> {
        if (parsedAltSettings.isEmpty()) {
            val info = cachedDeviceInfo ?: return Pair(1, 16)
            return Pair(info.bestAltSetting, info.bestBitDepth)
        }

        val exact = parsedAltSettings.firstOrNull { it.second == targetBitDepth }
        if (exact != null) {
            Log.i(TAG, "findAltSettingForBitDepth($targetBitDepth): exact match alt=${exact.first}")
            return exact
        }

        val higher = parsedAltSettings
                .filter { it.second > targetBitDepth }
                .minByOrNull { it.second }
        if (higher != null) {
            Log.i(TAG, "findAltSettingForBitDepth($targetBitDepth): next higher alt=${higher.first} bits=${higher.second}")
            return higher
        }

        val best = parsedAltSettings.maxByOrNull { it.second } ?: Pair(1, 16)
        Log.i(TAG, "findAltSettingForBitDepth($targetBitDepth): fallback to best alt=${best.first} bits=${best.second}")
        return best
    }

    /**
     * Close the USB device and release all resources.
     */
    fun closeDevice() {
        cachedDeviceInfo = null
        claimedInterface?.let { iface ->
            connection?.releaseInterface(iface)
            claimedInterface = null
        }
        connection?.close()
        connection = null
        currentDevice = null
        Log.i(TAG, "USB device closed")
    }

    /**
     * Set the sample rate on a UAC2 Clock Source entity via SET_CUR control transfer.
     * Falls back to UAC1 (endpoint-based) format if UAC2 fails.
     *
     * UAC2 SET_CUR format:
     *   bmRequestType = 0x21 (Host-to-Device, Class, Interface)
     *   bRequest = 0x01 (SET_CUR)
     *   wValue = (CS_SAM_FREQ_CONTROL << 8) | 0 = 0x0100
     *   wIndex = (clockSourceEntityId << 8) | audioControlInterfaceNumber
     *   data = 4-byte LE sample rate (UAC2 dwSamFreq)
     *
     * UAC1 SET_CUR format (fallback):
     *   bmRequestType = 0x22 (Host-to-Device, Class, Endpoint)
     *   bRequest = 0x01 (SET_CUR)
     *   wValue = 0x0100
     *   wIndex = endpointOutAddress (e.g. 0x03)
     *   data = 3-byte LE sample rate (UAC1 old format)
     */
    fun setSampleRate(sampleRateHz: Int): Boolean {
        val conn = connection ?: return false
        val info = cachedDeviceInfo ?: return false

        val uac2InterfaceId = info.audioControlInterfaceId

        val data4 = ByteArray(4)
        data4[0] = (sampleRateHz and 0xFF).toByte()
        data4[1] = ((sampleRateHz shr 8) and 0xFF).toByte()
        data4[2] = ((sampleRateHz shr 16) and 0xFF).toByte()
        data4[3] = ((sampleRateHz shr 24) and 0xFF).toByte()

        val detectedId = info.clockSourceId
        val clockSourceIds = if (detectedId > 0) {
            intArrayOf(detectedId)
        } else {
            intArrayOf(0x05, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
                    0x28, 0x29, 0x2A, 0x06, 0x07, 0x08,
                    0x10, 0x11, 0x12, 0x20, 0x21, 0x22)
        }

        Log.i(TAG, "setSampleRate($sampleRateHz Hz): UAC2 attempt using " +
                "interfaceId=$uac2InterfaceId, clockSourceIds=${clockSourceIds.joinToString(",") {"0x" + it.toString(16)}}, " +
                "data4Bytes=[${data4.joinToString(",") {"0x%02X".format(it.toInt() and 0xFF)}}]")

        for (csId in clockSourceIds) {
            val wIndex = (csId shl 8) or uac2InterfaceId
            val ret = conn.controlTransfer(
                    0x21,    // bmRequestType: Host-to-Device, Class, Interface
                    0x01,    // bRequest: SET_CUR
                    0x0100,  // wValue: CS_SAM_FREQ_CONTROL << 8 | CN (channel number)
                    wIndex,
                    data4,
                    data4.size,
                    1000     // timeout ms
            )
            if (ret >= 0) {
                Log.i(TAG, "setSampleRate($sampleRateHz Hz): UAC2 SUCCESS with " +
                        "clockSourceId=0x${csId.toString(16)} wIndex=0x${wIndex.toString(16)} ret=$ret")
                return true
            } else {
                Log.d(TAG, "setSampleRate: UAC2 csId=0x${csId.toString(16)} wIndex=0x${wIndex.toString(16)} FAILED ret=$ret")
            }
        }

        if (uac2InterfaceId == 0) {
            val data3 = ByteArray(3)
            data3[0] = (sampleRateHz and 0xFF).toByte()
            data3[1] = ((sampleRateHz shr 8) and 0xFF).toByte()
            data3[2] = ((sampleRateHz shr 16) and 0xFF).toByte()

            val epAddr = info.endpointOutAddress
            Log.i(TAG, "setSampleRate($sampleRateHz Hz): UAC1 endpoint fallback " +
                    "(no AudioControl interface) ep=0x${epAddr.toString(16)}")
            val ret = conn.controlTransfer(
                    0x22,    // bmRequestType: Host-to-Device, Class, Endpoint
                    0x01,    // bRequest: SET_CUR
                    0x0100,  // wValue: SAMPLING_FREQ_CONTROL
                    epAddr,  // wIndex: endpoint address
                    data3,
                    data3.size,
                    1000
            )
            if (ret >= 0) {
                Log.i(TAG, "setSampleRate($sampleRateHz Hz): UAC1 endpoint fallback SUCCESS " +
                        "(ep=0x${epAddr.toString(16)}, ret=$ret)")
                return true
            }
            Log.w(TAG, "setSampleRate($sampleRateHz Hz): UAC1 endpoint fallback FAILED")
        } else {
            Log.w(TAG, "setSampleRate($sampleRateHz Hz): UAC2 all attempts failed " +
                    "(interfaceId=$uac2InterfaceId, csIds=" +
                    "${clockSourceIds.joinToString(",") {"0x" + it.toString(16)}}) — " +
                    "UAC1 endpoint fallback SKIPPED (UAC2 device detected)")
        }

        Log.w(TAG, "setSampleRate($sampleRateHz Hz): all attempts failed")
        return false
    }

    /**
     * Read the current sample rate from the DAC via UAC2 GET_CUR.
     * This verifies whether our SET_CUR actually took effect.
     *
     * UAC2 GET_CUR format:
     *   bmRequestType = 0xA1 (Device-to-Host, Class, Interface)
     *   bRequest = 0x01 (GET_CUR)
     *   wValue = 0x0100 (CS_SAM_FREQ_CONTROL)
     *   wIndex = (clockSourceEntityId << 8) | audioControlInterfaceNumber
     *   data = 4-byte LE sample rate
     */
    fun readSampleRate(): Int {
        val conn = connection ?: return -1
        val data = ByteArray(4)
        val uac2InterfaceId = cachedDeviceInfo?.audioControlInterfaceId ?: 0

        val detectedId = cachedDeviceInfo?.clockSourceId ?: -1
        val clockSourceIds = if (detectedId > 0) intArrayOf(detectedId)
                else intArrayOf(0x05, 0x09, 0x0A, 0x0B, 0x0C, 0x28, 0x29)
        for (csId in clockSourceIds) {
            val wIndex = (csId shl 8) or uac2InterfaceId
            val ret = conn.controlTransfer(
                    0xA1,    // bmRequestType: Device-to-Host, Class, Interface
                    0x01,    // bRequest: GET_CUR
                    0x0100,  // wValue: CS_SAM_FREQ_CONTROL
                    wIndex,
                    data,
                    data.size,
                    1000
            )
            if (ret >= 4) {
                val rate = (data[0].toInt() and 0xFF) or
                        ((data[1].toInt() and 0xFF) shl 8) or
                        ((data[2].toInt() and 0xFF) shl 16) or
                        ((data[3].toInt() and 0xFF) shl 24)
                Log.i(TAG, "readSampleRate: GET_CUR clockSourceId=0x${csId.toString(16)} " +
                        "wIndex=0x${wIndex.toString(16)} returned $rate Hz " +
                        "(raw=${data.joinToString(",") { "0x${(it.toInt() and 0xFF).toString(16)}" }})")
                return rate
            } else {
                Log.d(TAG, "readSampleRate: GET_CUR csId=0x${csId.toString(16)} wIndex=0x${wIndex.toString(16)} " +
                        "FAILED ret=$ret")
            }
        }
        Log.w(TAG, "readSampleRate: all GET_CUR attempts failed")
        return -1
    }

    /**
     * Read the CLOCK_VALID control from the DAC via UAC2 GET_CUR.
     * This checks whether the Clock Source entity's clock is locked and stable
     * after a sample rate change. Standard practice per UAC2 spec: verify clock after SET_CUR before proceeding.
     *
     * UAC2 spec: Clock Source descriptor, CS = 0x02 (CUR_CLOCK_VALID_CONTROL)
     * Returns: true if clock is valid, false if not or on error.
     *
     * UAC2 GET_CUR format for CLOCK_VALID:
     *   bmRequestType = 0xA1 (Device-to-Host, Class, Interface)
     *   bRequest = 0x01 (GET_CUR)
     *   wValue = 0x0200 (CS=CLOCK_VALID_CONTROL=0x02 << 8 | CN=0)
     *   wIndex = (clockSourceEntityId << 8) | audioControlInterfaceNumber
     *   data = 1-byte: bit 0 = valid (1) or invalid (0)
     */
    fun readClockValid(): Boolean {
        val conn = connection ?: return false
        val data = ByteArray(1)
        val uac2InterfaceId = cachedDeviceInfo?.audioControlInterfaceId ?: 0

        val detectedId = cachedDeviceInfo?.clockSourceId ?: -1
        val clockSourceIds = if (detectedId > 0) intArrayOf(detectedId)
                else intArrayOf(0x05, 0x09, 0x0A, 0x0B, 0x0C, 0x28, 0x29)
        for (csId in clockSourceIds) {
            val wIndex = (csId shl 8) or uac2InterfaceId
            val ret = conn.controlTransfer(
                    0xA1,    // bmRequestType: Device-to-Host, Class, Interface
                    0x01,    // bRequest: GET_CUR
                    0x0200,  // wValue: CS=0x02 (CLOCK_VALID_CONTROL), CN=0x00
                    wIndex,
                    data,
                    data.size,
                    1000
            )
            if (ret >= 1) {
                val valid = data[0].toInt() and 0x01
                Log.i(TAG, "readClockValid: clockSourceId=0x${csId.toString(16)} " +
                        "wIndex=0x${wIndex.toString(16)} valid=$valid")
                return valid == 1
            } else {
                Log.d(TAG, "readClockValid: GET_CUR csId=0x${csId.toString(16)} wIndex=0x${wIndex.toString(16)} " +
                        "FAILED ret=$ret")
            }
        }
        Log.w(TAG, "readClockValid: all GET_CUR attempts failed")
        return false
    }

    /**
     * Dump raw USB descriptors in detail to diagnose SET_CUR format.
     * Logs every descriptor with type/subtype/fields for AudioControl and
     * AudioStreaming interfaces, including CLOCK_SOURCE, CLOCK_SELECTOR,
     * and Format Type descriptors.
     */
    private fun dumpRawDescriptors(conn: UsbDeviceConnection) {
        val raw = conn.rawDescriptors ?: run {
            Log.w(TAG, "dumpRawDescriptors: rawDescriptors is null")
            return
        }

        Log.i(TAG, "=== RAW USB DESCRIPTOR DUMP (${raw.size} bytes) ===")

        var i = 0
        var inAudioControl = false
        var inAudioStreaming = false
        var currentAlt = 0

        while (i + 1 < raw.size) {
            val bLength = raw[i].toInt() and 0xFF
            if (bLength < 2) { Log.w(TAG, "  Truncated descriptor at offset $i (len=$bLength)"); break }
            if (i + bLength > raw.size) { Log.w(TAG, "  Descriptor extends past end at offset $i"); break }

            val bDescriptorType = raw[i + 1].toInt() and 0xFF
            val hex = (0 until bLength).joinToString(" ") { idx ->
                "%02X".format(raw[i + idx].toInt() and 0xFF)
            }

            when (bDescriptorType) {
                0x01 -> { // DEVICE
                    Log.i(TAG, "[DEVICE] len=$bLength: $hex")
                }
                0x02 -> { // CONFIGURATION
                    Log.i(TAG, "[CONFIG] len=$bLength: $hex")
                }
                0x04 -> { // INTERFACE
                    if (bLength >= 9) {
                        val bInterfaceClass = raw[i + 5].toInt() and 0xFF
                        val bInterfaceSubClass = raw[i + 6].toInt() and 0xFF
                        val bInterfaceProtocol = raw[i + 7].toInt() and 0xFF
                        val bAlternateSetting = raw[i + 3].toInt() and 0xFF
                        currentAlt = bAlternateSetting
                        inAudioControl = (bInterfaceClass == 1 && bInterfaceSubClass == 1)
                        inAudioStreaming = (bInterfaceClass == 1 && bInterfaceSubClass == 2)

                        val clsStr = when (bInterfaceClass) {
                            1 -> "AUDIO"
                            2 -> "COMM"
                            3 -> "HID"
                            255 -> "VENDOR"
                            else -> "CLASS_$bInterfaceClass"
                        }
                        val subStr = when (bInterfaceSubClass) {
                            1 -> "AudioControl"
                            2 -> "AudioStreaming"
                            3 -> "MIDIStreaming"
                            else -> "SUBCLASS_$bInterfaceSubClass"
                        }
                        val protoStr = when (bInterfaceProtocol) {
                            0 -> "UAC1"
                            0x20 -> "UAC2"
                            else -> "PROTO_$bInterfaceProtocol"
                        }
                        Log.i(TAG, "[IFACE] alt=$bAlternateSetting class=$clsStr sub=$subStr proto=$protoStr len=$bLength: $hex")
                    } else {
                        Log.i(TAG, "[IFACE] len=$bLength: $hex")
                    }
                }
                0x05 -> { // ENDPOINT
                    if (bLength >= 7) {
                        val epAddr = raw[i + 2].toInt() and 0xFF
                        val attrs = raw[i + 3].toInt() and 0xFF
                        val maxPkt = (raw[i + 5].toInt() and 0xFF) shl 8 or (raw[i + 4].toInt() and 0xFF)
                        val interval = raw[i + 6].toInt() and 0xFF
                        val dir = if ((epAddr and 0x80) != 0) "IN" else "OUT"
                        val epType = when (attrs and 0x03) {
                            0 -> "CTRL"; 1 -> "ISO"; 2 -> "BULK"; 3 -> "INT"
                            else -> "UNKNOWN"
                        }
                        val syncType = when ((attrs shr 2) and 0x03) {
                            0 -> ""; 1 -> "ASYNC"; 2 -> "ADAPTIVE"; 3 -> "SYNC"
                            else -> ""
                        }
                        Log.i(TAG, "[ENDP] addr=0x${epAddr.toString(16)} $dir type=$epType $syncType " +
                                "maxPkt=$maxPkt interval=$interval")
                    }
                }
                0x24 -> { // CS_INTERFACE (class-specific)
                    if (bLength >= 3) {
                        val bDescriptorSubtype = raw[i + 2].toInt() and 0xFF
                        val subName = when (bDescriptorSubtype) {
                            0x01 -> if (inAudioControl) "AC_HEADER" else if (inAudioStreaming) "AS_GENERAL" else "???"
                            0x02 -> if (inAudioControl) "INPUT_TERMINAL" else "FORMAT_TYPE"
                            0x03 -> if (inAudioControl) "OUTPUT_TERMINAL" else "FORMAT_SPECIFIC"
                            0x04 -> "FEATURE_UNIT"
                            0x05 -> "PROCESSING_UNIT"
                            0x06 -> "EXTENSION_UNIT"
                            0x07 -> "MIXER_UNIT"
                            0x08 -> "SELECTOR_UNIT"
                            0x09 -> "CLOCK_SELECTOR"
                            0x0A -> "CLOCK_SOURCE"
                            0x0B -> "CLOCK_SELECTOR" // UAC2
                            0x0C -> "CLOCK_MULTIPLIER"
                            0x0D -> "SAMPLE_RATE_CONVERTER"
                            else -> "SUBTYPE_0x${bDescriptorSubtype.toString(16)}"
                        }

                        val sb = StringBuilder()
                        sb.append("[CS_IFACE] subtype=$subName ")

                        if (bDescriptorSubtype == 0x0A && bLength >= 5) {
                            val bClockID = raw[i + 3].toInt() and 0xFF
                            val bmAttributes = raw[i + 4].toInt() and 0xFF
                            sb.append("bClockID=0x${bClockID.toString(16)} ")
                            sb.append("attrs=0x${bmAttributes.toString(16)}")
                            if (bLength >= 8) {
                                val bmControls = (raw[i + 6].toInt() and 0xFF) shl 8 or (raw[i + 5].toInt() and 0xFF)
                                sb.append(" controls=0x${bmControls.toString(16)}")
                            }
                        } else if (bDescriptorSubtype == 0x05 && inAudioControl && bLength >= 13) {
                            val wProcessType = (raw[i + 5].toInt() and 0xFF) shl 8 or (raw[i + 4].toInt() and 0xFF)
                            sb.append("wProcessType=0x${wProcessType.toString(16)}")
                        } else if (bDescriptorSubtype == 0x02 && inAudioStreaming && bLength >= 6) {
                            val bSubslotSize = raw[i + 4].toInt() and 0xFF
                            val bBitResolution = raw[i + 5].toInt() and 0xFF
                            sb.append("alt=$currentAlt subslot=$bSubslotSize bit=$bBitResolution")

                            if (bLength >= 7) {
                                val bSamFreqType = raw[i + 6].toInt() and 0xFF
                                sb.append(" freqCount=$bSamFreqType ")
                                if (bSamFreqType > 0) {
                                    val rates = mutableListOf<Int>()
                                    for (f in 0 until bSamFreqType) {
                                        val off = i + 7 + f * 3
                                        if (off + 3 <= raw.size) {
                                            val rate = (raw[off + 2].toInt() and 0xFF) shl 16 or
                                                    ((raw[off + 1].toInt() and 0xFF) shl 8) or
                                                    (raw[off].toInt() and 0xFF)
                                            rates.add(rate)
                                        }
                                    }
                                    sb.append("rates=${rates.joinToString(",")}")
                                } else {
                                    sb.append("rates=CONTINUOUS")
                                }
                            }
                        } else if (bDescriptorSubtype == 0x01 && inAudioControl && bLength >= 9) {
                            val bcdADC = (raw[i + 4].toInt() and 0xFF) shl 8 or (raw[i + 3].toInt() and 0xFF)
                            val uacVer = when (bcdADC) {
                                0x0100 -> "UAC 1.0"
                                0x0200 -> "UAC 2.0"
                                0x0300 -> "UAC 3.0"
                                else -> "UAC 0x${bcdADC.toString(16)}"
                            }
                            sb.append("version=$uacVer")
                            if (bLength >= 8) {
                                val wTotalLength = (raw[i + 6].toInt() and 0xFF) shl 8 or (raw[i + 5].toInt() and 0xFF)
                                sb.append(" wTotalLen=$wTotalLength")
                            }
                            if (bcdADC == 0x0100) {
                                sb.append(" ← UAC 1.0 DAC! UAC2 clock source SET_CUR will FAIL. Use UAC1 endpoint-based format.")
                            }
                        }

                        Log.i(TAG, sb.toString())
                        Log.i(TAG, "  raw[$i]: $hex")
                    }
                }
                0x25 -> { // CS_ENDPOINT (class-specific endpoint)
                    val bDescriptorSubtype = raw[i + 2].toInt() and 0xFF
                    val subName = when (bDescriptorSubtype) {
                        0x01 -> "EP_GENERAL"
                        else -> "EP_SUBTYPE_0x${bDescriptorSubtype.toString(16)}"
                    }
                    Log.i(TAG, "[CS_ENDP] subtype=$subName len=$bLength: $hex")
                }
                else -> {
                }
            }

            i += bLength
        }

        Log.i(TAG, "=== END RAW USB DESCRIPTOR DUMP ===")
    }

    /**
     * Set the alternate setting on the streaming interface via Java API.
     * This may properly allocate USB bandwidth, which the native ioctl might not.
     */
    fun setAltSetting(altSetting: Int): Boolean {
        val conn = connection ?: return false
        val device = currentDevice ?: return false

        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_AUDIO &&
                iface.interfaceSubclass == 2 &&
                iface.alternateSetting == altSetting) {
                val result = conn.setInterface(iface)
                Log.i(TAG, "setAltSetting($altSetting) via Java API: $result " +
                        "(iface id=${iface.id}, endpoints=${iface.endpointCount})")
                return result
            }
        }

        Log.w(TAG, "setAltSetting($altSetting): no matching UsbInterface found, " +
                "trying all AudioStreaming interfaces...")

        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_AUDIO &&
                iface.interfaceSubclass == 2) {
                Log.d(TAG, "  interface $i: id=${iface.id} alt=${iface.alternateSetting} " +
                        "endpoints=${iface.endpointCount}")
            }
        }

        return false
    }

}
