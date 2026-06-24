pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "decent-usb-audio"
include(":decent-usb-audio-driver")
include(":decent-usb-audio-wrapper-media3")
include(":decent-media3-decoder-flac")
