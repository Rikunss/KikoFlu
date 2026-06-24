plugins {
    id("com.android.library")
}

android {
    namespace = "com.decent.usbaudio"
    compileSdk = 35

    defaultConfig {
        minSdk = 29
        externalNativeBuild { cmake { cppFlags("") } }
    }

    ndkVersion = "29.0.13113456"

    externalNativeBuild {
        cmake { path("src/main/jni/CMakeLists.txt") }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin { jvmToolchain(17) }
}

dependencies {
    implementation("androidx.core:core-ktx:1.18.0")
}
