#ifndef AAUDIO_PLAYER_H
#define AAUDIO_PLAYER_H

#include <cstdint>
#include <functional>
#include <string>

/**
 * AAudio exclusive-mode audio player.
 *
 * Uses Android's AAudio C API directly via runtime dynamic loading
 * (dlopen/dlsym) — see aaudio_player.cpp for the dynamic loading
 * mechanism. No compile-time or link-time dependency on libaaudio.so.
 *
 * Opens an AAudio stream with AAUDIO_SHARING_MODE_EXCLUSIVE to bypass
 * the Android AudioFlinger mixer for bit-perfect output.
 *
 * Key behaviors:
 * - Requests exclusive mode; verifies if granted via getSharingMode()
 * - Volume is entirely controlled at the app level (AudioManager is locked)
 * - Audio data is provided via synchronous write() calls
 *
 * Before using this class:
 * 1. Call init() with the desired audio parameters
 * 2. Call start() to begin playback
 * 3. Feed PCM data via write() or writeI16() calls
 * 4. Call stop() and destroy() to clean up
 */
class AaudioExclusivePlayer {
public:
    AaudioExclusivePlayer();
    ~AaudioExclusivePlayer();

    // No copy/move
    AaudioExclusivePlayer(const AaudioExclusivePlayer&) = delete;
    AaudioExclusivePlayer& operator=(const AaudioExclusivePlayer&) = delete;

    /**
     * Initialize the AAudio stream with the given parameters.
     *
     * @param sampleRate  Target sample rate (e.g., 44100, 48000, 96000, 192000)
     * @param channelCount  Number of channels (1 = mono, 2 = stereo)
     * @param bitsPerSample  Bit depth (16 or 24 or 32)
     * @return true if the stream was created successfully (may fall back to shared mode)
     */
    bool init(int32_t sampleRate, int32_t channelCount, int32_t bitsPerSample, int32_t deviceId = 0);

    /**
     * Start audio playback.
     * @return true if playback started successfully
     */
    bool start();

    /**
     * Stop audio playback.
     */
    void stop();

    /**
     * Close the stream and release resources.
     */
    void destroy();

    /**
     * Write PCM audio data to the stream (float format).
     *
     * @param data  Pointer to PCM float audio buffer (-1.0 to 1.0)
     * @param numFrames  Number of audio frames to write
     * @return Number of frames actually written, or negative on error
     */
    int32_t write(const float* data, int32_t numFrames);

    /**
     * Write PCM I16 audio data to the stream (auto-converted to float).
     *
     * @param data  Pointer to PCM int16_t audio buffer
     * @param numFrames  Number of audio frames to write
     * @return Number of frames actually written, or negative on error
     */
    int32_t writeI16(const int16_t* data, int32_t numFrames);

    /**
     * Get total frames written since last reset.
     */
    int64_t getTotalFramesWritten() const;

    /**
     * Reset the frame counter (call after seek/flush).
     */
    void resetTotalFramesWritten();

    /**
     * Check if the stream was granted exclusive mode.
     * @return true if the stream is in exclusive mode
     */
    bool isExclusive() const;

    /**
     * Check if the stream is currently active.
     */
    bool isActive() const;

    /**
     * Get the actual sample rate of the stream.
     */
    int32_t getSampleRate() const;

    /**
     * Get the buffer capacity in frames.
     */
    int32_t getBufferCapacity() const;

    /**
     * Get the current latency in milliseconds (approximate).
     */
    double getLatencyMs() const;

    /**
     * Get a human-readable status string.
     */
    std::string getStatusString() const;

private:
    // PIMPL idiom — implementation details hidden in .cpp
    class Impl;
    Impl* pImpl_;
};

#endif // AAUDIO_PLAYER_H
