import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../services/account_database.dart';
import '../services/blurhash_service.dart';
import '../services/cache_service.dart';
import '../services/download_service.dart';
import '../services/log_service.dart';
import '../services/storage_service.dart';

/// Kelas yang menangani inisialisasi heavy app di background
/// saat splash screen sedang ditampilkan.
class AppBootstrap {
  AppBootstrap._();

  /// Initialisasi essential storage layer yang HARUS selesai
  /// SEBELUM widget tree dibuat (sebelum runApp).
  ///
  /// Ini diperlukan karena provider seperti [AuthNotifier]
  /// langsung mengakses [StorageService] secara synchronous
  /// di konstruktor (via [_loadCurrentUser]).
  static Future<void> initEssential({bool isDesktop = false}) async {
    if (isDesktop) {
      final appDocDir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter('${appDocDir.path}/KikoFlu');
    } else {
      await Hive.initFlutter();
    }
    await StorageService.init();
  }

  /// Jalankan inisialisasi non-essential setelah app berjalan
  /// (splash screen masih terlihat).
  ///
  /// [initEssential] harus sudah dipanggil SEBELUM [initialize].
  static Future<void> initialize({bool isDesktop = false}) async {
    // Hive + StorageService already initialized by initEssential()

    // Initialize account database
    await AccountDatabase.instance.database;
    await _yield();

    // Cache cleanup on startup (fire-and-forget, runs in background)
    CacheService.checkAndCleanCache(force: true).catchError((e) {
      LogService.instance.error('[Cache] Cache check failed: $e', tag: 'Download');
    });

    // Initialize download service (only load tasks from memory, not disk scan)
    await DownloadService.instance.initialize();
    await _yield();

    // Init blurhash service
    await BlurHashService.instance.init();

    // Configure ImageCache untuk manajemen memori gambar yang optimal.
    PaintingBinding.instance.imageCache.maximumSize = 200;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50 MB
  }

  /// Konfigurasi system UI overlay style dan orientasi.
  static void configureSystemUi() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// Setup zone untuk global error handling dan log capture.
  static void runWithZone(Future<void> Function() body) {
    runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();
        setupLogCapture();
        await body();
      },
      (error, stack) {
        LogService.instance.error('$error\n$stack', tag: 'Zone');
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          parent.print(zone, line);
          LogService.instance.captureOutput(line);
        },
      ),
    );
  }

  /// Yield ≈1 frame (16ms) ke event loop agar Flutter bisa render frame
  /// dan platform channel (sqflite, SharedPreferences) punya slot proses.
  static const _shortDelay = Duration(milliseconds: 16);

  static Future<void> _yield() => Future<void>.delayed(_shortDelay);
}
