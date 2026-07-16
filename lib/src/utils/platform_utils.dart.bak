import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../services/log_service.dart';

/// Menetapkan environment variable lintas platform.
///
/// Windows: menggunakan `SetEnvironmentVariableW` dari kernel32.dll.
/// macOS/Linux: menggunakan `setenv` dari libc.
void setEnv(String key, String value) {
  if (Platform.isWindows) {
    final keyNative = key.toNativeUtf16();
    final valueNative = value.toNativeUtf16();
    try {
      final setEnvironmentVariable = ffi.DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
              ffi.Int32 Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>),
              int Function(ffi.Pointer<Utf16>,
                  ffi.Pointer<Utf16>)>('SetEnvironmentVariableW');
      setEnvironmentVariable(keyNative, valueNative);
    } finally {
      calloc.free(keyNative);
      calloc.free(valueNative);
    }
  } else if (Platform.isMacOS || Platform.isLinux) {
    final keyNative = key.toNativeUtf8();
    final valueNative = value.toNativeUtf8();
    try {
      final setenv = ffi.DynamicLibrary.process().lookupFunction<
          ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32),
          int Function(
              ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int)>('setenv');
      setenv(keyNative, valueNative, 1);
    } finally {
      calloc.free(keyNative);
      calloc.free(valueNative);
    }
  }
}

/// Eager init: panggil sqfliteFfiInit untuk memuat native library.
void initSqfliteFfi() {
  sqfliteFfiInit();
  LogService.instance.debug('[Sqflite] FFI initialized', tag: 'Database');
}

/// Set database factory dengan lazy init callback.
/// Fungsi ini dipanggil setelah initSqfliteFfi().
void setupSqfliteDatabaseFactory() {
  databaseFactory = createDatabaseFactoryFfi(ffiInit: initSqfliteFfi);
  LogService.instance.debug('[Sqflite] Database factory configured', tag: 'Database');
}