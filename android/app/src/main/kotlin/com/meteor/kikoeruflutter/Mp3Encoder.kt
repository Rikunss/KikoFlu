package com.meteor.kikoeruflutter

/**
 * Kotlin wrapper for the LAME MP3 encoder JNI library.
 *
 * LAME is bundled as a native static library and exposed via JNI in
 * `mp3_encoder_jni.cpp`. This class loads the shared library lazily
 * and forwards calls to the native side.
 *
 * If the native library is not available (e.g. LAME source was not
 * bundled at build time), [init] returns false and [isAvailable]
 * reports false. Callers should fall back to another format.
 */
class Mp3Encoder {

    private var handle: Long = 0

    /**
     * True if the native LAME library was successfully loaded.
     * Check this before calling [init].
     */
    val isAvailable: Boolean
        get() = libraryLoaded

    private var inited = false

    /**
     * Initialize the encoder.
     *
     * @param sampleRate  Input sample rate (Hz). MP3 supports
     *                    32000, 44100, 48000. Other values will be
     *                    re-mapped to 44100 by the caller.
     * @param channels    1 (mono) or 2 (stereo)
     * @param bitrateKbps Target bitrate in kbps. Defaults to 320.
     * @return true on success, false on failure or if library is missing
     */
    fun init(sampleRate: Int, channels: Int, bitrateKbps: Int = 320): Boolean {
        if (!libraryLoaded) return false
        if (inited) close()
        return try {
            handle = nativeInit(sampleRate, channels, bitrateKbps)
            inited = handle != 0L
            inited
        } catch (e: UnsatisfiedLinkError) {
            inited = false
            false
        } catch (e: Throwable) {
            inited = false
            false
        }
    }

    /**
     * Encode a chunk of interleaved 16-bit PCM samples.
     *
     * @param pcm Interleaved 16-bit PCM samples (L, R, L, R, …)
     * @return    MP3 frame bytes. May be empty if the encoder is
     *            still buffering. Never null.
     */
    fun encode(pcm: ShortArray): ByteArray {
        if (!inited || handle == 0L) return ByteArray(0)
        return try {
            nativeEncode(handle, pcm) ?: ByteArray(0)
        } catch (e: UnsatisfiedLinkError) {
            ByteArray(0)
        } catch (e: Throwable) {
            ByteArray(0)
        }
    }

    /**
     * Flush any remaining buffered MP3 frames.
     * Call once after all PCM chunks have been encoded.
     */
    fun flush(): ByteArray {
        if (!inited || handle == 0L) return ByteArray(0)
        return try {
            nativeFlush(handle) ?: ByteArray(0)
        } catch (e: UnsatisfiedLinkError) {
            ByteArray(0)
        } catch (e: Throwable) {
            ByteArray(0)
        }
    }

    /**
     * Release all native resources. Safe to call multiple times.
     */
    fun close() {
        if (inited && handle != 0L) {
            try {
                nativeClose(handle)
            } catch (_: UnsatisfiedLinkError) {
                // ignore
            } catch (_: Throwable) {
                // ignore
            }
            handle = 0
            inited = false
        }
    }

    protected fun finalize() {
        close()
    }

    companion object {
        @Volatile
        private var libraryLoaded: Boolean = false
        @Volatile
        private var loadAttempted: Boolean = false

        init {
            tryLoad()
        }

        private fun tryLoad() {
            if (loadAttempted) return
            loadAttempted = true
            try {
                System.loadLibrary("mp3_encoder_jni")
                libraryLoaded = true
            } catch (e: UnsatisfiedLinkError) {
                libraryLoaded = false
            } catch (e: Throwable) {
                libraryLoaded = false
            }
        }

        /**
         * Returns true if the native LAME library was successfully loaded.
         * Safe to call from any thread.
         */
        @JvmStatic
        fun isLibraryLoaded(): Boolean = libraryLoaded
    }

    private external fun nativeInit(sampleRate: Int, channels: Int, bitrateKbps: Int): Long
    private external fun nativeEncode(handle: Long, pcm: ShortArray): ByteArray?
    private external fun nativeFlush(handle: Long): ByteArray?
    private external fun nativeClose(handle: Long)
}
