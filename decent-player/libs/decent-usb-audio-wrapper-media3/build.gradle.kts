plugins {
    id("com.android.library")
}

android {
    namespace = "com.decent.usbaudio.media3"
    compileSdk = 35

    defaultConfig {
        minSdk = 29
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin { jvmToolchain(17) }
}

dependencies {
    api(project(":decent-usb-audio-driver"))
    implementation("androidx.core:core-ktx:1.18.0")
    // Use app's existing Media3 version (1.5.1) for compatibility
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-common:1.5.1")
    implementation("androidx.media3:media3-datasource:1.5.1")
    // JSch fork (maintained) — SFTP streaming with native offset seek
    implementation("com.github.mwiede:jsch:0.2.23")
}
