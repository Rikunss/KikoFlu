// ────────────────────────────────────────────────────────────
// AAudio Exclusive Mode Player — Implementation
// ────────────────────────────────────────────────────────────
// Uses Android's AAudio C API via dynamic loading (dlopen/dlsym)
// at runtime. This avoids compile/link-time dependency on the
// AAudio library, enabling the same APK to run on API 24+ while
// only calling AAudio functions on devices that support it (API 26+).
// ────────────────────────────────────────────────────────────

#include "aaudio_player.h"

// We include the AAudio header only for type definitions (enums, structs).
// Function calls are resolved via dlsym at runtime.
#include <aaudio/AAudio.h>

// AAudio format constants that are only available in the NDK headers
// starting from API level 31 (Android 12). Since KikoFlu targets API 24,
// these may not be defined in the NDK headers. The values are fixed in
// the AAudio specification and never change, so we define them manually.
// AAudio format constants — values from NDK AAudio.h for API 31+.
// PCM_I24_PACKED=3, PCM_I32=4, PCM_FLOAT=2, PCM_I16=1.
// These #ifndef guards allow compilation against older NDK headers (API<31)
// where these constants may not exist.
#ifndef AAUDIO_FORMAT_PCM_I24_PACKED
#define AAUDIO_FORMAT_PCM_I24_PACKED ((aaudio_format_t) 3)
#endif
#ifndef AAUDIO_FORMAT_PCM_I32
#define AAUDIO_FORMAT_PCM_I32 ((aaudio_format_t) 4)
#endif

#include <android/api-level.h>
#include <android/log.h>
#include <dlfcn.h>
#include <mutex>
#include <memory>
#include <atomic>
#include <cstring>
#include <cmath>

#define LOG_TAG "AaudioExclusive"
#define LOGV(...) __android_log_print(ANDROID_LOG_VERBOSE, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// ── Runtime AAudio function pointers ──
// Loaded via dlopen("libaaudio.so") + dlsym at runtime.
// Only populated on API 26+ devices where libaaudio.so exists.
static struct AaudioApi {
    bool loaded;
    void* handle;

    // Exact AAudio C API symbol names — used directly in dlsym() calls
    aaudio_result_t (*AAudio_createStreamBuilder)(AAudioStreamBuilder** builder);
    void (*AAudioStreamBuilder_setSharingMode)(AAudioStreamBuilder* builder, aaudio_sharing_mode_t mode);
    void (*AAudioStreamBuilder_setPerformanceMode)(AAudioStreamBuilder* builder, aaudio_performance_mode_t mode);
    void (*AAudioStreamBuilder_setFormat)(AAudioStreamBuilder* builder, aaudio_format_t format);
    void (*AAudioStreamBuilder_setSampleRate)(AAudioStreamBuilder* builder, int32_t sampleRate);
    void (*AAudioStreamBuilder_setChannelCount)(AAudioStreamBuilder* builder, int32_t channelCount);
    void (*AAudioStreamBuilder_setBufferCapacityInFrames)(AAudioStreamBuilder* builder, int32_t numFrames);
    void (*AAudioStreamBuilder_setDeviceId)(AAudioStreamBuilder* builder, int32_t deviceId);
    aaudio_result_t (*AAudioStreamBuilder_openStream)(AAudioStreamBuilder* builder, AAudioStream** stream);
    aaudio_result_t (*AAudioStreamBuilder_delete)(AAudioStreamBuilder* builder);

    aaudio_sharing_mode_t (*AAudioStream_getSharingMode)(AAudioStream* stream);
    int32_t (*AAudioStream_getSampleRate)(AAudioStream* stream);
    int32_t (*AAudioStream_getChannelCount)(AAudioStream* stream);
    aaudio_format_t (*AAudioStream_getFormat)(AAudioStream* stream);
    int32_t (*AAudioStream_getFramesPerBurst)(AAudioStream* stream);
    int32_t (*AAudioStream_getBufferCapacityInFrames)(AAudioStream* stream);
    int32_t (*AAudioStream_getBufferSizeInFrames)(AAudioStream* stream);

    aaudio_result_t (*AAudioStream_requestStart)(AAudioStream* stream);
    aaudio_result_t (*AAudioStream_requestStop)(AAudioStream* stream);
    aaudio_result_t (*AAudioStream_close)(AAudioStream* stream);

    aaudio_result_t (*AAudioStream_write)(AAudioStream* stream, const void* buffer, int32_t numFrames, int64_t timeoutNanoseconds);
    aaudio_result_t (*AAudioStream_getFramesRead)(AAudioStream* stream, int64_t* frames);
    aaudio_result_t (*AAudioStream_getFramesWritten)(AAudioStream* stream, int64_t* frames);
    aaudio_stream_state_t (*AAudioStream_getState)(AAudioStream* stream);
} s_aaudio = {false, nullptr};

// ── State-to-string helper ──
// Converts AAudio stream state enum to human-readable name.
static const char* aaudioStateToString(aaudio_stream_state_t state) {
    switch (state) {
        case AAUDIO_STREAM_STATE_UNINITIALIZED: return "UNINITIALIZED(0)";
        case AAUDIO_STREAM_STATE_UNKNOWN:       return "UNKNOWN(1)";
        case AAUDIO_STREAM_STATE_OPEN:          return "OPEN(2)";
        case AAUDIO_STREAM_STATE_STARTING:      return "STARTING(3)";
        case AAUDIO_STREAM_STATE_STARTED:       return "STARTED(4)";
        case AAUDIO_STREAM_STATE_PAUSING:       return "PAUSING(5)";
        case AAUDIO_STREAM_STATE_PAUSED:        return "PAUSED(6)";
        case AAUDIO_STREAM_STATE_FLUSHING:      return "FLUSHING(7)";
        case AAUDIO_STREAM_STATE_FLUSHED:       return "FLUSHED(8)";
        case AAUDIO_STREAM_STATE_STOPPING:      return "STOPPING(9)";
        case AAUDIO_STREAM_STATE_STOPPED:       return "STOPPED(10)";
        case AAUDIO_STREAM_STATE_DISCONNECTED:  return "DISCONNECTED(11)";
        default:                                return "UNKNOWN";
    }
}

// ── Load AAudio library at runtime ──
// Called once. Returns true if libaaudio.so was loaded and all symbols resolved.
static bool loadAaudioLibrary() {
    if (s_aaudio.loaded) return true;

    // Runtime API level check — AAudio requires API 26+
    if (android_get_device_api_level() < 26) {
        LOGW("AAudio requires API 26+ (device: %d)", android_get_device_api_level());
        return false;
    }

    void* handle = dlopen("libaaudio.so", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        LOGW("Failed to dlopen libaaudio.so: %s", dlerror());
        return false;
    }

    // Load all function pointers using exact symbol names
    #define LOAD_SYM(name) \
        s_aaudio.name = reinterpret_cast<decltype(s_aaudio.name)>(dlsym(handle, #name)); \
        if (!s_aaudio.name) { LOGW("dlsym %s failed: %s", #name, dlerror()); dlclose(handle); return false; }

    LOAD_SYM(AAudio_createStreamBuilder);
    LOAD_SYM(AAudioStreamBuilder_setSharingMode);
    LOAD_SYM(AAudioStreamBuilder_setPerformanceMode);
    LOAD_SYM(AAudioStreamBuilder_setFormat);
    LOAD_SYM(AAudioStreamBuilder_setSampleRate);
    LOAD_SYM(AAudioStreamBuilder_setChannelCount);
    LOAD_SYM(AAudioStreamBuilder_setBufferCapacityInFrames);
    LOAD_SYM(AAudioStreamBuilder_setDeviceId);
    LOAD_SYM(AAudioStreamBuilder_openStream);
    LOAD_SYM(AAudioStreamBuilder_delete);
    LOAD_SYM(AAudioStream_getSharingMode);
    LOAD_SYM(AAudioStream_getSampleRate);
    LOAD_SYM(AAudioStream_getChannelCount);
    LOAD_SYM(AAudioStream_getFormat);
    LOAD_SYM(AAudioStream_getFramesPerBurst);
    LOAD_SYM(AAudioStream_getBufferCapacityInFrames);
    LOAD_SYM(AAudioStream_getBufferSizeInFrames);
    LOAD_SYM(AAudioStream_requestStart);
    LOAD_SYM(AAudioStream_requestStop);
    LOAD_SYM(AAudioStream_close);
    LOAD_SYM(AAudioStream_write);
    LOAD_SYM(AAudioStream_getFramesRead);
    LOAD_SYM(AAudioStream_getFramesWritten);
    LOAD_SYM(AAudioStream_getState);

    #undef LOAD_SYM

    s_aaudio.handle = handle;
    s_aaudio.loaded = true;
    LOGI("AAudio library loaded successfully");
    return true;
}

class AaudioExclusivePlayer::Impl {
public:
    Impl()
        : stream_(nullptr),
          builder_(nullptr),
          sampleRate_(0),
          channelCount_(0),
          bitsPerSample_(0),
          isExclusive_(false),
          isActive_(false),
          streamStarted_(false) {}

    ~Impl() { destroy(); }

    bool init(int32_t sampleRate, int32_t channelCount, int32_t bitsPerSample, int32_t deviceId = 0) {
        std::lock_guard<std::mutex> lock(mutex_);

        LOGI("init(sampleRate=%d, channels=%d, bits=%d, deviceId=%d)", sampleRate, channelCount, bitsPerSample, deviceId);

        // Ensure AAudio library is loaded
        if (!loadAaudioLibrary()) {
            LOGW("AAudio library not available");
            return false;
        }

        // Destroy any previous stream
        closeStream();

        sampleRate_ = sampleRate;
        channelCount_ = channelCount;
        bitsPerSample_ = bitsPerSample;

        // Always use PCM_FLOAT because all Kotlin write helpers convert samples
        // to float before calling nativeWritePcmFloatStatic. Integer formats
        // (I16, I24_PACKED, I32) expect raw integer data, but we send float
        // data, which would be misinterpreted by the AAudio HAL as integer bit
        // patterns, producing crackling/static noise.
        aaudio_format_t format = AAUDIO_FORMAT_PCM_FLOAT;

        aaudio_result_t result = s_aaudio.AAudio_createStreamBuilder(&builder_);
        if (result != AAUDIO_OK) {
            LOGE("createStreamBuilder failed: %d", result);
            return false;
        }

        s_aaudio.AAudioStreamBuilder_setSharingMode(builder_, AAUDIO_SHARING_MODE_EXCLUSIVE);
        // LOW_LATENCY is REQUIRED for MMAP-based exclusive mode.
        // Without it, AAudio falls back to legacy AudioTrack which does not
        // grant exclusive access on most devices.
        s_aaudio.AAudioStreamBuilder_setPerformanceMode(builder_, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
        s_aaudio.AAudioStreamBuilder_setFormat(builder_, format);
        s_aaudio.AAudioStreamBuilder_setSampleRate(builder_, sampleRate_ > 0 ? sampleRate_ : 48000);
        s_aaudio.AAudioStreamBuilder_setChannelCount(builder_, channelCount_ > 0 ? channelCount_ : 2);
        if (deviceId > 0) {
            s_aaudio.AAudioStreamBuilder_setDeviceId(builder_, deviceId);
            LOGI("Set AAudio deviceId=%d", deviceId);
        }

        result = s_aaudio.AAudioStreamBuilder_openStream(builder_, &stream_);

        if (result != AAUDIO_OK) {
            LOGE("openStream failed: %d", result);
            s_aaudio.AAudioStreamBuilder_delete(builder_);
            builder_ = nullptr;
            stream_ = nullptr;
            return false;
        }

        // Check if exclusive mode was granted
        aaudio_sharing_mode_t actualMode = s_aaudio.AAudioStream_getSharingMode(stream_);
        isExclusive_ = (actualMode == AAUDIO_SHARING_MODE_EXCLUSIVE);

        // If exclusive was requested but denied, log warning
        if (!isExclusive_ && deviceId > 0) {
            LOGW("Exclusive mode denied for USB DAC - using shared mode (still bit-perfect if sample rate matches)");
        }

        // Determine format for status logging
        const char* fmtName;
        switch (format) {
            case AAUDIO_FORMAT_PCM_I16: fmtName = "I16"; break;
            case AAUDIO_FORMAT_PCM_I24_PACKED: fmtName = "I24_PACKED"; break;
            case AAUDIO_FORMAT_PCM_I32: fmtName = "I32"; break;
            case AAUDIO_FORMAT_PCM_FLOAT: fmtName = "FLOAT32"; break;
            default: fmtName = "UNKNOWN"; break;
        }

        // For bit-perfect: ensure sample rate matches the file's native rate
        // If file is 44.1kHz and device supports it, Android mixer won't resample

        LOGI("AAudio opened: exclusive=%d, rate=%dHz, ch=%d, fmt=%s",
             isExclusive_,
             s_aaudio.AAudioStream_getSampleRate(stream_),
             s_aaudio.AAudioStream_getChannelCount(stream_),
             fmtName);

        sampleRate_ = s_aaudio.AAudioStream_getSampleRate(stream_);
        channelCount_ = s_aaudio.AAudioStream_getChannelCount(stream_);

        // Stream opened but NOT started — avoid underruns without audio data
        isActive_ = true;
        streamStarted_ = false;
        return true;
    }

    bool start() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!stream_ || !s_aaudio.loaded) return false;
        if (streamStarted_) return true;

        aaudio_stream_state_t beforeState = s_aaudio.AAudioStream_getState(stream_);
        LOGI("start(): stateBefore=%s", aaudioStateToString(beforeState));
        aaudio_result_t result = s_aaudio.AAudioStream_requestStart(stream_);
        aaudio_stream_state_t afterState = s_aaudio.AAudioStream_getState(stream_);
        if (result != AAUDIO_OK) {
            LOGE("start FAILED: result=%d, stateAfter=%s", result, aaudioStateToString(afterState));
            return false;
        }
        LOGI("start() succeeded: result=%d, stateAfter=%s", result, aaudioStateToString(afterState));

        streamStarted_ = true;
        isActive_ = true;
        return true;
    }

    void stop() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!stream_ || !streamStarted_ || !s_aaudio.loaded) return;
        LOGI("stop()");
        s_aaudio.AAudioStream_requestStop(stream_);
        streamStarted_ = false;
        isActive_ = false;
    }

    void destroy() {
        std::lock_guard<std::mutex> lock(mutex_);
        LOGI("destroy()");
        closeStream();
    }

    int32_t write(const float* data, int32_t numFrames) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!stream_ || !isActive_ || !s_aaudio.loaded) return -1;

        // Log stream state before every write for buffer-full diagnostics
        aaudio_stream_state_t state = s_aaudio.AAudioStream_getState(stream_);
        int32_t bufCap = s_aaudio.AAudioStream_getBufferCapacityInFrames(stream_);
        int32_t bufSize = s_aaudio.AAudioStream_getBufferSizeInFrames(stream_);
        int32_t framesAvail = bufCap - bufSize;
        int64_t wrote = 0, read = 0;
        s_aaudio.AAudioStream_getFramesWritten(stream_, &wrote);
        s_aaudio.AAudioStream_getFramesRead(stream_, &read);
        int64_t timeoutNs = 1000000LL * 500;  // 500ms
        LOGV("[AAUDIO-STREAM] write(frames=%d): state=%s, bufCap=%d, bufSize=%d, framesAvail=%d, wrote=%lld, read=%lld, timeoutNs=%lld",
             numFrames, aaudioStateToString(state), bufCap, bufSize, framesAvail,
             (long long)wrote, (long long)read, (long long)timeoutNs);

        aaudio_result_t result = s_aaudio.AAudioStream_write(stream_, data, numFrames, timeoutNs);

        if (result >= 0) {
            int64_t wroteAfter = 0, readAfter = 0;
            s_aaudio.AAudioStream_getFramesWritten(stream_, &wroteAfter);
            s_aaudio.AAudioStream_getFramesRead(stream_, &readAfter);
            int32_t bufSizeAfter = s_aaudio.AAudioStream_getBufferSizeInFrames(stream_);
            LOGV("[AAUDIO-STREAM] write result: requested=%d, written=%d, stateAfter=%s, bufSizeAfter=%d, framesAvailAfter=%d, wrote=%lld, read=%lld",
                 numFrames, (int)result,
                 aaudioStateToString(s_aaudio.AAudioStream_getState(stream_)),
                 bufSizeAfter,
                 bufCap - bufSizeAfter,
                 (long long)wroteAfter, (long long)readAfter);
        } else {
            LOGW("[AAUDIO-STREAM] write FAILED: requested=%d, result=%d, stateAfter=%s, bufCap=%d, framesAvail=%d",
                 numFrames, (int)result,
                 aaudioStateToString(s_aaudio.AAudioStream_getState(stream_)),
                 bufCap,
                 framesAvail);
        }

        if (result < 0) { LOGE("write failed: %d", result); return static_cast<int32_t>(result); }
        totalFramesWritten_ += static_cast<int32_t>(result);
        return static_cast<int32_t>(result);
    }

    int32_t writeI16(const int16_t* data, int32_t numFrames) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!stream_ || !isActive_ || !s_aaudio.loaded) return -1;

        // Log stream state before every write for buffer-full diagnostics
        aaudio_stream_state_t state = s_aaudio.AAudioStream_getState(stream_);
        int32_t bufCap = s_aaudio.AAudioStream_getBufferCapacityInFrames(stream_);
        int32_t bufSize = s_aaudio.AAudioStream_getBufferSizeInFrames(stream_);
        int32_t framesAvail = bufCap - bufSize;
        int64_t wrote = 0, read = 0;
        s_aaudio.AAudioStream_getFramesWritten(stream_, &wrote);
        s_aaudio.AAudioStream_getFramesRead(stream_, &read);
        int64_t timeoutNs = 1000000LL * 500;  // 500ms
        LOGV("[AAUDIO-STREAM] writeI16(frames=%d): state=%s, bufCap=%d, bufSize=%d, framesAvail=%d, wrote=%lld, read=%lld, timeoutNs=%lld",
             numFrames, aaudioStateToString(state), bufCap, bufSize, framesAvail,
             (long long)wrote, (long long)read, (long long)timeoutNs);

        int32_t totalSamples = numFrames * channelCount_;
        if (static_cast<size_t>(totalSamples) > floatBufferSize_) {
            floatBuffer_.reset(new float[totalSamples]);
            floatBufferSize_ = static_cast<size_t>(totalSamples);
        }
        for (int32_t i = 0; i < totalSamples; i++) {
            floatBuffer_[i] = data[i] / 32768.0f;
        }
        aaudio_result_t result = s_aaudio.AAudioStream_write(stream_, floatBuffer_.get(), numFrames, timeoutNs);

        if (result >= 0) {
            int64_t wroteAfter = 0, readAfter = 0;
            s_aaudio.AAudioStream_getFramesWritten(stream_, &wroteAfter);
            s_aaudio.AAudioStream_getFramesRead(stream_, &readAfter);
            int32_t bufSizeAfter = s_aaudio.AAudioStream_getBufferSizeInFrames(stream_);
            LOGV("[AAUDIO-STREAM] writeI16 result: requested=%d, written=%d, stateAfter=%s, bufSizeAfter=%d, framesAvailAfter=%d, wrote=%lld, read=%lld",
                 numFrames, (int)result,
                 aaudioStateToString(s_aaudio.AAudioStream_getState(stream_)),
                 bufSizeAfter,
                 bufCap - bufSizeAfter,
                 (long long)wroteAfter, (long long)readAfter);
        } else {
            LOGW("[AAUDIO-STREAM] writeI16 FAILED: requested=%d, result=%d, stateAfter=%s, bufCap=%d, framesAvail=%d",
                 numFrames, (int)result,
                 aaudioStateToString(s_aaudio.AAudioStream_getState(stream_)),
                 bufCap,
                 framesAvail);
        }

        if (result < 0) { LOGE("writeI16 failed: %d", result); return static_cast<int32_t>(result); }
        totalFramesWritten_ += static_cast<int32_t>(result);
        return static_cast<int32_t>(result);
    }

    int64_t getTotalFramesWritten() const { return totalFramesWritten_; }
    void resetTotalFramesWritten() { totalFramesWritten_ = 0; }

    bool isExclusive() const { return isExclusive_; }
    bool isActive() const { return isActive_; }
    int32_t getSampleRate() const { return sampleRate_; }

    int32_t getBufferCapacity() const {
        if (!stream_ || !s_aaudio.loaded) return 0;
        return static_cast<int32_t>(s_aaudio.AAudioStream_getBufferCapacityInFrames(stream_));
    }

    double getLatencyMs() const {
        if (!stream_ || sampleRate_ <= 0 || !s_aaudio.loaded) return 0.0;
        int32_t buf = static_cast<int32_t>(s_aaudio.AAudioStream_getBufferSizeInFrames(stream_));
        if (buf <= 0) return 0.0;
        return (static_cast<double>(buf) / sampleRate_) * 1000.0;
    }

    std::string getStatusString() const {
        if (!s_aaudio.loaded) return "AAudio not available";
        if (!stream_) return "Not initialized";
        if (!isActive_) return "Opened (stopped)";
        if (!streamStarted_) return "Opened (prepared)";
        if (isExclusive_) return "Exclusive (AAudio)";
        return "Shared (AAudio)";
    }

private:
    void closeStream() {
        if (!s_aaudio.loaded) return;
        if (stream_ != nullptr) {
            if (streamStarted_) s_aaudio.AAudioStream_requestStop(stream_);
            s_aaudio.AAudioStream_close(stream_);
            stream_ = nullptr;
        }
        if (builder_ != nullptr) {
            s_aaudio.AAudioStreamBuilder_delete(builder_);
            builder_ = nullptr;
        }
        isActive_ = false;
        isExclusive_ = false;
        streamStarted_ = false;
    }

    std::mutex mutex_;
    AAudioStream* stream_;
    AAudioStreamBuilder* builder_;
    int32_t sampleRate_;
    int32_t channelCount_;
    int32_t bitsPerSample_;
    bool isExclusive_;
    bool isActive_;
    bool streamStarted_;
    std::atomic<int64_t> totalFramesWritten_{0};
    std::unique_ptr<float[]> floatBuffer_;
    size_t floatBufferSize_ = 0;
};

// ── Public API ──

AaudioExclusivePlayer::AaudioExclusivePlayer() : pImpl_(new Impl()) {}
AaudioExclusivePlayer::~AaudioExclusivePlayer() { delete pImpl_; }

bool AaudioExclusivePlayer::init(int32_t sr, int32_t ch, int32_t b, int32_t deviceId) { return pImpl_->init(sr, ch, b, deviceId); }
bool AaudioExclusivePlayer::start() { return pImpl_->start(); }
void AaudioExclusivePlayer::stop() { pImpl_->stop(); }
void AaudioExclusivePlayer::destroy() { pImpl_->destroy(); }
int32_t AaudioExclusivePlayer::write(const float* d, int32_t n) { return pImpl_->write(d, n); }
int32_t AaudioExclusivePlayer::writeI16(const int16_t* d, int32_t n) { return pImpl_->writeI16(d, n); }
int64_t AaudioExclusivePlayer::getTotalFramesWritten() const { return pImpl_->getTotalFramesWritten(); }
void AaudioExclusivePlayer::resetTotalFramesWritten() { pImpl_->resetTotalFramesWritten(); }
bool AaudioExclusivePlayer::isExclusive() const { return pImpl_->isExclusive(); }
bool AaudioExclusivePlayer::isActive() const { return pImpl_->isActive(); }
int32_t AaudioExclusivePlayer::getSampleRate() const { return pImpl_->getSampleRate(); }
int32_t AaudioExclusivePlayer::getBufferCapacity() const { return pImpl_->getBufferCapacity(); }
double AaudioExclusivePlayer::getLatencyMs() const { return pImpl_->getLatencyMs(); }
std::string AaudioExclusivePlayer::getStatusString() const { return pImpl_->getStatusString(); }
