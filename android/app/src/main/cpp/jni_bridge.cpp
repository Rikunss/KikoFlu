#include <jni.h>
#include <android/log.h>
#include "aaudio_player.h"

#define LOG_TAG "AaudioJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ────────────────────────────────────────────────────────────
// JNI Bridge — Kotlin ↔ C++ AAudio Player
// ────────────────────────────────────────────────────────────
// Connects the Kotlin ExclusiveAudioPlugin to the C++
// AaudioExclusivePlayer via JNI.
//
// Matches external fun declarations in ExclusiveAudioPlugin.kt:
//   private external fun nativeCreatePlayer(): Long
//   private external fun nativeInitPlayer(...): Boolean
//   private external fun nativeStartPlayer(nativePtr: Long): Boolean
//   private external fun nativeStopPlayer(nativePtr: Long)
//   private external fun nativeDestroyPlayer(nativePtr: Long)
//   private external fun nativeIsExclusive(nativePtr: Long): Boolean
//   private external fun nativeGetSampleRate(nativePtr: Long): Int
//   private external fun nativeGetLatencyMs(nativePtr: Long): Double
//   private external fun nativeWritePcmFloat(nativePtr: Long, buffer: FloatArray, numFrames: Int): Int
//   private external fun nativeWritePcmI16(nativePtr: Long, buffer: ShortArray, numFrames: Int): Int
//   private external fun nativeGetFramesWritten(nativePtr: Long): Long
//   private external fun nativeResetFramesWritten(nativePtr: Long)
// ────────────────────────────────────────────────────────────

#ifdef __cplusplus
extern "C" {
#endif

JNIEXPORT jlong JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeCreatePlayer(
    JNIEnv* env, jobject /* thiz */) {
    LOGI("nativeCreatePlayer()");
    auto* player = new AaudioExclusivePlayer();
    return reinterpret_cast<jlong>(player);
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeInitPlayer(
    JNIEnv* env, jobject /* thiz */,
    jlong native_ptr, jint sample_rate, jint channel_count, jint bits_per_sample, jint device_id) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return JNI_FALSE;
    return player->init(sample_rate, channel_count, bits_per_sample, device_id) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeStartPlayer(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return JNI_FALSE;
    return player->start() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeStopPlayer(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player != nullptr) player->stop();
}

JNIEXPORT void JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeDestroyPlayer(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player != nullptr) {
        player->destroy();
        delete player;
    }
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeIsExclusive(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return JNI_FALSE;
    return player->isExclusive() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeGetSampleRate(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return 0;
    return player->getSampleRate();
}

JNIEXPORT jdouble JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeGetLatencyMs(
    JNIEnv* env, jobject /* thiz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return 0.0;
    return player->getLatencyMs();
}

// ── Static versions (used by AaudioAudioSink via ExclusiveAudioPlugin.Companion) ──
// These use JNI global convention: ClassName_methodName for @JvmStatic methods

JNIEXPORT jlong JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeCreatePlayerStaticImpl(
    JNIEnv* env, jclass /* clazz */) {
    LOGI("nativeCreatePlayerStaticImpl()");
    auto* player = new AaudioExclusivePlayer();
    return reinterpret_cast<jlong>(player);
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeInitPlayerStaticImpl(
    JNIEnv* env, jclass /* clazz */,
    jlong native_ptr, jint sample_rate, jint channel_count, jint bits_per_sample, jint device_id) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return JNI_FALSE;
    return player->init(sample_rate, channel_count, bits_per_sample, device_id) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeStartPlayerStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return JNI_FALSE;
    return player->start() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeStopPlayerStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player != nullptr) player->stop();
}

JNIEXPORT void JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeDestroyPlayerStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player != nullptr) {
        player->destroy();
        delete player;
    }
}

JNIEXPORT jboolean JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeIsExclusiveStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return JNI_FALSE;
    return player->isExclusive() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeGetSampleRateStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return 0;
    return player->getSampleRate();
}

JNIEXPORT jint JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeWritePcmFloatStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr,
    jfloatArray buffer, jint num_frames) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return -1;

    jsize len = env->GetArrayLength(buffer);
    if (len <= 0) return 0;

    jfloat* elements = env->GetFloatArrayElements(buffer, nullptr);
    if (elements == nullptr) return -1;

    int32_t written = player->write(elements, num_frames);
    env->ReleaseFloatArrayElements(buffer, elements, JNI_ABORT);
    return static_cast<jint>(written);
}

JNIEXPORT jint JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeWritePcmI16StaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr,
    jshortArray buffer, jint num_frames) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return -1;

    jsize len = env->GetArrayLength(buffer);
    if (len <= 0) return 0;

    jshort* elements = env->GetShortArrayElements(buffer, nullptr);
    if (elements == nullptr) return -1;

    int32_t written = player->writeI16(reinterpret_cast<int16_t*>(elements), num_frames);
    env->ReleaseShortArrayElements(buffer, elements, JNI_ABORT);
    return static_cast<jint>(written);
}

JNIEXPORT jlong JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeGetFramesWrittenStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player == nullptr) return 0;
    return static_cast<jlong>(player->getTotalFramesWritten());
}

JNIEXPORT void JNICALL
Java_com_meteor_kikoeruflutter_ExclusiveAudioPlugin_nativeResetFramesWrittenStaticImpl(
    JNIEnv* env, jclass /* clazz */, jlong native_ptr) {
    auto* player = reinterpret_cast<AaudioExclusivePlayer*>(native_ptr);
    if (player != nullptr) player->resetTotalFramesWritten();
}

#ifdef __cplusplus
}
#endif
