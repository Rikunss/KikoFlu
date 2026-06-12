#include <jni.h>
#include <vector>
#include "lame.h"

extern "C" {

/**
 * Initialize LAME encoder.
 *
 * @param sampleRate input sample rate (e.g. 44100, 48000)
 * @param channels   number of channels (1 = mono, 2 = stereo)
 * @param bitrate    bitrate in kbps (e.g. 320 for 320 kbps CBR)
 * @return opaque handle (>0) on success, 0 on failure
 */
JNIEXPORT jlong JNICALL
Java_com_meteor_kikoeruflutter_Mp3Encoder_nativeInit(
    JNIEnv* env, jobject obj, jint sampleRate, jint channels, jint bitrate) {

    lame_global_flags* lame = lame_init();
    if (!lame) return 0;

    lame_set_in_samplerate(lame, sampleRate);
    lame_set_out_samplerate(lame, sampleRate);
    lame_set_num_channels(lame, channels);
    lame_set_brate(lame, bitrate);
    lame_set_quality(lame, 2); // 0=best, 9=worst; 2 is a good default

    if (channels == 1) {
        lame_set_mode(lame, MONO);
    } else {
        lame_set_mode(lame, JOINT_STEREO);
    }

    if (lame_init_params(lame) < 0) {
        lame_close(lame);
        return 0;
    }

    return reinterpret_cast<jlong>(lame);
}

/**
 * Encode a chunk of interleaved 16-bit PCM samples to MP3.
 *
 * @param handle  opaque handle from nativeInit
 * @param pcm     interleaved 16-bit PCM samples (short array)
 * @return        MP3 bytes (may be empty if encoder needs more data)
 */
JNIEXPORT jbyteArray JNICALL
Java_com_meteor_kikoeruflutter_Mp3Encoder_nativeEncode(
    JNIEnv* env, jobject obj, jlong handle, jshortArray pcm) {

    lame_global_flags* lame = reinterpret_cast<lame_global_flags*>(handle);
    if (!lame || !pcm) return nullptr;

    jsize len = env->GetArrayLength(pcm);
    jshort* pcmData = env->GetShortArrayElements(pcm, nullptr);

    int channels = lame_get_num_channels(lame);
    int samplesPerChannel = len / channels;
    int frameSize = 1152 * channels;
    int mp3BufSize = (int)(1.25 * frameSize + 7200);
    std::vector<unsigned char> mp3Buf(mp3BufSize);

    int written = lame_encode_buffer_interleaved(
        lame, pcmData, samplesPerChannel, mp3Buf.data(), mp3BufSize);

    env->ReleaseShortArrayElements(pcm, pcmData, JNI_ABORT);

    if (written < 0) {
        return env->NewByteArray(0);
    }

    jbyteArray result = env->NewByteArray(written);
    if (written > 0) {
        env->SetByteArrayRegion(result, 0, written, reinterpret_cast<jbyte*>(mp3Buf.data()));
    }
    return result;
}

/**
 * Flush any remaining MP3 frames held by the encoder.
 * Should be called once after all PCM data has been encoded.
 *
 * @return  MP3 bytes (may be empty)
 */
JNIEXPORT jbyteArray JNICALL
Java_com_meteor_kikoeruflutter_Mp3Encoder_nativeFlush(
    JNIEnv* env, jobject obj, jlong handle) {

    lame_global_flags* lame = reinterpret_cast<lame_global_flags*>(handle);
    if (!lame) return nullptr;

    std::vector<unsigned char> mp3Buf(7200);
    int written = lame_encode_flush(lame, mp3Buf.data(), (int)mp3Buf.size());

    if (written < 0) {
        return env->NewByteArray(0);
    }

    jbyteArray result = env->NewByteArray(written);
    if (written > 0) {
        env->SetByteArrayRegion(result, 0, written, reinterpret_cast<jbyte*>(mp3Buf.data()));
    }
    return result;
}

/**
 * Release the LAME encoder.
 */
JNIEXPORT void JNICALL
Java_com_meteor_kikoeruflutter_Mp3Encoder_nativeClose(
    JNIEnv* env, jobject obj, jlong handle) {

    lame_global_flags* lame = reinterpret_cast<lame_global_flags*>(handle);
    if (lame) {
        lame_close(lame);
    }
}

} // extern "C"
