// ────────────────────────────────────────────────────────────
// USB DAC Driver — Real libusb Implementation
// ────────────────────────────────────────────────────────────
// Provides direct USB Audio Class (UAC) isochronous audio streaming
// via libusb, bypassing the Android audio mixer for bit-perfect output.
//
// Architecture:
//   Dart writePcmFloat/writePcmI16
//     → JNI (Kotlin passes buffer from MethodChannel)
//       → C++ Impl::write() / writeI16()
//         → RingBuffer (lock-free SPSC, 256KB)
//           → Iso transfer callback drains ring → submits ISO packets
//             → libusb_submit_transfer → USB DAC hardware
//
// Threads:
//   - Audio producer thread (JNI calls) → writes to RingBuffer
//   - Event thread → runs libusb_handle_events(), calls transfer callbacks
//
// Isochronous transfer strategy:
//   - Maintain NUM_TRANSFERS_BUFFERED (6) transfers in flight
//   - Each transfer has NUM_ISO_PACKETS (10) packets for ~10ms audio
//   - On completion callback: drain ring buffer, refill, resubmit
//
// ────────────────────────────────────────────────────────────

#include "usb_dac_driver.h"
#include <libusb.h>
#include <jni.h>
#include <android/log.h>
#include <thread>
#include <atomic>
#include <mutex>
#include <vector>
#include <cstring>
#include <cassert>
#include <algorithm>
#include <sstream>
#include <pthread.h>

#define LOG_TAG "UsbDacDriver"
#define LOGV(...) __android_log_print(ANDROID_LOG_VERBOSE, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// ── Constants ──────────────────────────────────────────────

/// Number of concurrent isochronous transfers to keep in flight.
static constexpr int kNumTransfersBuffered = 6;

/// Number of isochronous packets per transfer (~10ms of audio at 1ms intervals).
static constexpr int kNumIsoPackets = 10;

/// Ring buffer capacity in bytes (256 KB).
static constexpr size_t kRingBufferCapacity = 256 * 1024;

/// USB Audio Class interface / subclass codes.
static constexpr int kUacClassAudio = 0x01;
static constexpr int kUacSubclassAudioControl = 0x01;
static constexpr int kUacSubclassAudioStreaming = 0x02;

/// UAC 1.0 class-specific request codes.
static constexpr uint8_t kUacSetCur = 0x01;
static constexpr uint8_t kUacGetCur = 0x81;
static constexpr uint8_t kUacGetMin = 0x82;
static constexpr uint8_t kUacGetMax = 0x83;
static constexpr uint8_t kUacGetRes = 0x84;

/// UAC 1.0 control selectors for AudioStreaming interface.
static constexpr uint8_t kUacSamplingFreqControl = 0x01;

/// bmRequestType for host-to-device, class, interface (AudioStreaming).
static constexpr uint8_t kHostToDeviceClassInterface = 0x21;

/// bmRequestType for device-to-host, class, interface.
static constexpr uint8_t kDeviceToHostClassInterface = 0xA1;

// ── Lock-Free SPSC Ring Buffer ─────────────────────────────
// Single-Producer Single-Consumer ring buffer.
// Producer: JNI write() calls.   Consumer: iso transfer callback.

class RingBuffer {
public:
    explicit RingBuffer(size_t capacity)
        : buffer_(new uint8_t[capacity]), capacity_(capacity),
          writeIndex_(0), readIndex_(0) {}

    ~RingBuffer() { delete[] buffer_; }

    /// Write up to `size` bytes. Returns bytes actually written.
    size_t write(const uint8_t* data, size_t size) {
        size_t available = freeSpace();
        size_t toWrite = std::min(size, available);
        if (toWrite == 0) return 0;

        size_t wIdx = writeIndex_.load(std::memory_order_relaxed);
        size_t firstChunk = std::min(toWrite, capacity_ - wIdx);
        std::memcpy(buffer_ + wIdx, data, firstChunk);

        if (firstChunk < toWrite) {
            std::memcpy(buffer_, data + firstChunk, toWrite - firstChunk);
        }

        size_t newWIdx = (wIdx + toWrite) % capacity_;
        // Ensure data is visible before updating write index (release)
        std::atomic_thread_fence(std::memory_order_release);
        writeIndex_.store(newWIdx, std::memory_order_relaxed);
        return toWrite;
    }

    /// Read up to `size` bytes. Returns bytes actually read.
    size_t read(uint8_t* data, size_t size) {
        size_t available = usedSpace();
        size_t toRead = std::min(size, available);
        if (toRead == 0) return 0;

        // Ensure we see the latest write before reading (acquire)
        std::atomic_thread_fence(std::memory_order_acquire);
        size_t rIdx = readIndex_.load(std::memory_order_relaxed);
        size_t firstChunk = std::min(toRead, capacity_ - rIdx);
        std::memcpy(data, buffer_ + rIdx, firstChunk);

        if (firstChunk < toRead) {
            std::memcpy(data + firstChunk, buffer_, toRead - firstChunk);
        }

        size_t newRIdx = (rIdx + toRead) % capacity_;
        readIndex_.store(newRIdx, std::memory_order_relaxed);
        return toRead;
    }

    /// Get the number of bytes available for reading.
    size_t usedSpace() const {
        size_t w = writeIndex_.load(std::memory_order_acquire);
        size_t r = readIndex_.load(std::memory_order_relaxed);
        if (w >= r) return w - r;
        return capacity_ - (r - w);
    }

    /// Get the number of bytes free for writing.
    size_t freeSpace() const {
        return capacity_ - usedSpace() - 1; // -1 to distinguish full vs empty
    }

    /// Total capacity.
    size_t capacity() const { return capacity_; }

    /// Reset the buffer (not thread-safe — call only when both threads are idle).
    void reset() {
        writeIndex_.store(0, std::memory_order_relaxed);
        readIndex_.store(0, std::memory_order_relaxed);
    }

private:
    uint8_t* buffer_;
    size_t capacity_;
    std::atomic<size_t> writeIndex_;
    std::atomic<size_t> readIndex_;
};

// ── Transfer Context ───────────────────────────────────────
// Manages a pre-allocated isochronous transfer that gets recycled.

struct TransferContext {
    libusb_transfer* transfer = nullptr;
    uint8_t* buffer = nullptr;
    int bufferSize = 0;
    int sampleSize = 0;        // bytes per sample (2 for I16, 3 for 24-bit, 4 for float32)
    int channels = 2;
    bool active = false;

    ~TransferContext() {
        if (transfer) {
            if (active) {
                libusb_cancel_transfer(transfer);
            }
            libusb_free_transfer(transfer);
        }
        delete[] buffer;
    }

    // Prevent copy
    TransferContext(const TransferContext&) = delete;
    TransferContext& operator=(const TransferContext&) = delete;

    TransferContext() = default;
    TransferContext(TransferContext&& other) noexcept
        : transfer(other.transfer), buffer(other.buffer),
          bufferSize(other.bufferSize), sampleSize(other.sampleSize),
          channels(other.channels), active(other.active) {
        other.transfer = nullptr;
        other.buffer = nullptr;
        other.bufferSize = 0;
        other.active = false;
    }

    bool allocate(int isoPackets, int packetSize) {
        transfer = libusb_alloc_transfer(isoPackets);
        if (!transfer) return false;
        bufferSize = isoPackets * packetSize;
        buffer = new uint8_t[bufferSize];
        return true;
    }
};

// ── USB Audio Interface Info ───────────────────────────────

struct UsbAudioInterfaceInfo {
    int interfaceNumber = -1;       // AudioStreaming interface number
    int alternateSetting = -1;      // Alt setting with isochronous OUT endpoint
    uint8_t outEndpointAddr = 0;    // Isochronous OUT endpoint address
    int maxPacketSize = 0;          // wMaxPacketSize of the OUT endpoint
    int controlInterfaceNum = -1;   // AudioControl interface number
};

// ── Implementation ─────────────────────────────────────────

class UsbDacDriver::Impl {
public:
    Impl()
        : context_(nullptr), handle_(nullptr),
          deviceFd_(-1), sampleRate_(0), channelCount_(0), bitsPerSample_(0),
          bytesPerFrame_(0), sampleSize_(0), isActive_(false),
          isBitPerfect_(true), started_(false), streaming_(false),
          ringBuffer_(kRingBufferCapacity), currentEncoding_(nullptr) {}

    ~Impl() { destroy(); }

    // ── Public API ──────────────────────────────────────────

    bool init(int deviceFd, int sampleRate, int channelCount, int bitsPerSample) {
        std::lock_guard<std::mutex> lock(initMutex_);

        if (context_ != nullptr) {
            LOGE("init called but already initialized");
            return false;
        }

        LOGI("init(fd=%d, rate=%dHz, ch=%d, bits=%d)",
             deviceFd, sampleRate, channelCount, bitsPerSample);

        deviceFd_ = deviceFd;
        sampleRate_ = sampleRate;
        channelCount_ = channelCount;
        bitsPerSample_ = bitsPerSample;
        bytesPerFrame_ = channelCount * (bitsPerSample / 8);
        sampleSize_ = bitsPerSample / 8;

        // Step 1: Initialize libusb with NO_DEVICE_DISCOVERY (required on Android
        // because we can't scan /dev/bus/usb/ without root).
        // Without this option, libusb_init_context tries to access /dev/bus/usb/*
        // which is blocked by SELinux on non-rooted Android devices.
        libusb_init_option options[] = {
            { .option = LIBUSB_OPTION_NO_DEVICE_DISCOVERY },
            { .option = LIBUSB_OPTION_LOG_LEVEL, .value = { .ival = LIBUSB_LOG_LEVEL_WARNING } }
        };
        int ret = libusb_init_context(&context_, options, 2);
        if (ret != LIBUSB_SUCCESS) {
            LOGE("libusb_init_context failed: %s", libusb_error_name(ret));
            context_ = nullptr;
            return false;
        }

        LOGI("libusb initialized with NO_DEVICE_DISCOVERY (skipped /dev/bus/usb/ scan)");

        // Step 2: Wrap the sys device FD from Android's UsbDeviceConnection.
        ret = libusb_wrap_sys_device(context_, static_cast<intptr_t>(deviceFd), &handle_);
        if (ret != LIBUSB_SUCCESS || handle_ == nullptr) {
            LOGE("libusb_wrap_sys_device failed: %s", libusb_error_name(ret));
            libusb_exit(context_);
            context_ = nullptr;
            return false;
        }

        LOGI("libusb device wrapped successfully");

        // Step 3: Parse USB descriptors to find audio interfaces.
        if (!findAudioInterface()) {
            LOGE("No suitable USB audio interface found on device");
            libusb_close(handle_);
            handle_ = nullptr;
            libusb_exit(context_);
            context_ = nullptr;
            return false;
        }

        LOGI("Found audio interface: iface=%d, alt_setting=%d, ep=0x%02x, "
             "maxPkt=%d, controlIface=%d",
             audioInfo_.interfaceNumber, audioInfo_.alternateSetting,
             audioInfo_.outEndpointAddr, audioInfo_.maxPacketSize,
             audioInfo_.controlInterfaceNum);

        // Step 4: Claim the audio streaming interface.
        ret = libusb_claim_interface(handle_, audioInfo_.interfaceNumber);
        if (ret != LIBUSB_SUCCESS) {
            LOGE("libusb_claim_interface failed: %s", libusb_error_name(ret));
            libusb_close(handle_);
            handle_ = nullptr;
            libusb_exit(context_);
            context_ = nullptr;
            return false;
        }

        LOGI("Claimed audio interface %d", audioInfo_.interfaceNumber);

        isActive_ = true;
        statusString_ = makeStatusString("Initialized");

        // Step 5: Parse device descriptor for status.
        struct libusb_device_descriptor desc;
        libusb_device* dev = libusb_get_device(handle_);
        if (dev && libusb_get_device_descriptor(dev, &desc) == LIBUSB_SUCCESS) {
            vendorId_ = desc.idVendor;
            productId_ = desc.idProduct;
            LOGI("Device: %04x:%04x", vendorId_, productId_);
        }

        return true;
    }

    bool start() {
        std::lock_guard<std::mutex> lock(initMutex_);
        if (!isActive_ || started_) return false;
        if (audioInfo_.interfaceNumber < 0) return false;

        LOGI("start() — initializing alt setting %d for interface %d",
             audioInfo_.alternateSetting, audioInfo_.interfaceNumber);

        // Step 1: Set alt setting to 0 (idle) before SET_CUR.
        // Many UAC devices require the streaming interface to be idle
        // (alt setting 0) for class-specific control requests to succeed.
        // Without this, SET_CUR returns EBUSY (errno=16) because the
        // isochronous endpoint is already active.
        int ret = libusb_set_interface_alt_setting(
            handle_, audioInfo_.interfaceNumber, 0);
        if (ret != LIBUSB_SUCCESS) {
            LOGW("start(): could not set alt 0 (idle): %s", libusb_error_name(ret));
        } else {
            LOGI("Alt setting 0 (idle) enabled for SET_CUR");
        }

        // Step 2: Set sample rate via UAC class-specific control request.
        // IMPORTANT: Must be done BEFORE enabling the streaming alt setting.
        // Sending SET_CUR while the isochronous endpoint is active causes
        // the kernel to reject the control transfer with EBUSY.
        if (audioInfo_.controlInterfaceNum >= 0) {
            setSampleRate(sampleRate_);
        }

        // Step 3: Set alternate setting to enable isochronous endpoint.
        ret = libusb_set_interface_alt_setting(
            handle_, audioInfo_.interfaceNumber, audioInfo_.alternateSetting);
        if (ret != LIBUSB_SUCCESS) {
            LOGE("libusb_set_interface_alt_setting failed: %s", libusb_error_name(ret));
            return false;
        }

        LOGI("Alt setting %d enabled", audioInfo_.alternateSetting);

        // Step 3: Allocate and prepare isochronous transfers.
        int packetSize = audioInfo_.maxPacketSize;
        // For integer formats, we might need to adjust packet size
        // based on actual frame size.
        int expectedPacketSize = bytesPerFrame_ * (sampleRate_ / 1000);
        if (expectedPacketSize < packetSize) {
            // Use actual data size, but cap at maxPacketSize.
            packetSize = std::min(packetSize, expectedPacketSize);
        }

        // Ensure packet size is at least 1 and not excessive.
        if (packetSize <= 0) packetSize = audioInfo_.maxPacketSize;

        LOGI("Iso packet size: %d bytes (%d frames), %d packets/transfer",
             packetSize, packetSize / bytesPerFrame_, kNumIsoPackets);

        // Pre-allocate all transfers.
        transfers_.clear();
        transfers_.reserve(kNumTransfersBuffered);

        for (int i = 0; i < kNumTransfersBuffered; i++) {
            auto tc = std::make_unique<TransferContext>();
            tc->sampleSize = sampleSize_;
            tc->channels = channelCount_;
            tc->active = false;

            if (!tc->allocate(kNumIsoPackets, packetSize)) {
                LOGE("Failed to allocate transfer %d", i);
                continue;
            }

            libusb_fill_iso_transfer(
                tc->transfer,
                handle_,
                audioInfo_.outEndpointAddr | LIBUSB_ENDPOINT_OUT,
                tc->buffer,
                tc->bufferSize,
                kNumIsoPackets,
                isoTransferCallback,
                this,
                0  // no timeout for isochronous
            );

            libusb_set_iso_packet_lengths(tc->transfer, packetSize);
            transfers_.push_back(std::move(tc));
        }

        if (transfers_.empty()) {
            LOGE("No transfers allocated — cannot start streaming");
            return false;
        }

        // Step 4: Start the event handling thread.
        streaming_ = true;
        eventThread_ = std::thread(&Impl::eventLoop, this);

        // Step 5: Submit initial batch of transfers.
        {
            int submittedCount = 0;
            for (auto& tc : transfers_) {
                if (tc->buffer == nullptr) continue;

                // Fill initial data from ring buffer.
                fillTransferBuffer(tc.get());

                tc->active = true;
                ret = libusb_submit_transfer(tc->transfer);
                if (ret != LIBUSB_SUCCESS) {
                    LOGE("Failed to submit transfer %d: %s",
                         submittedCount, libusb_error_name(ret));
                    tc->active = false;

                    // Cancel already-submitted transfers.
                    for (auto& tc2 : transfers_) {
                        if (tc2->active) {
                            tc2->active = false;
                            libusb_cancel_transfer(tc2->transfer);
                        }
                    }

                    streaming_ = false;
                    if (eventThread_.joinable()) {
                        libusb_interrupt_event_handler(context_);
                        eventThread_.join();
                    }
                    return false;
                }
                submittedCount++;
            }
        }

        started_ = true;
        statusString_ = makeStatusString("Streaming");
        LOGI("USB DAC streaming started with %zu transfers", transfers_.size());
        return true;
    }

    /// Internal stop implementation — does NOT lock initMutex_.
    /// Called from public stop() (which locks) and destroy() (which already holds the lock).
    void stopInternal() {
        if (!started_) return;

        LOGI("stop()");

        // Signal event thread to stop.
        streaming_ = false;
        started_ = false;

        // Cancel all pending transfers.
        for (auto& tc : transfers_) {
            if (tc->active) {
                tc->active = false;
                libusb_cancel_transfer(tc->transfer);
            }
        }

        // Interrupt event handler so it wakes up and exits.
        if (context_) {
            libusb_interrupt_event_handler(context_);
        }

        // Wait for event thread to finish.
        if (eventThread_.joinable()) {
            eventThread_.join();
        }

        // Destroy all transfer contexts (frees buffers and transfers).
        transfers_.clear();

        // Release the alt setting by selecting alt setting 0.
        if (handle_ && audioInfo_.interfaceNumber >= 0) {
            libusb_set_interface_alt_setting(
                handle_, audioInfo_.interfaceNumber, 0);
        }

        ringBuffer_.reset();
        statusString_ = makeStatusString("Stopped");
        LOGI("USB DAC streaming stopped");
    }

    void stop() {
        std::lock_guard<std::mutex> lock(initMutex_);
        stopInternal();
    }

    void destroy() {
        std::lock_guard<std::mutex> lock(initMutex_);
        if (!isActive_) return;

        LOGI("destroy()");
        // Use stopInternal() to avoid deadlock — destroy() already holds initMutex_,
        // and stop() would try to lock it again (std::mutex is NOT recursive).
        stopInternal();

        // Release interface.
        if (handle_ && audioInfo_.interfaceNumber >= 0) {
            int ret = libusb_release_interface(handle_, audioInfo_.interfaceNumber);
            if (ret != LIBUSB_SUCCESS) {
                LOGW("libusb_release_interface: %s", libusb_error_name(ret));
            }
        }

        // Close device handle and exit libusb.
        if (handle_) {
            libusb_close(handle_);
            handle_ = nullptr;
        }
        if (context_) {
            libusb_exit(context_);
            context_ = nullptr;
        }

        audioInfo_ = UsbAudioInterfaceInfo{};
        transfers_.clear();
        deviceFd_ = -1;
        isActive_ = false;
        started_ = false;
        streaming_ = false;
        ringBuffer_.reset();

        statusString_ = "Destroyed";
        LOGI("USB DAC destroyed");
    }

    int write(const float* data, int numFrames) {
        currentEncoding_ = "FLOAT";
        if (!isActive_) {
            LOGE("write() called but driver not active");
            return -1;
        }
        if (data == nullptr || numFrames <= 0) return 0;

        size_t numSamples = static_cast<size_t>(numFrames) * channelCount_;

        LOGI("[NATIVE-AUDIO] IMPL-FLOAT: sampleSize_=%d bitsPerSample_=%d "
             "channelCount_=%d bytesPerFrame_=%d "
             "numFrames=%d numSamples=%zu outputBytes=%zu",
             sampleSize_, bitsPerSample_, channelCount_, bytesPerFrame_,
             numFrames, numSamples,
             numSamples * static_cast<size_t>(sampleSize_));

        // Convert float PCM to the output format and write to ring buffer.
        // For USB audio, we typically send linear PCM as either:
        //   - 16-bit signed integer (2 bytes per sample)
        //   - 24-bit signed integer (3 bytes per sample, left-aligned in 3 bytes)
        //   - 32-bit signed integer (4 bytes per sample)
        //
        // We convert from float [-1.0, 1.0] to the target format.

        size_t outputBytes = numSamples * static_cast<size_t>(sampleSize_);
        if (outputBytes > tempBuffer_.size()) {
            tempBuffer_.resize(outputBytes + 1024);
        }

        convertFloatToPcm(data, numFrames, tempBuffer_.data(), sampleSize_);

        size_t preWriteUsed = ringBuffer_.usedSpace();
        size_t written = ringBuffer_.write(tempBuffer_.data(), outputBytes);
        size_t postWriteUsed = ringBuffer_.usedSpace();
        int framesWritten = static_cast<int>(written / bytesPerFrame_);

        LOGI("[NATIVE-AUDIO] IMPL-FLOAT result: bytesReceived=%zu framesReceived=%d "
             "(requested=%d frames) preUsed=%zu postUsed=%zu",
             written, framesWritten, numFrames,
             preWriteUsed, postWriteUsed);

        if (framesWritten < numFrames) {
            LOGW("write: ring buffer FULL — requested %d frames (%zu B), "
                 "wrote %d frames (%zu B) "
                 "(preWriteUsed=%zu/%zu, postWriteUsed=%zu/%zu)",
                 numFrames, outputBytes,
                 framesWritten, written,
                 preWriteUsed, ringBuffer_.capacity(),
                 postWriteUsed, ringBuffer_.capacity());
        }

        return framesWritten;
    }

    int writeI16(const int16_t* data, int numFrames) {
        currentEncoding_ = "I16";
        if (!isActive_) {
            LOGE("writeI16() called but driver not active");
            return -1;
        }
        if (data == nullptr || numFrames <= 0) return 0;

        size_t numSamples = static_cast<size_t>(numFrames) * channelCount_;
        size_t byteCount = numSamples * sizeof(int16_t);

        LOGI("[NATIVE-AUDIO] IMPL-I16: sampleSize_=%d bitsPerSample_=%d "
             "channelCount_=%d bytesPerFrame_=%d "
             "numFrames=%d numSamples=%zu bytesReceived=%zu "
             "sampleSize_==2(direct)=%s",
             sampleSize_, bitsPerSample_, channelCount_, bytesPerFrame_,
             numFrames, numSamples, byteCount,
             sampleSize_ == 2 ? "true" : "false");

        size_t preWriteUsed = ringBuffer_.usedSpace();
        size_t written;

        // If DAC expects 16-bit, write directly.
        if (sampleSize_ == 2) {
            written = ringBuffer_.write(
                reinterpret_cast<const uint8_t*>(data), byteCount);
        } else {
            // Otherwise, upscale to 24-bit or 32-bit.
            size_t outputBytes = numSamples * static_cast<size_t>(sampleSize_);
            if (outputBytes > tempBuffer_.size()) {
                tempBuffer_.resize(outputBytes + 1024);
            }

            convertI16ToPcm(data, numFrames, tempBuffer_.data(), sampleSize_);
            written = ringBuffer_.write(tempBuffer_.data(), outputBytes);
        }

        size_t postWriteUsed = ringBuffer_.usedSpace();
        int framesWritten = static_cast<int>(written / bytesPerFrame_);

        LOGI("[NATIVE-AUDIO] IMPL-I16 result: bytesWritten=%zu framesWritten=%d "
             "(requested=%d frames) preUsed=%zu postUsed=%zu",
             written, framesWritten, numFrames,
             preWriteUsed, postWriteUsed);

        if (framesWritten < numFrames) {
            LOGW("writeI16: ring buffer FULL — requested %d frames (%zu B), "
                 "wrote %d frames (%zu B) "
                 "(preWriteUsed=%zu/%zu, postWriteUsed=%zu/%zu)",
                 numFrames, byteCount,
                 framesWritten, written,
                 preWriteUsed, ringBuffer_.capacity(),
                 postWriteUsed, ringBuffer_.capacity());
        }

        return framesWritten;
    }

    bool isActive() const { return isActive_; }
    bool isBitPerfect() const { return isBitPerfect_; }
    std::string getStatusString() const { return statusString_; }

private:
    // ── Core State ──────────────────────────────────────────

    libusb_context* context_;
    libusb_device_handle* handle_;
    int deviceFd_;
    int sampleRate_;
    int channelCount_;
    int bitsPerSample_;
    int bytesPerFrame_;
    int sampleSize_;       // bytes per sample
    int vendorId_ = 0;
    int productId_ = 0;

    bool isActive_;
    bool isBitPerfect_;
    bool started_;
    std::atomic<bool> streaming_;
    const char* currentEncoding_;  // Set by write functions for [FORMAT-STATS]

    UsbAudioInterfaceInfo audioInfo_;
    std::vector<std::unique_ptr<TransferContext>> transfers_;
    std::thread eventThread_;
    std::mutex initMutex_;

    RingBuffer ringBuffer_;
    std::vector<uint8_t> tempBuffer_;
    std::string statusString_;

    // ── Debug counters ──
    std::atomic<int> underrunCount_{0};
    std::atomic<int> transferTimeouts_{0};
    std::atomic<int> transferErrors_{0};
    std::atomic<int> resubmitErrors_{0};
    std::atomic<long long> totalBytesConsumed_{0};  // Total bytes read from ring by fillTransferBuffer

    // ── USB Audio Interface Discovery ───────────────────────

    bool findAudioInterface() {
        if (!handle_) return false;

        libusb_device* dev = libusb_get_device(handle_);
        if (!dev) {
            LOGE("Cannot get libusb_device from handle");
            return false;
        }

        struct libusb_config_descriptor* config = nullptr;
        int ret = libusb_get_active_config_descriptor(dev, &config);
        if (ret != LIBUSB_SUCCESS) {
            LOGE("Cannot get active config descriptor: %s", libusb_error_name(ret));
            return false;
        }

        int foundControlInterface = -1;
        int foundStreamInterface = -1;

        // Iterate through all interfaces and alternate settings.
        for (int ifaceIdx = 0; ifaceIdx < config->bNumInterfaces; ifaceIdx++) {
            const libusb_interface& iface = config->interface[ifaceIdx];

            for (int altIdx = 0; altIdx < iface.num_altsetting; altIdx++) {
                const libusb_interface_descriptor& alt = iface.altsetting[altIdx];

                // Check for Audio Control interface.
                if (alt.bInterfaceClass == kUacClassAudio &&
                    alt.bInterfaceSubClass == kUacSubclassAudioControl) {
                    foundControlInterface = alt.bInterfaceNumber;
                    LOGI("Found AudioControl interface %d, alt %d",
                         alt.bInterfaceNumber, alt.bAlternateSetting);
                }

                // Check for Audio Streaming interface with isochronous OUT endpoint.
                if (alt.bInterfaceClass == kUacClassAudio &&
                    alt.bInterfaceSubClass == kUacSubclassAudioStreaming &&
                    alt.bAlternateSetting > 0) {

                    LOGI("Found AudioStreaming interface %d, alt %d, %d endpoints",
                         alt.bInterfaceNumber, alt.bAlternateSetting, alt.bNumEndpoints);

                    for (int epIdx = 0; epIdx < alt.bNumEndpoints; epIdx++) {
                        const libusb_endpoint_descriptor& ep = alt.endpoint[epIdx];

                        // Look for isochronous OUT endpoint.
                        bool isOUT = (ep.bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_OUT;
                        bool isIso = (ep.bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) ==
                                     LIBUSB_ENDPOINT_TRANSFER_TYPE_ISOCHRONOUS;

                        if (isOUT && isIso) {
                            LOGI("  Found ISO OUT endpoint: 0x%02x, maxPkt=%d, interval=%d",
                                 ep.bEndpointAddress, ep.wMaxPacketSize, ep.bInterval);

                            // ── Alt setting selection logic ──
                            // Match the alt setting's maxPacketSize to our audio format.
                            //   Alt 1 (maxPkt≈200) → 16-bit  (expected 48×4=192)
                            //   Alt 2 (maxPkt≈300) → 24-bit  (expected 48×6=288)
                            //   Alt 3/4 (maxPkt≈400) → 32-bit (expected 48×8=384)
                            // Previously we always picked the highest alt setting (32-bit),
                            // which caused severe crackling when sending PCM16 data on a
                            // 32-bit-configured endpoint (every sample misaligned by 4 bytes).
                            int expectedPkt = bytesPerFrame_ * (sampleRate_ / 1000);
                            bool shouldReplace = false;
                            if (foundStreamInterface < 0) {
                                shouldReplace = true;
                            } else {
                                int curDiff = audioInfo_.maxPacketSize - expectedPkt;
                                if (curDiff < 0) curDiff = -curDiff;
                                int thisDiff = (int)ep.wMaxPacketSize - expectedPkt;
                                if (thisDiff < 0) thisDiff = -thisDiff;
                                // Prefer alt setting closest to expected packet size
                                if (thisDiff < curDiff) {
                                    shouldReplace = true;
                                } else if (thisDiff == curDiff &&
                                           alt.bAlternateSetting > audioInfo_.alternateSetting) {
                                    shouldReplace = true;
                                }
                            }

                            if (shouldReplace) {
                                audioInfo_.interfaceNumber = alt.bInterfaceNumber;
                                audioInfo_.alternateSetting = alt.bAlternateSetting;
                                audioInfo_.outEndpointAddr = ep.bEndpointAddress;
                                audioInfo_.maxPacketSize = ep.wMaxPacketSize;
                                foundStreamInterface = alt.bInterfaceNumber;
                                LOGI("    → SELECTED: alt=%d, maxPkt=%d (expected=%d, diff=%d)",
                                     alt.bAlternateSetting, ep.wMaxPacketSize, expectedPkt,
                                     (int)ep.wMaxPacketSize - expectedPkt);
                            } else {
                                LOGI("    → SKIPPED: alt=%d, maxPkt=%d (expected=%d, better alt already selected)",
                                     alt.bAlternateSetting, ep.wMaxPacketSize, expectedPkt);
                            }
                        }
                    }
                }
            }
        }

        libusb_free_config_descriptor(config);

        // If no explicit AudioControl interface, try using the streaming interface itself.
        if (foundControlInterface >= 0) {
            audioInfo_.controlInterfaceNum = foundControlInterface;
        } else if (foundStreamInterface >= 0) {
            // Some UAC 2.0 devices use combined interfaces.
            audioInfo_.controlInterfaceNum = audioInfo_.interfaceNumber;
        }

        return foundStreamInterface >= 0;
    }

    // ── UAC Sample Rate Control ────────────────────────────

    bool setSampleRate(int sampleRate) {
        if (!handle_ || audioInfo_.controlInterfaceNum < 0) return false;

        LOGI("Setting sample rate to %d Hz via interface %d",
             sampleRate, audioInfo_.controlInterfaceNum);

        // Try UAC 1.0 format first (3-byte 24.8 fixed point).
        {
            uint8_t data[3] = {
                static_cast<uint8_t>(sampleRate & 0xFF),
                static_cast<uint8_t>((sampleRate >> 8) & 0xFF),
                static_cast<uint8_t>((sampleRate >> 16) & 0xFF)
            };

            int ret = libusb_control_transfer(
                handle_,
                kHostToDeviceClassInterface,  // bmRequestType: host→dev, class, iface
                kUacSetCur,                   // bRequest: SET_CUR
                (kUacSamplingFreqControl << 8) | 0x00,  // wValue: CS=0x01, CN=0
                static_cast<uint16_t>(audioInfo_.controlInterfaceNum),  // wIndex
                data, 3,                      // data + length
                1000                           // timeout
            );

            if (ret >= 0) {
                LOGI("Sample rate set to %d Hz (UAC 1.0)", sampleRate);
                return true;
            }

            LOGW("UAC 1.0 SET_CUR failed: %s — trying UAC 2.0", libusb_error_name(ret));
        }

        // Try UAC 2.0 format (4-byte uint32_t).
        {
            uint8_t data[4] = {
                static_cast<uint8_t>(sampleRate & 0xFF),
                static_cast<uint8_t>((sampleRate >> 8) & 0xFF),
                static_cast<uint8_t>((sampleRate >> 16) & 0xFF),
                static_cast<uint8_t>((sampleRate >> 24) & 0xFF)
            };

            int ret = libusb_control_transfer(
                handle_,
                kHostToDeviceClassInterface,  // bmRequestType
                kUacSetCur,                   // bRequest: SET_CUR
                0x0200,                       // wValue: CS=0x02 (SamplingFreq), CN=0
                static_cast<uint16_t>(audioInfo_.controlInterfaceNum),  // wIndex
                data, 4,                      // data + length
                1000
            );

            if (ret >= 0) {
                LOGI("Sample rate set to %d Hz (UAC 2.0)", sampleRate);
                return true;
            }

            LOGW("UAC 2.0 SET_CUR failed: %s — continuing without explicit rate set",
                 libusb_error_name(ret));
        }

        // If both failed, the DAC might auto-detect from bus clock.
        // This is common with adaptive USB DACs.
        return false;
    }

    // ── PCM Format Conversion ───────────────────────────────

    void convertFloatToPcm(const float* src, int numFrames,
                           uint8_t* dst, int outSampleSize) {
        size_t numSamples = static_cast<size_t>(numFrames) * channelCount_;

        switch (outSampleSize) {
        case 2: // 16-bit signed integer
            for (size_t i = 0; i < numSamples; i++) {
                int32_t s = static_cast<int32_t>(src[i] * 32767.0f);
                if (s < -32768) s = -32768;
                if (s > 32767) s = 32767;
                dst[i * 2 + 0] = static_cast<uint8_t>(s & 0xFF);
                dst[i * 2 + 1] = static_cast<uint8_t>((s >> 8) & 0xFF);
            }
            break;

        case 3: // 24-bit signed integer (little-endian, 3 bytes)
            for (size_t i = 0; i < numSamples; i++) {
                int32_t s = static_cast<int32_t>(src[i] * 8388607.0f);
                if (s < -8388608) s = -8388608;
                if (s > 8388607) s = 8388607;
                dst[i * 3 + 0] = static_cast<uint8_t>(s & 0xFF);
                dst[i * 3 + 1] = static_cast<uint8_t>((s >> 8) & 0xFF);
                dst[i * 3 + 2] = static_cast<uint8_t>((s >> 16) & 0xFF);
            }
            break;

        case 4: // 32-bit signed integer
            for (size_t i = 0; i < numSamples; i++) {
                int32_t s = static_cast<int32_t>(src[i] * 2147483647.0f);
                dst[i * 4 + 0] = static_cast<uint8_t>(s & 0xFF);
                dst[i * 4 + 1] = static_cast<uint8_t>((s >> 8) & 0xFF);
                dst[i * 4 + 2] = static_cast<uint8_t>((s >> 16) & 0xFF);
                dst[i * 4 + 3] = static_cast<uint8_t>((s >> 24) & 0xFF);
            }
            break;

        default:
            LOGE("Unsupported sample size: %d bytes", outSampleSize);
            break;
        }
    }

    void convertI16ToPcm(const int16_t* src, int numFrames,
                          uint8_t* dst, int outSampleSize) {
        size_t numSamples = static_cast<size_t>(numFrames) * channelCount_;

        switch (outSampleSize) {
        case 3: // Upscale to 24-bit
            for (size_t i = 0; i < numSamples; i++) {
                int32_t s = static_cast<int32_t>(src[i]) << 8;  // I16 → I24 (left-aligned)
                dst[i * 3 + 0] = static_cast<uint8_t>(s & 0xFF);
                dst[i * 3 + 1] = static_cast<uint8_t>((s >> 8) & 0xFF);
                dst[i * 3 + 2] = static_cast<uint8_t>((s >> 16) & 0xFF);
            }
            break;

        case 4: // Upscale to 32-bit
            for (size_t i = 0; i < numSamples; i++) {
                int32_t s = static_cast<int32_t>(src[i]) << 16;  // I16 → I32
                dst[i * 4 + 0] = static_cast<uint8_t>(s & 0xFF);
                dst[i * 4 + 1] = static_cast<uint8_t>((s >> 8) & 0xFF);
                dst[i * 4 + 2] = static_cast<uint8_t>((s >> 16) & 0xFF);
                dst[i * 4 + 3] = static_cast<uint8_t>((s >> 24) & 0xFF);
            }
            break;

        default:
            // Should not reach here (I16 case handled at call site).
            LOGE("Unexpected upscale target: %d bytes", outSampleSize);
            break;
        }
    }

    // ── Isochronous Transfer Management ─────────────────────

    /// Fill a transfer buffer from the ring buffer.
    void fillTransferBuffer(TransferContext* tc) {
        if (!tc || !tc->buffer || tc->bufferSize <= 0) return;

        size_t bytesRead = ringBuffer_.read(tc->buffer, tc->bufferSize);
        totalBytesConsumed_ += bytesRead;

        // If ring buffer is underrun, fill remaining with silence.
        if (bytesRead < static_cast<size_t>(tc->bufferSize)) {
            size_t underrunBytes = tc->bufferSize - bytesRead;
            LOGW("RING BUFFER UNDERRUN: expected %d B, read %zu B, "
                 "filling %zu B with silence (ringUsed=%zu/%zu)",
                 tc->bufferSize, bytesRead, underrunBytes,
                 ringBuffer_.usedSpace(), ringBuffer_.capacity());
            std::memset(tc->buffer + bytesRead, 0,
                        underrunBytes);
            underrunCount_++;
        }

        // Update actual lengths for iso packets.
        // Each packet gets an equal share of the data.
        int pktSize = tc->bufferSize / kNumIsoPackets;
        for (int i = 0; i < kNumIsoPackets; i++) {
            tc->transfer->iso_packet_desc[i].length = pktSize;
            tc->transfer->iso_packet_desc[i].actual_length = 0;
            tc->transfer->iso_packet_desc[i].status = LIBUSB_TRANSFER_COMPLETED;
        }
    }

    /// Static callback for isochronous transfer completion.
    static void LIBUSB_CALL isoTransferCallback(struct libusb_transfer* transfer) {
        if (!transfer) {
            LOGE("isoTransferCallback: null transfer");
            return;
        }

        auto* impl = static_cast<Impl*>(transfer->user_data);
        if (!impl) {
            LOGE("isoTransferCallback: null impl");
            return;
        }

        // Check if we should continue streaming.
        if (!impl->streaming_.load(std::memory_order_acquire)) {
            // Mark the transfer as inactive and don't resubmit.
            // Find which TransferContext this transfer belongs to.
            for (auto& tc : impl->transfers_) {
                if (tc->transfer == transfer) {
                    tc->active = false;
                    break;
                }
            }
            LOGI("isoTransferCallback: streaming stopped, not resubmitting");
            return;
        }

        // Check transfer status.
        switch (transfer->status) {
        case LIBUSB_TRANSFER_COMPLETED:
            break;  // Continue normally
        case LIBUSB_TRANSFER_TIMED_OUT:
            LOGW("isoTransferCallback: TIMED OUT — resubmitting");
            impl->transferTimeouts_++;
            break;
        case LIBUSB_TRANSFER_CANCELLED:
        case LIBUSB_TRANSFER_NO_DEVICE: {
            // Device disconnected or cancelled — stop streaming.
            for (auto& tc : impl->transfers_) {
                if (tc->transfer == transfer) {
                    tc->active = false;
                    break;
                }
            }
            impl->streaming_.store(false, std::memory_order_release);
            LOGE("isoTransferCallback: %s — stopping stream (totalTimeouts=%d)",
                 transfer->status == LIBUSB_TRANSFER_CANCELLED ? "CANCELLED" : "NO_DEVICE",
                 impl->transferTimeouts_.load());
            return;
        }
        case LIBUSB_TRANSFER_ERROR:
            LOGW("isoTransferCallback: ERROR — resubmitting (errCount=%d)",
                 impl->transferErrors_++);
            break;
        case LIBUSB_TRANSFER_STALL:
            LOGW("isoTransferCallback: STALL — resubmitting");
            break;
        case LIBUSB_TRANSFER_OVERFLOW:
            LOGW("isoTransferCallback: OVERFLOW — resubmitting");
            break;
        default:
            LOGW("isoTransferCallback: unknown status %d — resubmitting", transfer->status);
            break;
        }

        // Find the transfer context and refill from ring buffer.
        for (auto& tc : impl->transfers_) {
            if (tc->transfer == transfer) {
                impl->fillTransferBuffer(tc.get());

                // Resubmit the transfer.
                int ret = libusb_submit_transfer(transfer);
                if (ret != LIBUSB_SUCCESS) {
                    LOGE("Iso resubmit failed: %s", libusb_error_name(ret));
                    tc->active = false;
                    impl->resubmitErrors_++;
                }
                break;
            }
        }
    }

    // ── Event Handling Thread ───────────────────────────────

    void eventLoop() {
        LOGI("Event thread started");

        // Set thread name for debugging.
#if defined(__ANDROID__) || defined(__linux__)
        pthread_setname_np(pthread_self(), "usb_dac_events");
#endif

        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 100000;  // 100ms timeout — allows checking streaming_ flag

        while (streaming_.load(std::memory_order_acquire)) {
            // ── Per-second [FORMAT-STATS] logging ──
            static uint64_t lastStatsLogUs = 0;
            static long long lastBytesConsumed = 0;
            struct timeval now;
            gettimeofday(&now, nullptr);
            uint64_t nowUs = static_cast<uint64_t>(now.tv_sec) * 1000000ULL + now.tv_usec;
            if (lastStatsLogUs != 0 && nowUs - lastStatsLogUs >= 1000000ULL) {
                long long curBytes = totalBytesConsumed_.load();
                long long bytesDelta = curBytes - lastBytesConsumed;
                size_t ringUsed = ringBuffer_.usedSpace();
                LOGI("[FORMAT-STATS] encoding=%s ringUsed=%zu/%zu underruns=%d bytesTotal=%lld bytesDelta=%lld",
                     currentEncoding_ ? currentEncoding_ : "NULL",
                     ringUsed, ringBuffer_.capacity(),
                     underrunCount_.load(),
                     curBytes, bytesDelta);
                lastStatsLogUs = nowUs;
                lastBytesConsumed = curBytes;
            }
            if (lastStatsLogUs == 0) {
                gettimeofday(&now, nullptr);
                lastStatsLogUs = static_cast<uint64_t>(now.tv_sec) * 1000000ULL + now.tv_usec;
                lastBytesConsumed = totalBytesConsumed_.load();
            }

            int ret = libusb_handle_events_timeout(context_, &tv);
            if (ret != LIBUSB_SUCCESS && ret != LIBUSB_ERROR_INTERRUPTED &&
                ret != LIBUSB_ERROR_TIMEOUT) {
                LOGE("libusb_handle_events error: %s (streaming=%d)",
                     libusb_error_name(ret), streaming_.load());
                break;
            }
        }

        LOGI("Event thread finished");
    }

    // ── Utilities ───────────────────────────────────────────

    std::string makeStatusString(const char* state) const {
        std::ostringstream oss;
        oss << "USB DAC " << state;
        if (vendorId_ && productId_) {
            oss << " [" << std::hex << vendorId_ << ":" << productId_ << "]";
        }
        oss << " " << sampleRate_ / 1000 << "kHz, "
            << channelCount_ << "ch, " << bitsPerSample_ << "bit";
        if (isBitPerfect_) oss << " [bit-perfect]";
        return oss.str();
    }
};

// ── Public API (delegates to PIMPL) ─────────────────────────

UsbDacDriver::UsbDacDriver() : pImpl_(std::make_unique<Impl>()) {}
UsbDacDriver::~UsbDacDriver() = default;

bool UsbDacDriver::init(int fd, int sr, int ch, int b) {
    return pImpl_->init(fd, sr, ch, b);
}
bool UsbDacDriver::start() { return pImpl_->start(); }
void UsbDacDriver::stop() { pImpl_->stop(); }
void UsbDacDriver::destroy() { pImpl_->destroy(); }
int UsbDacDriver::write(const float* d, int n) { return pImpl_->write(d, n); }
int UsbDacDriver::writeI16(const int16_t* d, int n) { return pImpl_->writeI16(d, n); }
bool UsbDacDriver::isActive() const { return pImpl_->isActive(); }
bool UsbDacDriver::isBitPerfect() const { return pImpl_->isBitPerfect(); }
std::string UsbDacDriver::getStatusString() const { return pImpl_->getStatusString(); }

// ── JNI Bridge ─────────────────────────────────────────────

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeCreateDriver(
    JNIEnv* env, jobject /* thiz */) {
    LOGI("nativeCreateDriver()");
    auto* driver = new UsbDacDriver();
    return reinterpret_cast<jlong>(driver);
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeInitDriver(
    JNIEnv* env, jobject /* thiz */,
    jlong native_ptr, jint device_fd, jint sample_rate,
    jint channel_count, jint bits_per_sample) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver == nullptr) return JNI_FALSE;
    return driver->init(device_fd, sample_rate, channel_count, bits_per_sample)
        ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeStartDriver(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver == nullptr) return JNI_FALSE;
    return driver->start() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeStopDriver(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver != nullptr) driver->stop();
}

JNIEXPORT void JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeDestroyDriver(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver != nullptr) {
        driver->destroy();
        delete driver;
    }
}

JNIEXPORT jint JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeWritePcmFloat(
    JNIEnv* env, jobject /* thiz */,
    jlong native_ptr, jfloatArray buffer, jint num_frames) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver == nullptr) return -1;

    jsize len = env->GetArrayLength(buffer);
    if (len <= 0) return 0;

    jfloat* elements = env->GetFloatArrayElements(buffer, nullptr);
    if (elements == nullptr) return -1;

    jint written = driver->write(elements, num_frames);
    env->ReleaseFloatArrayElements(buffer, elements, JNI_ABORT);
    return written;
}

JNIEXPORT jint JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeWritePcmI16(
    JNIEnv* env, jobject /* thiz */,
    jlong native_ptr, jshortArray buffer, jint num_frames) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver == nullptr) return -1;

    jsize len = env->GetArrayLength(buffer);
    if (len <= 0) return 0;

    jshort* elements = env->GetShortArrayElements(buffer, nullptr);
    if (elements == nullptr) return -1;

    jint written = driver->writeI16(
        reinterpret_cast<int16_t*>(elements), num_frames);
    env->ReleaseShortArrayElements(buffer, elements, JNI_ABORT);
    return written;
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeIsActive(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver == nullptr) return JNI_FALSE;
    return driver->isActive() ? JNI_TRUE : JNI_FALSE;
}

// ── Static JNI impl functions (used by LibusbAudioSink via UsbDacPlugin companion) ──
// These are @JvmStatic private external fun in the companion object, so the JNI name
// uses the outer class name (not "Companion") because @JvmStatic generates a static
// method directly on the containing class (UsbDacPlugin).

JNIEXPORT jint JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeWritePcmFloatStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr,
    jfloatArray buffer, jint num_frames) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver == nullptr) {
        LOGE("nativeWritePcmFloatStaticImpl: null driver (ptr=0x%llx)", (long long)native_ptr);
        return -1;
    }

    jsize len = env->GetArrayLength(buffer);
    if (len <= 0) {
        LOGW("nativeWritePcmFloatStaticImpl: empty buffer");
        return 0;
    }

    jfloat* elements = env->GetFloatArrayElements(buffer, nullptr);
    if (elements == nullptr) {
        LOGE("nativeWritePcmFloatStaticImpl: GetFloatArrayElements returned null");
        return -1;
    }

    LOGI("[NATIVE-AUDIO] JNI-FLOAT: path=FLOAT frames=%d samples=%d bytesPerSample=%d",
         num_frames, (int)len, 4);

    jint written = driver->write(elements, num_frames);
    env->ReleaseFloatArrayElements(buffer, elements, JNI_ABORT);

    LOGI("[NATIVE-AUDIO] JNI-FLOAT result: written=%d frames, requested=%d frames",
         written, num_frames);

    if (written < 0) {
        LOGE("nativeWritePcmFloatStaticImpl: driver->write returned %d (frames=%d, bufLen=%d)",
             written, num_frames, (int)len);
    }

    return written;
}

JNIEXPORT jint JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeWritePcmI16StaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr,
    jshortArray buffer, jint num_frames) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver == nullptr) {
        LOGE("nativeWritePcmI16StaticImpl: null driver (ptr=0x%llx)", (long long)native_ptr);
        return -1;
    }

    jsize len = env->GetArrayLength(buffer);
    if (len <= 0) {
        LOGW("nativeWritePcmI16StaticImpl: empty buffer");
        return 0;
    }

    jshort* elements = env->GetShortArrayElements(buffer, nullptr);
    if (elements == nullptr) {
        LOGE("nativeWritePcmI16StaticImpl: GetShortArrayElements returned null");
        return -1;
    }

    LOGI("[NATIVE-AUDIO] JNI-I16: path=PCM16 frames=%d samples=%d bytesPerSample=2 bytesReceived=%d",
         num_frames, (int)len, (int)len * 2);

    jint written = driver->writeI16(
        reinterpret_cast<int16_t*>(elements), num_frames);
    env->ReleaseShortArrayElements(buffer, elements, JNI_ABORT);

    LOGI("[NATIVE-AUDIO] JNI-I16 result: written=%d frames, requested=%d frames",
         written, num_frames);

    if (written < 0) {
        LOGE("nativeWritePcmI16StaticImpl: driver->writeI16 returned %d (frames=%d, bufLen=%d)",
             written, num_frames, (int)len);
    }

    return written;
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_UsbDacPlugin_nativeIsActiveStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr) {
    auto* driver = reinterpret_cast<UsbDacDriver*>(native_ptr);
    if (driver == nullptr) {
        LOGW("nativeIsActiveStaticImpl: null driver (ptr=0x%llx)", (long long)native_ptr);
        return JNI_FALSE;
    }
    bool active = driver->isActive();
    LOGV("nativeIsActiveStaticImpl(ptr=0x%llx) = %s",
         (long long)native_ptr, active ? "true" : "false");
    return active ? JNI_TRUE : JNI_FALSE;
}

} // extern "C"
