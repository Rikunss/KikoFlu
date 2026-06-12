# === FFmpegKit — keep native JNI wrapper classes ===
# Without these rules, R8 strips/obfuscates the Java JNI bridge classes
# causing UnsatisfiedLinkError in release builds:
#   "Bad JNI version returned from JNI_OnLoad in libffmpegkit_abidetect.so"
-keep class com.antonkarpenko.ffmpegkit.** { *; }


# === Flutter engine deferred components (play core) ===
# The Flutter engine references com.google.android.play.core classes
# for split APK / deferred component loading. R8 removes these if missing.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }


# === Flutter default classes ===
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
