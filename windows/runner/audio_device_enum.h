#pragma once

// Native helpers for enumerating WASAPI render (output) audio devices.
//
// These are exported from the runner executable and called from Dart via
// `DynamicLibrary.process()` (plain FFI — no COM vtable dispatch on the Dart
// side, which crashes on some Windows/Dart toolchain combinations).
//
// `kikoflu_enumerate_audio_devices` returns a UTF-16 JSON string allocated
// with CoTaskMemAlloc, or nullptr on failure. The caller MUST release the
// result with `kikoflu_free_string`.
//
// JSON shape:
// {
//   "default": "<full endpoint id of the default render device or \"\">",
//   "devices": [
//     {
//       "fullId": "<raw IMMDevice::GetId() string>",
//       "name": "<PKEY_Device_FriendlyName>",
//       "formFactor": <int or -1>,
//       "isDefault": <bool>
//     }
//   ]
// }

#ifdef __cplusplus
extern "C" {
#endif

__declspec(dllexport) wchar_t* kikoflu_enumerate_audio_devices(void);

__declspec(dllexport) void kikoflu_free_string(wchar_t* ptr);

#ifdef __cplusplus
}
#endif
