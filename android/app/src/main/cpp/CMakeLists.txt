cmake_minimum_required(VERSION 3.18.1)
project("aaudio_exclusive")

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
