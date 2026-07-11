import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import '../services/log_service.dart';
import '../services/floating_lyric_service.dart';
import '../services/audio_player_service.dart';
import '../models/lyric.dart';
import 'lyric_provider.dart';
import 'floating_lyric_style_provider.dart';

/// 悬浮字幕开关状态
/// 使用后台 Stream 监听机制自动更新，无需依赖 UI Provider
final floatingLyricEnabledProvider =
    StateNotifierProvider<FloatingLyricEnabledNotifier, bool>((ref) {
  return FloatingLyricEnabledNotifier(ref);
});

/// 悬浮字幕触摸开关（仅 Android，默认允许触摸）
final floatingLyricTouchEnabledProvider =
    StateNotifierProvider<FloatingLyricTouchEnabledNotifier, bool>((ref) {
  return FloatingLyricTouchEnabledNotifier(ref);
});

/// 悬浮窗 FPS 显示开关（仅 iOS）
final floatingLyricFPSEnabledProvider =
    StateNotifierProvider<FloatingLyricFPSEnabledNotifier, bool>((ref) {
  return FloatingLyricFPSEnabledNotifier(ref);
});

/// 悬浮窗网速显示开关（仅 iOS）
final floatingLyricNetworkSpeedEnabledProvider =
    StateNotifierProvider<FloatingLyricNetworkSpeedEnabledNotifier, bool>((ref) {
  return FloatingLyricNetworkSpeedEnabledNotifier(ref);
});

class FloatingLyricTouchEnabledNotifier extends StateNotifier<bool> {
  static const _key = 'floating_lyric_touch_enabled';
  final Ref ref;
  StreamSubscription<bool>? _touchEnabledSubscription;

  FloatingLyricTouchEnabledNotifier(this.ref) : super(true) {
    _load();
    _listenToNativeChanges();
  }

  @override
  void dispose() {
    _touchEnabledSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  void _listenToNativeChanges() {
    if (!Platform.isAndroid) return;

    _touchEnabledSubscription =
        FloatingLyricService.instance.onTouchEnabledChanged.listen((enabled) async {
      if (state == enabled) return;

      state = enabled;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    });
  }

  Future<void> setEnabled(bool enabled, {bool applyToWindow = true}) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);

    if (applyToWindow) {
      await FloatingLyricService.instance.setTouchEnabled(enabled);
    }
  }

  Future<void> toggle() async {
    await setEnabled(!state);
  }
}

class FloatingLyricFPSEnabledNotifier extends StateNotifier<bool> {
  static const _key = 'floating_lyric_fps_enabled';
  final Ref ref;

  FloatingLyricFPSEnabledNotifier(this.ref) : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
    if (state) {
      await FloatingLyricService.instance.setFPSEnabled(true);
    }
  }

  Future<void> toggle() async {
    final newValue = !state;
    state = newValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, newValue);
    await FloatingLyricService.instance.setFPSEnabled(newValue);
  }
}

class FloatingLyricNetworkSpeedEnabledNotifier extends StateNotifier<bool> {
  static const _key = 'floating_lyric_network_speed_enabled';
  final Ref ref;

  FloatingLyricNetworkSpeedEnabledNotifier(this.ref) : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
    if (state) {
      await FloatingLyricService.instance.setNetworkSpeedEnabled(true);
    }
  }

  Future<void> toggle() async {
    final newValue = !state;
    state = newValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, newValue);
    await FloatingLyricService.instance.setNetworkSpeedEnabled(newValue);
  }
}

class FloatingLyricEnabledNotifier extends StateNotifier<bool> {
  static const _key = 'floating_lyric_enabled';
  final Ref ref;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _trackSubscription;
  StreamSubscription? _closeSubscription;
  ProviderSubscription? _lyricStateSubscription;
  String? _lastTrackId;

  FloatingLyricEnabledNotifier(this.ref) : super(false) {
    _load();
    _listenToCloseEvent();
  }

  @override
  void dispose() {
    _stopBackgroundUpdate();
    _closeSubscription?.cancel();
    super.dispose();
  }

  void _listenToCloseEvent() {
    _closeSubscription =
        FloatingLyricService.instance.onClose.listen((_) async {
      if (state) {
        state = false;
        _stopBackgroundUpdate();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_key, false);
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;

    if (state) {
      _showFloatingLyric();
    }
  }

  Future<void> toggle() async {
    final newValue = !state;

    if (newValue) {
      final hasPermission = await FloatingLyricService.instance.hasPermission();
      if (!hasPermission) {
        final granted = await FloatingLyricService.instance.requestPermission();
        if (!granted) {
          LogService.instance.warning('[FloatingLyric] 用户未授予悬浮窗权限', tag: 'UI');
          return;
        }
      }

      await _showFloatingLyric();
    } else {
      _stopBackgroundUpdate();
      await FloatingLyricService.instance.hide();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, newValue);
    state = newValue;
  }

  Future<void> _showFloatingLyric() async {
    final style = ref.read(floatingLyricStyleProvider);

    final styleMap = {
      'fontSize': style.fontSize,
      'textColor': style.textColorArgb,
      'backgroundColor': style.backgroundColorArgb,
      'cornerRadius': style.cornerRadius,
      'paddingHorizontal': style.paddingHorizontal,
      'paddingVertical': style.paddingVertical,
    };

    await FloatingLyricService.instance.show('♪ - ♪', style: styleMap);

    if (Platform.isWindows || Platform.isLinux) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    ref.read(floatingLyricStyleProvider.notifier).applyStyle();

    if (Platform.isAndroid) {
      final touchEnabled = ref.read(floatingLyricTouchEnabledProvider);
      await FloatingLyricService.instance.setTouchEnabled(touchEnabled);
    }

    _startBackgroundUpdate();
  }

  /// 启动后台更新监听
  void _startBackgroundUpdate() {
    _stopBackgroundUpdate();
    LogService.instance.debug('[FloatingLyric] 启动后台更新监听', tag: 'UI');

    ref.read(lyricAutoLoaderProvider);

    _positionSubscription =
        AudioPlayerService.instance.positionStream.listen((_) {
      _updateLyricInBackground();
    });

    _playingSubscription =
        AudioPlayerService.instance.playerStateStream.listen((_) {
      _updateLyricInBackground();
    });

    _trackSubscription =
        AudioPlayerService.instance.currentTrackStream.listen((track) {
      LogService.instance.debug(
          '[FloatingLyric] 收到音轨事件: id=${track?.id}, title=${track?.title}, lastId=$_lastTrackId', tag: 'UI');
      if (track?.id != _lastTrackId) {
        _lastTrackId = track?.id;
        LogService.instance.debug('[FloatingLyric] ✓ 音轨切换确认: ${track?.title}', tag: 'UI');
        FloatingLyricService.instance.updateText('♪ 加载字幕中 ♪');

        if (track != null) {
          final fileListState = ref.read(fileListControllerProvider);
          if (fileListState.files.isNotEmpty) {
            LogService.instance.debug('[FloatingLyric] 主动触发字幕加载', tag: 'UI');
            ref.read(lyricControllerProvider.notifier).loadLyricForTrack(
                  track,
                  fileListState.files,
                );
          } else {
            LogService.instance.debug('[FloatingLyric] 文件列表为空，无法加载字幕', tag: 'UI');
          }
        }
      } else {          LogService.instance.debug('[FloatingLyric] ✗ 相同音轨，忽略', tag: 'UI');
      }
    });

    _lyricStateSubscription = ref.listen<LyricState>(
      lyricControllerProvider,
      (previous, next) {
        if (previous?.isLoading == true && next.isLoading == false) {
          LogService.instance.debug('[FloatingLyric] 字幕加载完成，更新悬浮窗', tag: 'UI');
          _updateLyricInBackground();
        }
        else if (previous?.lyrics != next.lyrics && !next.isLoading) {
          LogService.instance.debug('[FloatingLyric] 字幕内容变化，更新悬浮窗', tag: 'UI');
          _updateLyricInBackground();
        }
      },
    );
  }

  /// 停止后台更新监听
  void _stopBackgroundUpdate() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _playingSubscription?.cancel();
    _playingSubscription = null;
    _trackSubscription?.cancel();
    _trackSubscription = null;
    _lyricStateSubscription?.close();
    _lyricStateSubscription = null;
  }

  /// 在后台更新字幕（不依赖 Provider watch）
  void _updateLyricInBackground() {
    final isPlaying = AudioPlayerService.instance.playing;
    final lyricState = ref.read(lyricControllerProvider);
    final currentPosition = AudioPlayerService.instance.position;

    String displayText;
    if (!isPlaying) {
      displayText = '♪ - ♪';
    } else if (lyricState.lyrics.isNotEmpty) {
      final displayLyrics = lyricState.displayLyrics;
      final currentLyric =
          LyricParser.getCurrentLyric(displayLyrics, currentPosition);

      if (currentLyric != null && currentLyric.trim().isNotEmpty) {
        displayText = currentLyric;
      } else {
        displayText = '♪ - ♪';
      }
    } else {
      displayText = '♪ - ♪';
    }

    FloatingLyricService.instance.updateText(displayText);
  }

  /// 更新悬浮字幕文本
  Future<void> updateText(String text) async {
    if (state) {
      await FloatingLyricService.instance.updateText(text);
    }
  }
}