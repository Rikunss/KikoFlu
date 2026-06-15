#ifndef USB_DAC_DRIVER_H
#define USB_DAC_DRIVER_H

#include <jni.h>
#include <cstdint>
#include <string>
#include <memory>
#include <functional>

/**
 * USB DAC Audio Driver — bit-perfect USB audio output via libusb.
 *
 * Provides direct USB Audio Class (UAC) communication with USB DACs,
 * bypassing the Android audio mixer for pristine bit-perfect output.
 *
 * Architecture:
 * ┌─────────────────────────────┐
 * │      Dart (Flutter)         │
 * │  UsbDacService              │
 * └────────┬────────────────────┘
 *          │ MethodChannel
 * ┌────────▼────────────────────┐
 * │   Kotlin (UsbDacPlugin.kt)  │
 * │   - USB permission handling │
 * │   - Device enumeration      │
 * └────────┬────────────────────┘
 *          │ JNI
 * ┌────────▼────────────────────┐
 * │  C++ (usb_dac_driver.cpp)   │
 * │  - libusb initialization    │
 * │  - UAC stream setup         │
 * │  - Isochronous PCM write    │
 * └────────┬────────────────────┘
 *          │ libusb (linux_usbfs)
 *          ▼
 *     USB DAC (hardware)
 *
 * NOTE: On non-rooted Android, direct /dev/bus/usb/ access via libusb
 * is restricted. This driver must be paired with the Android USB Host API
 * (UsbManager + UsbDeviceConnection) which provides the USB device FD
 * through JNI. See UsbDacPlugin.kt for the permission handling layer.
 */

class UsbDacDriver {
public:
    UsbDacDriver();
    ~UsbDacDriver();

    // No copy/move
    UsbDacDriver(const UsbDacDriver&) = delete;
    UsbDacDriver& operator=(const UsbDacDriver&) = delete;

    /**
     * Initialize the driver with a USB device file descriptor.
     * The FD is obtained from Android's UsbDeviceConnection via JNI.
     *
     * @param deviceFd  File descriptor from UsbDeviceConnection.getFileDescriptor()
     * @param sampleRate  Target sample rate (e.g., 44100, 48000, 96000, 192000)
     * @param channelCount  Number of channels (1 = mono, 2 = stereo)
     * @param bitsPerSample  Bit depth (16, 24, or 32)
     * @return true if the DAC was initialized successfully
     */
    bool init(int deviceFd, int sampleRate, int channelCount, int bitsPerSample);

    /**
     * Start audio playback to the USB DAC.
     * @return true if playback started successfully
     */
    bool start();

    /**
     * Stop audio playback.
     */
    void stop();

    /**
     * Close the USB DAC connection and release resources.
     */
    void destroy();

    /**
     * Write PCM float audio data to the USB DAC.
     *
     * @param data  PCM float samples (-1.0 to 1.0)
     * @param numFrames  Number of frames to write
     * @return Number of frames actually written, or negative on error
     */
    int write(const float* data, int numFrames);

    /**
     * Write PCM I16 audio data to the USB DAC (auto-converted to float).
     *
     * @param data  PCM int16_t samples
     * @param numFrames  Number of frames to write
     * @return Number of frames actually written, or negative on error
     */
    int writeI16(const int16_t* data, int numFrames);

    /**
     * Check if the DAC is currently active and streaming.
     */
    bool isActive() const;

    /**
     * Check if the DAC is in bit-perfect mode (mixer bypassed).
     */
    bool isBitPerfect() const;

    /**
     * Get a human-readable status string.
     */
    std::string getStatusString() const;

private:
    // PIMPL pattern — implementation hidden in .cpp
    class Impl;
    std::unique_ptr<Impl> pImpl_;
};

// JNI function declarations (implemented in usb_dac_driver.cpp)
extern "C" {
    // Native JNI for UsbDacPlugin.kt
    JNIEXPORT jlong JNICALL
    Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeCreateDriver(JNIEnv*, jobject);

    JNIEXPORT jboolean JNICALL
    Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeInitDriver(
        JNIEnv*, jobject, jlong native_ptr,
        jint device_fd, jint sample_rate,
        jint channel_count, jint bits_per_sample);

    JNIEXPORT jboolean JNICALL
    Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeStartDriver(
        JNIEnv*, jobject, jlong native_ptr);

    JNIEXPORT void JNICALL
    Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeStopDriver(
        JNIEnv*, jobject, jlong native_ptr);

    JNIEXPORT void JNICALL
    Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeDestroyDriver(
        JNIEnv*, jobject, jlong native_ptr);

    JNIEXPORT jint JNICALL
    Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeWritePcmFloat(
        JNIEnv*, jobject, jlong native_ptr,
        jfloatArray buffer, jint num_frames);

    JNIEXPORT jint JNICALL
    Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeWritePcmI16(
        JNIEnv*, jobject, jlong native_ptr,
        jshortArray buffer, jint num_frames);

    JNIEXPORT jboolean JNICALL
    Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeIsActive(
        JNIEnv*, jobject, jlong native_ptr);
}

#endif // USB_DAC_DRIVER_H
