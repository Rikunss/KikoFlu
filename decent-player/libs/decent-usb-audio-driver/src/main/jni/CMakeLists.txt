cmake_minimum_required(VERSION 3.22.1)
project("decent_usb_audio" C CXX)

set(CMAKE_CXX_STANDARD 11)

# ── libFLAC (xiph/flac) ──────────────────────────────────────────────
# The native audio engine (native-audio-engine.cpp) requires libFLAC for
# native FLAC decoding. The source is from the decent-media3-decoder-flac
# module's libflac submodule (cloned from https://github.com/xiph/flac).
set(LIBFLAC_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../decent-media3-decoder-flac/src/main/jni/libflac")

# Disable unnecessary libFLAC features for faster build and fewer deps
set(WITH_OGG OFF CACHE BOOL "Disable Ogg support" FORCE)
set(BUILD_CXXLIBS OFF CACHE BOOL "Disable C++ bindings" FORCE)
set(BUILD_PROGRAMS OFF CACHE BOOL "Disable programs" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "Disable examples" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "Disable tests" FORCE)
set(BUILD_DOCS OFF CACHE BOOL "Disable docs" FORCE)
set(INSTALL_MANPAGES OFF CACHE BOOL "Disable man pages" FORCE)
set(INSTALL_PKGCONFIG_MODULES OFF CACHE BOOL "Disable pkgconfig" FORCE)
set(INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "Disable cmake config" FORCE)

add_subdirectory("${LIBFLAC_SRC_DIR}" "${CMAKE_BINARY_DIR}/libflac" EXCLUDE_FROM_ALL)

# ── FLAC parser source (from decent-media3-decoder-flac) ────────────
# The native audio engine uses FLACParser to decode FLAC frames.
# flac_parser.cc is compiled directly into libdecent_usb_audio.so to avoid
# a runtime dependency on libflacJNI.so.
set(DECENT_FLAC_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../decent-media3-decoder-flac/src/main/jni")

# ── USB audio driver + native audio engine ──────────────────────────
add_library(decent_usb_audio SHARED
    usb-audio-output.cpp
    native-audio-engine.cpp
    "${DECENT_FLAC_SRC_DIR}/flac_parser.cc"
)

target_include_directories(decent_usb_audio PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    "${DECENT_FLAC_SRC_DIR}/include"
    "${LIBFLAC_SRC_DIR}/include"
)

# Hide internal C++ symbols to prevent ODR conflicts with libflacJNI.so
# (which also compiles flac_parser.cc). JNI functions are explicitly
# exported via JNIEXPORT / __attribute__((visibility("default"))).
set_target_properties(decent_usb_audio PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

find_library(log-lib log)
target_link_libraries(decent_usb_audio
    ${log-lib}
    FLAC
)
