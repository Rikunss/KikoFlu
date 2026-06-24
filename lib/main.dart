import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/app_bootstrap.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/splash_screen.dart';
import 'src/screens/main_screen.dart';
import 'src/widgets/desktop_floating_lyric.dart';
import 'src/utils/theme.dart';
import 'src/utils/global_keys.dart';
import 'src/utils/platform_utils.dart';
import 'src/services/audio_player_service.dart';
<<<<<<< HEAD
import 'src/services/usb_dac_audio_manager.dart';
=======
import 'src/services/hi_res_audio_service.dart';
import 'src/services/streaming_speed_tracker.dart';
>>>>>>> 96f3b38
import 'src/services/ai_download_notification_service.dart';
import 'src/services/log_service.dart';
import 'src/services/batch_transcription_notification_service.dart';
import 'src/services/conversion_notification_service.dart';
import 'src/services/download_service.dart';
import 'src/services/floating_lyric_service.dart';
import 'src/services/home_widget_service.dart';
import 'src/services/mpv_config_service.dart';
import 'src/services/playback_history_service.dart';
import 'src/services/progress_sync_service.dart';
import 'src/services/listening_stats_service.dart';
import 'src/services/bookmark_service.dart';
import 'src/services/app_lock_service.dart';
import 'src/services/screen_state_service.dart';
import 'src/services/subtitle_library_file_watcher.dart';
import 'src/screens/lock_screen.dart';
import 'src/models/work.dart';
import 'package:flutter/services.dart';
import 'l10n/app_localizations.dart';
import 'src/providers/audio_provider.dart';
import 'src/providers/auth_provider.dart';
import 'src/providers/locale_provider.dart';
import 'src/providers/settings_provider.dart';
import 'src/providers/theme_provider.dart';
import 'src/providers/update_provider.dart';
import 'src/widgets/fps_overlay.dart';
import 'src/services/kikoeru_api_service.dart';

void main(List<String> args) {
  AppBootstrap.runWithZone(() async {
    // --- Multi-window mode (floating lyric as separate window) ---
    if (args.firstOrNull == 'multi_window') {
      await _runMultiWindow(args);
      return;
    }

    // --- Desktop-only setup that must happen before any UI ---
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    if (isDesktop) {
      await MpvConfigService.configure();
      JustAudioMediaKit.ensureInitialized();
      await windowManager.ensureInitialized();

      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(1280, 720),
          minimumSize: Size(350, 600),
          center: true,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.normal,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    }

    if (Platform.isWindows || Platform.isLinux) {
      initSqfliteFfi();
      setupSqfliteDatabaseFactory();
    }

    // --- Pre-load theme before single runApp ---
    await ThemeSettingsNotifier.preload();
    final splashSeed = await SplashApp.loadSavedSeedColor();

    // --- CRITICAL: Init Hive + StorageService BEFORE runApp ---
    // AuthNotifier._loadCurrentUser() accesses StorageService synchronously
    // on creation. If runApp creates the widget tree before storage is ready,
    // it throws a HiveError/StateError.
    await AppBootstrap.initEssential(isDesktop: isDesktop);

    // Notifier: signals when heavy init is done → triggers splash cross-fade
    final initComplete = ValueNotifier<bool>(false);

    // --- Single runApp with splash → main cross-fade ---
    runApp(_SplashCrossFade(
      initComplete: initComplete,
      splashSeed: splashSeed,
      child: const ProviderScope(child: KikoeruApp()),
    ));

    // --- Wait for first frame to render so splash screen is visible first ---
    // runApp() schedules root widget attachment asynchronously via Timer.run.
    // Without this delay, AppBootstrap.initialize() starts immediately and may
    // complete before the first frame renders, especially on devices where
    // Impeller/Vulkan shader compilation takes ~2s (Davey! frames).
    // This 100ms is enough for the Timer to fire and the initial frame to begin.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Record when splash became visible (for minimum display duration)
    final splashStart = DateTime.now();

    // --- Remaining heavy initialization (runs while splash is showing) ---
    await AppBootstrap.initialize(isDesktop: isDesktop);
    AppBootstrap.configureSystemUi();

    // --- Ensure splash is visible for at least 1.5 seconds total ---
    // Prevents the splash from flashing and disappearing too quickly when
    // initialization finishes faster than the first frame can render.
    const minSplashDuration = Duration(milliseconds: 1500);
    final splashElapsed = DateTime.now().difference(splashStart);
    if (splashElapsed < minSplashDuration) {
      await Future<void>.delayed(minSplashDuration - splashElapsed);
    }

    // --- Signal init complete → triggers cross-fade transition ---
    initComplete.value = true;
  });
}

/// Run the app in multi-window mode (floating lyric).
Future<void> _runMultiWindow(List<String> args) async {
  final windowId = args.length > 1 ? args[1] : '0';
  Map<String, dynamic> argument;
  try {
    argument = (args.length > 2 && args[2].isNotEmpty)
        ? jsonDecode(args[2]) as Map<String, dynamic>
        : const <String, dynamic>{};
  } catch (e) {
    LogService.instance.warning('[MultiWindow] Failed to parse arguments: $e', tag: 'Main');
    argument = const <String, dynamic>{};
  }

  await windowManager.ensureInitialized();

  runApp(DesktopFloatingLyric(
    windowId: windowId,
    arguments: argument,
  ));
}

class KikoeruApp extends ConsumerStatefulWidget {
  const KikoeruApp({super.key});

  @override
  ConsumerState<KikoeruApp> createState() => _KikoeruAppState();
}

class _KikoeruAppState extends ConsumerState<KikoeruApp>
    with WindowListener, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
    // Initialize audio and video services after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAppServices();
    });
  }

  void _initializeAppServices() {
    _attachPlaybackHistory();
    _initProgressSync();
    ref.read(audioPlayerControllerProvider.notifier).initialize();
    _checkForUpdatesSilently();
    _initHomeWidget();
    _setupWidgetActionHandler();
    _initUsbDacManager();
    _initConversionNotifications();
    _initAiDownloadNotifications();
    _initBatchTranscriptionNotifications();
    _initBookmarkService();
    _initScreenStateService();
    _initListeningStatsSubscription();
    _initSubtitleLibraryFileWatcher();
    _setupAppLockTileHandler();

    // Heavy download disk scan (fire-and-forget, runs after app is visible)
    DownloadService.instance.syncWithDiskAfterInit().catchError((e) {
      LogService.instance.warning('[Main] Disk sync failed: $e', tag: 'Main');
    });
  }

  void _initConversionNotifications() {
    if (!Platform.isAndroid) return;
    ConversionNotificationService.instance.initialize().catchError((e) {
      LogService.instance.warning('[Main] Failed to init conversion notifications: $e', tag: 'Main');
    });
  }

  void _initAiDownloadNotifications() {
    if (!Platform.isAndroid) return;
    AiDownloadNotificationService.instance.initialize().catchError((e) {
      LogService.instance.warning('[Main] Failed to init AI download notifications: $e', tag: 'Main');
    });
  }

  void _initBatchTranscriptionNotifications() {
    if (!Platform.isAndroid) return;
    BatchTranscriptionNotificationService.instance.initialize().catchError((e) {
      LogService.instance.warning('[Main] Failed to init batch transcription notifications: $e', tag: 'Main');
    });
  }

  void _initBookmarkService() {
    BookmarkService.instance.initialize().catchError((e) {
      LogService.instance.warning('[Main] Failed to init bookmark service: $e', tag: 'Main');
    });
  }

  void _initScreenStateService() {
    ScreenStateService.instance.initialize();
  }

  void _initListeningStatsSubscription() {
    ListeningStatsService.instance.subscribeToHistoryUpdates();
  }

  void _initSubtitleLibraryFileWatcher() {
    SubtitleLibraryFileWatcher.instance.start();
  }

  void _setupAppLockTileHandler() {
    if (!Platform.isAndroid) return;
    const tileChannel = MethodChannel('com.kikoeru.flutter/app_lock_tile');
    tileChannel.setMethodCallHandler((call) async {
      if (call.method == 'tileToggled') {
        final enabled = call.arguments as bool? ?? false;
        // Sync the in-memory AppLockService with the tile's toggle
        // The native TileService already updated SharedPreferences.
        // The UI will adapt on next build via _buildHomeScreen() check.
        LogService.instance.debug('[AppLockTile] Toggled to $enabled', tag: 'Main');
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  void _attachPlaybackHistory() {
    final historyService = PlaybackHistoryService.instance;
    historyService.onFetchWork = (workId) async {
      final api = ref.read(kikoeruApiServiceProvider);
      final json = await api.getWork(workId);
      return Work.fromJson(json);
    };
    historyService.attachPlayer(AudioPlayerService.instance);
  }

  void _initProgressSync() {
    // Initialize cross-device progress sync
    ProgressSyncService.instance.init(ref);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    // Dispose services to prevent memory leaks
    AudioPlayerService.instance.dispose();
    HiResAudioService.instance.dispose();
    StreamingSpeedTracker.instance.dispose();
    ListeningStatsService.instance.unsubscribeFromHistoryUpdates();
    PlaybackHistoryService.instance.detach();
    // Flush remaining logs before exit
    LogService.instance.flush();
    super.dispose();
  }

  /// Called when the operating system notifies the app of memory pressure.
  /// Clears Flutter's in-memory image cache to free decoded image data.
  /// This is especially important after increasing [ImageCache.maximumSize]
  /// to 500 images (100 MB) — on low-end devices, the larger cache could
  /// otherwise contribute to Out-Of-Memory (OOM) kills when background apps
  /// consume additional memory.
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      PlaybackHistoryService.instance
          .flushNow(reason: FlushReason.appBackground);

      // Track background time for auto-relock
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        if (AppLockService.instance.isEnabled) {
          AppLockService.instance.notifyAppBackgrounded();
        }
      }
    }

    // Auto-relock check when app returns to foreground
    if (state == AppLifecycleState.resumed) {
      if (AppLockService.instance.isEnabled &&
          AppLockService.instance.notifyAppForegrounded()) {
        setState(() {});
      }
    }

    // On Android, when the app is swiped away from recent apps (detached),
    // fully stop audio playback and dismiss the notification.
    //
    // The sequence: stop() halts the player + transitions processing state
    // to idle → AudioService._observePlaybackState() detects the transition
    // and calls stopSelf() on the native service → notification is dismissed.
    // clearQueue() resets the queue + current track so state is fully clean.
    if (state == AppLifecycleState.detached && Platform.isAndroid) {
      try {
        final service = AudioPlayerService.instance;
        service.audioHandler
            ?.stop()
            .then((_) => service.clearQueue())
            .catchError((_) {});
      } catch (e) {
        // Service may already be disposed — safe to ignore.
      }
    }
  }

  @override
  void onWindowClose() async {
    await PlaybackHistoryService.instance.flushNow(reason: FlushReason.dispose);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await FloatingLyricService.instance.hide();
    }
    super.onWindowClose();
  }

  void _initUsbDacManager() {
    if (!Platform.isAndroid) return;
    UsbDacAudioManager.instance.initialize().catchError((e) {
      debugPrint('[Main] USB DAC manager init failed: $e');
    });
  }

  void _initHomeWidget() {
    // Initialize widget service on Android only
    if (!Platform.isAndroid) return;
    HomeWidgetService.instance.init();
  }

  void _setupWidgetActionHandler() {
    if (!Platform.isAndroid) return;

    const widgetChannel = MethodChannel('com.kikoeru.flutter/home_widget_actions');
    widgetChannel.setMethodCallHandler((call) async {
      final controller = ref.read(audioPlayerControllerProvider.notifier);
      switch (call.method) {
        case 'togglePlayback':
          if (controller.isPlaying) {
            await controller.pause();
          } else {
            await controller.play();
          }
        case 'skipNext':
          await controller.skipToNext();
        case 'skipPrev':
          await controller.skipToPrevious();
      }
    });
  }

  Future<void> _checkForUpdatesSilently() async {
    try {
      final updateService = ref.read(updateServiceProvider);
      final updateInfo = await updateService.checkForUpdates();

      if (updateInfo != null && updateInfo.hasNewVersion) {
        ref.read(updateInfoProvider.notifier).state = updateInfo;
        ref.read(hasNewVersionProvider.notifier).state = true;

        final shouldShow = await updateService.shouldShowRedDot();
        ref.read(showUpdateRedDotProvider.notifier).state = shouldShow;
      }
    } catch (e) {
      LogService.instance.debug('[Update] Check failed: $e', tag: 'Main');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeSettings = ref.watch(themeSettingsProvider);
    final locale = ref.watch(localeProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme? lightScheme =
            themeSettings.colorSchemeType == ColorSchemeType.dynamic
                ? lightDynamic
                : null;
        final ColorScheme? darkScheme =
            themeSettings.colorSchemeType == ColorSchemeType.dynamic
                ? darkDynamic
                : null;

        final ThemeMode mode = switch (themeSettings.themeMode) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
          AppThemeMode.trueBlack => ThemeMode.dark,
        };

        return MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          title: 'Kikoeru',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: locale,
          theme:
              AppTheme.lightTheme(lightScheme, themeSettings.colorSchemeType),
          darkTheme: themeSettings.themeMode == AppThemeMode.trueBlack
              ? AppTheme.trueBlackDarkTheme(
                  darkScheme, themeSettings.colorSchemeType)
              : AppTheme.darkTheme(
                  darkScheme, themeSettings.colorSchemeType),
          themeMode: mode,
          home: _buildHomeScreen(),
          builder: (context, child) {
            return Stack(
              children: [
                if (child != null) child,
                // Global FPS overlay (top-right, togglable via Developer Tools)
                const _FpsOverlayGlobal(),
                // Session-expired dialog listener (must be inside Navigator scope)
                const _SessionExpiredListener(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHomeScreen() {
    final authState = ref.watch(authProvider);
    if (authState.currentUser == null) {
      return const LoginScreen();
    }

    // If app lock is enabled, show lock screen before MainScreen
    // Use lockGeneration as key to force fresh LockScreen on auto-relock
    if (AppLockService.instance.isEnabled) {
      return _LockScreenWrapper(
        key: ValueKey('lock_${AppLockService.instance.lockGeneration}'),
      );
    }

    return const MainScreen();
  }
}

/// Invisible widget inside [MaterialApp.builder] that listens for session
/// expired events (via [AuthState.sessionExpired]) and shows a dialog.
/// Must be rendered INSIDE the [MaterialApp] so [Navigator.of] works.
class _SessionExpiredListener extends ConsumerStatefulWidget {
  const _SessionExpiredListener();

  @override
  ConsumerState<_SessionExpiredListener> createState() =>
      _SessionExpiredListenerState();
}

class _SessionExpiredListenerState
    extends ConsumerState<_SessionExpiredListener> {
  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.sessionExpired && previous?.sessionExpired != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showDialog();
        });
      }
    });
    return const SizedBox.shrink();
  }

  void _showDialog() {
    if (!mounted) return;
    final s = S.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text(
          'Your login session has expired or you have been logged out. '
          'Please log in again to continue.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.ok),
          ),
        ],
      ),
    );
  }
}

/// Global FPS overlay — watches the toggle from Developer Tools.
/// Rendered above all screens via MaterialApp.builder.
class _FpsOverlayGlobal extends ConsumerWidget {
  const _FpsOverlayGlobal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showFps = ref.watch(showFpsOverlayProvider);
    if (!showFps) return const SizedBox.shrink();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 4,
      child: const FpsOverlay(),
    );
  }
}

/// Wrapper widget that shows the [LockScreen] until the user authenticates,
/// then replaces it with [MainScreen].
class _LockScreenWrapper extends ConsumerStatefulWidget {
  const _LockScreenWrapper({super.key});

  @override
  ConsumerState<_LockScreenWrapper> createState() => _LockScreenWrapperState();
}

class _LockScreenWrapperState extends ConsumerState<_LockScreenWrapper>
    with SingleTickerProviderStateMixin {
  bool _unlocked = false;
  late final AnimationController _exitCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeOutCubic),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _exitCtrl.dispose();
    super.dispose();
  }

  void _onUnlocked() {
    _exitCtrl.forward().then((_) {
      if (mounted) {
        setState(() => _unlocked = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return const MainScreen();
    }
    // Stack MainScreen underneath + LockScreen overlay with exit animation
    return Stack(
      children: [
        const MainScreen(),
        FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: LockScreen(
              onUnlocked: _onUnlocked,
            ),
          ),
        ),
      ],
    );
  }
}

/// Cross-fades from splash content to the real app when init completes.
/// Wraps the final app so the transition isn't a hard cut.
///
/// Uses [initComplete] ValueNotifier so the fade only starts after
/// heavy initialization (accounts, database, auth) has finished.
class _SplashCrossFade extends StatefulWidget {
  /// Signals when `AppBootstrap.initialize()` has completed.
  final ValueNotifier<bool> initComplete;

  /// Seed color for the splash theme.
  final Color? splashSeed;

  /// The real app widget tree ([ProviderScope] wrapping [KikoeruApp]).
  final Widget child;

  const _SplashCrossFade({
    required this.initComplete,
    this.splashSeed,
    required this.child,
  });

  @override
  State<_SplashCrossFade> createState() => _SplashCrossFadeState();
}

class _SplashCrossFadeState extends State<_SplashCrossFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {}); // remove splash overlay from tree
        }
      });

    // Wait for init to complete before starting the cross-fade
    widget.initComplete.addListener(_onInitComplete);
  }

  void _onInitComplete() {
    if (widget.initComplete.value && mounted) {
      widget.initComplete.removeListener(_onInitComplete);
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    widget.initComplete.removeListener(_onInitComplete);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seed = widget.splashSeed ?? const Color(0xFF146683);
    // Use light theme by default — will update on first app frame via
    // the real KikoeruApp theme. Splash is brief so this is fine.
    final splashCs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    return Stack(
      alignment: Alignment.topLeft,
      children: [
        // Real app (renders underneath, fully opaque)
        widget.child,

        // Splash overlay (fades out, removed from tree when done)
        if (_ctrl.status != AnimationStatus.completed)
          FadeTransition(
            opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
              CurvedAnimation(
                parent: _ctrl,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: Container(
              color: splashCs.surface,
              child: Theme(
                data: ThemeData(
                  colorScheme: splashCs,
                  useMaterial3: true,
                ),
                child: const Directionality(
                  textDirection: TextDirection.ltr,
                  child: SplashBody(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
