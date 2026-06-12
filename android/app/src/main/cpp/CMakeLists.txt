cmake_minimum_required(VERSION 3.18.1)
project("kikoeru_native")

# ──────────────────────────────────────────────
# AAudio Exclusive Mode — Native C++ Library
# ──────────────────────────────────────────────
# Uses Android's AAudio C API via dynamic loading (dlopen/dlsym)
# at runtime. This avoids compile-time and link-time dependency
# on the AAudio library, allowing the same APK to run on both
# API 24 (AAudio unavailable) and API 26+ (AAudio available).
# ──────────────────────────────────────────────

# ── Source files ──
add_library(
    aaudio_exclusive
    SHARED
    aaudio_player.cpp
    jni_bridge.cpp
)

# ── Target includes ──
target_include_directories(
    aaudio_exclusive
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# ── Link libraries ──
# AAudio is NOT linked at compile time. We use dlopen("libaaudio.so")
# at runtime to dynamically load AAudio functions only on API 26+.
target_link_libraries(
    aaudio_exclusive
    dl          # dlopen/dlsym for runtime AAudio loading
    android
    log
)

# ── C++ standard ──
set_target_properties(
    aaudio_exclusive
    PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

# ── Compiler flags ──
target_compile_options(
    aaudio_exclusive
    PRIVATE
    -Wall -Wextra -Wno-unused-parameter
)

# ──────────────────────────────────────────────
# LAME MP3 Encoder — Static Library
# ──────────────────────────────────────────────
# Bundled LAME source is required for MP3 encoding on Android,
# because MediaCodec does NOT provide a software MP3 encoder
# on most devices (only decoders).
#
# Setup instructions:
#   1. Download LAME 3.100 source from:
#      https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download
#   2. Extract to android/app/src/main/cpp/lame/
#      The folder should contain: lame/include/lame.h
#   3. Rebuild: flutter clean && flutter run
# ──────────────────────────────────────────────

set(LAME_DIR ${CMAKE_CURRENT_SOURCE_DIR}/lame)

if(EXISTS ${LAME_DIR}/include/lame.h)
    message(STATUS "LAME source found at ${LAME_DIR} — building MP3 encoder")

    file(GLOB LAME_SOURCES
        "${LAME_DIR}/libmp3lame/*.c"
    )
    # Remove main() entry point, decoder-only files, and test files
    list(FILTER LAME_SOURCES EXCLUDE REGEX ".*/(main|lametest|mpglib_interface)\\.[cC]$")

    add_library(mp3lame STATIC ${LAME_SOURCES})

    target_include_directories(mp3lame PUBLIC
        ${LAME_DIR}/include
        ${LAME_DIR}
        ${LAME_DIR}/libmp3lame
    )

    target_compile_options(mp3lame PRIVATE
        -O2
        -w
        -fno-strict-aliasing
        -DHAVE_MPGLIB
        -DLAMEPARSE
        -DHAVE_MEMCPY=1
    )

    # JNI wrapper for LAME
    add_library(mp3_encoder_jni SHARED mp3_encoder_jni.cpp)
    target_include_directories(mp3_encoder_jni PRIVATE
        ${LAME_DIR}/include
    )
    target_link_libraries(mp3_encoder_jni mp3lame log)

    set(LAME_AVAILABLE TRUE)
else()
    message(WARNING
        "LAME source NOT found at ${LAME_DIR}.\n"
        "MP3 encoding will be DISABLED on Android.\n"
        "To enable: download LAME 3.100 from sourceforge.net and extract to that path.")
    set(LAME_AVAILABLE FALSE)
endif()

