import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "我的"界面标签页显示设置
class MyTabsDisplaySettings {
  final bool showOnlineMarks;
  final bool showPlaylists;
  final bool showSubtitleLibrary;
  final bool showStats;

  const MyTabsDisplaySettings({
    this.showOnlineMarks = true,
    this.showPlaylists = true,
    this.showSubtitleLibrary = true,
    this.showStats = true,
  });

  MyTabsDisplaySettings copyWith({
    bool? showOnlineMarks,
    bool? showPlaylists,
    bool? showSubtitleLibrary,
    bool? showStats,
  }) {
    return MyTabsDisplaySettings(
      showOnlineMarks: showOnlineMarks ?? this.showOnlineMarks,
      showPlaylists: showPlaylists ?? this.showPlaylists,
      showSubtitleLibrary: showSubtitleLibrary ?? this.showSubtitleLibrary,
      showStats: showStats ?? this.showStats,
    );
  }
}

/// "我的"界面标签页显示设置控制器
class MyTabsDisplaySettingsNotifier
    extends StateNotifier<MyTabsDisplaySettings> {
  static const String _onlineMarksKey = 'my_tabs_show_online_marks';
  static const String _playlistsKey = 'my_tabs_show_playlists';
  static const String _subtitleLibraryKey = 'my_tabs_show_subtitle_library';
  static const String _statsKey = 'my_tabs_show_stats';

  MyTabsDisplaySettingsNotifier() : super(const MyTabsDisplaySettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = MyTabsDisplaySettings(
        showOnlineMarks: prefs.getBool(_onlineMarksKey) ?? true,
        showPlaylists: prefs.getBool(_playlistsKey) ?? true,
        showSubtitleLibrary: prefs.getBool(_subtitleLibraryKey) ?? true,
        showStats: prefs.getBool(_statsKey) ?? true,
      );
    } catch (e) {
      state = const MyTabsDisplaySettings();
    }
  }

  Future<void> setShowOnlineMarks(bool value) async {
    state = state.copyWith(showOnlineMarks: value);
    await _saveSetting(_onlineMarksKey, value);
  }

  Future<void> setShowPlaylists(bool value) async {
    state = state.copyWith(showPlaylists: value);
    await _saveSetting(_playlistsKey, value);
  }

  Future<void> setShowSubtitleLibrary(bool value) async {
    state = state.copyWith(showSubtitleLibrary: value);
    await _saveSetting(_subtitleLibraryKey, value);
  }

  Future<void> setShowStats(bool value) async {
    state = state.copyWith(showStats: value);
    await _saveSetting(_statsKey, value);
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
    }
  }
}

/// "我的"界面标签页显示设置提供者
final myTabsDisplayProvider =
    StateNotifierProvider<MyTabsDisplaySettingsNotifier, MyTabsDisplaySettings>(
        (ref) {
  return MyTabsDisplaySettingsNotifier();
});