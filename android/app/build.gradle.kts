import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val releaseKeystoreFile = keystoreProperties.getProperty("storeFile")?.let(rootProject::file)
val hasReleaseKeystore = releaseKeystoreFile?.exists() == true

android {
    namespace = "com.meteor.kikoeruflutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.meteor.kikoeruflutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // AAudio exclusive mode — NDK (C++) build configuration
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.18.1+"
        }
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore && releaseKeystoreFile != null) {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // AGP 8.x release builds may load native .so directly from the APK (no extraction),
    // which can cause "Bad JNI version" errors in some older native libraries
    // (e.g. ffmpegkit_abidetect.so). Forcing legacy extraction fixes this.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // AndroidX Media3 (ExoPlayer) for hi-res audio playback
    // FLAC decoding is natively supported by media3-exoplayer
    implementation("androidx.media3:media3-exoplayer:1.5.1")

    // ExoPlayer FFmpeg extension — provides libffmpegJNI.so for software ALAC/FLAC/etc decoding
    // Jellyfin community build of AndroidX Media3 FFmpeg decoder (includes Java + native libs)
    implementation("org.jellyfin.media3:media3-ffmpeg-decoder:1.5.0+1")

    // SAF DocumentFile API — needed by SafFileUtils for content:// URI file access
    implementation("androidx.documentfile:documentfile:1.0.1")

    // Core library desugaring (required by flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
