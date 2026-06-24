package com.decent.usbaudio

import android.hardware.usb.UsbDeviceConnection

/**
 * Information about an opened USB audio device, ready for native I/O.
 */
data class UsbAudioDeviceInfo(
    val connection: UsbDeviceConnection,
    val fd: Int,
    val deviceName: String,
    val interfaceId: Int,
    val endpointOutAddress: Int,
    val endpointFeedbackAddress: Int,
    val maxPacketSize: Int,
    val altSettingCount: Int,
    val clockSourceId: Int,
    val bestAltSetting: Int,
    val bestBitDepth: Int,
    /**
     * Interface number of the AudioControl interface (used in UAC2 SET_CUR/GET_CUR
     * wIndex to address the Clock Source entity). Must be passed as the low byte
     * of wIndex: (clockSourceEntityId << 8) | audioControlInterfaceId.
     *
     * This is found during [UsbAudioDevice.openDevice] by scanning for the USB
     * interface with class=AUDIO(1), subclass=AudioControl(1).
     */
    val audioControlInterfaceId: Int = 0
)
