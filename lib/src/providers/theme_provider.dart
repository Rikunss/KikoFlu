import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 主题模式枚举
enum AppThemeMode {
  system, // 跟随系统
  light, // 浅色模式
  dark, // 深色模式
  trueBlack, // 纯黑 OLED 模式
}

// 颜色方案类型枚举
enum ColorSchemeType {
  oceanBlue, // 海洋蓝（默认）
  forestGreen, // 森林绿
  sunsetOrange, // 日落橙
  lavenderPurple, // 薰衣草紫
  sakuraPink, // 樱花粉
  crimsonRed, // 绯红
  amberGold, // 琥珀金
  slateGray, // 岩灰
  dynamic, // 系统动态取色
}

// 主题设置状态
class ThemeSettings {
  final AppThemeMode themeMode;
  final ColorSchemeType colorSchemeType;

  const ThemeSettings({
    this.themeMode = AppThemeMode.system,
    this.colorSchemeType = ColorSchemeType.oceanBlue,
  });

  ThemeSettings copyWith({
    AppThemeMode? themeMode,
    ColorSchemeType? colorSchemeType,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      colorSchemeType: colorSchemeType ?? this.colorSchemeType,
    );
  }

  ThemeMode toThemeMode() {
    switch (themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.trueBlack:
        return ThemeMode.dark;
    }
  }
}

// 主题设置控制器
class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  static const String themeModeKey = 'theme_mode';
  static const String colorSchemeTypeKey = 'color_scheme_type';

  /// Pre-loaded settings from SharedPreferences (set before ProviderScope is created).
  static ThemeSettings? _preloaded;

  /// Call in [main] before [runApp] to avoid flashing the default theme.
  static Future<void> preload() async {
    final prefs = await SharedPreferences.getInstance();
    _preloaded = ThemeSettings(
      themeMode: AppThemeMode.values[prefs.getInt(themeModeKey) ?? 0],
      colorSchemeType:
          ColorSchemeType.values[prefs.getInt(colorSchemeTypeKey) ?? 0],
    );
  }

  ThemeSettingsNotifier() : super(_preloaded ?? const ThemeSettings()) {
    _preloaded = null; // one-time use, avoid leaking
    if (state == const ThemeSettings()) {
      // Only load async if no preload was done (splash-only / cold start fallback)
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final themeModeIndex = prefs.getInt(themeModeKey) ?? 0;
    final colorSchemeTypeIndex = prefs.getInt(colorSchemeTypeKey) ?? 0;

    state = ThemeSettings(
      themeMode: AppThemeMode.values[themeModeIndex],
      colorSchemeType: ColorSchemeType.values[colorSchemeTypeIndex],
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(themeModeKey, mode.index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setColorSchemeType(ColorSchemeType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(colorSchemeTypeKey, type.index);
    state = state.copyWith(colorSchemeType: type);
  }
}

// 主题设置提供者
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  return ThemeSettingsNotifier();
});
