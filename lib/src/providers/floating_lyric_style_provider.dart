import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/floating_lyric_service.dart';
import '../utils/theme.dart';
import 'theme_provider.dart';

/// Transparency mode for the floating lyric overlay
enum TransparencyMode {
  pill,   // Background wraps text with padding (default)
  overlay, // Transparent background, only text with shadow
  card,    // Full-width background with larger padding
}

/// Floating lyric style settings
class FloatingLyricStyle {
  final double fontSize;
  final double opacity;
  final Color textColor;
  final Color backgroundColor;
  final double cornerRadius;
  final double paddingHorizontal;
  final double paddingVertical;
  final String fontFamily;
  final FontWeight fontWeight;
  final bool shadowEnabled;
  final double shadowBlur;
  final TransparencyMode transparencyMode;
  final bool showCloseButton;
  final Color shadowColor;

  const FloatingLyricStyle({
    this.fontSize = 14.0,
    this.opacity = 0.88,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0xFF2196F3),
    this.cornerRadius = 16.0,
    this.paddingHorizontal = 20.0,
    this.paddingVertical = 10.0,
    this.fontFamily = '',
    this.fontWeight = FontWeight.bold,
    this.shadowEnabled = true,
    this.shadowBlur = 3.0,
    this.transparencyMode = TransparencyMode.pill,
    this.showCloseButton = false,
    this.shadowColor = const Color(0xCC000000),
  });

  FloatingLyricStyle copyWith({
    double? fontSize,
    double? opacity,
    Color? textColor,
    Color? backgroundColor,
    double? cornerRadius,
    double? paddingHorizontal,
    double? paddingVertical,
    String? fontFamily,
    FontWeight? fontWeight,
    bool? shadowEnabled,
    double? shadowBlur,
    TransparencyMode? transparencyMode,
    bool? showCloseButton,
    Color? shadowColor,
  }) {
    return FloatingLyricStyle(
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      paddingHorizontal: paddingHorizontal ?? this.paddingHorizontal,
      paddingVertical: paddingVertical ?? this.paddingVertical,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      shadowEnabled: shadowEnabled ?? this.shadowEnabled,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      transparencyMode: transparencyMode ?? this.transparencyMode,
      showCloseButton: showCloseButton ?? this.showCloseButton,
      shadowColor: shadowColor ?? this.shadowColor,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fontSize': fontSize,
      'opacity': opacity,
      'textColor': textColor.toARGB32(),
      'backgroundColor': backgroundColor.toARGB32(),
      'cornerRadius': cornerRadius,
      'paddingHorizontal': paddingHorizontal,
      'paddingVertical': paddingVertical,
      'fontFamily': fontFamily,
      'fontWeight': fontWeight.index,
      'shadowEnabled': shadowEnabled,
      'shadowBlur': shadowBlur,
      'transparencyMode': transparencyMode.index,
      'showCloseButton': showCloseButton,
      'shadowColor': shadowColor.toARGB32(),
    };
  }

  factory FloatingLyricStyle.fromMap(Map<String, dynamic> map) {
    return FloatingLyricStyle(
      fontSize: map['fontSize']?.toDouble() ?? 14.0,
      opacity: map['opacity']?.toDouble() ?? 0.95,
      textColor: Color(map['textColor'] ?? Colors.white.toARGB32()),
      backgroundColor:
          Color(map['backgroundColor'] ?? const Color(0xFF000000).toARGB32()),
      cornerRadius: map['cornerRadius']?.toDouble() ?? 16.0,
      paddingHorizontal: map['paddingHorizontal']?.toDouble() ?? 20.0,
      paddingVertical: map['paddingVertical']?.toDouble() ?? 10.0,
      fontFamily: map['fontFamily'] as String? ?? '',
      fontWeight: FontWeight.values[(map['fontWeight'] as int?) ?? 6], // bold default
      shadowEnabled: map['shadowEnabled'] as bool? ?? true,
      shadowBlur: map['shadowBlur']?.toDouble() ?? 3.0,
      transparencyMode: TransparencyMode.values[(map['transparencyMode'] as int?) ?? 0],
      showCloseButton: map['showCloseButton'] as bool? ?? false,
      shadowColor: Color(map['shadowColor'] ?? const Color(0xCC000000).toARGB32()),
    );
  }

  Color get backgroundColorWithOpacity {
    if (transparencyMode == TransparencyMode.overlay) {
      return Colors.transparent;
    }
    return backgroundColor.withValues(alpha: opacity);
  }

  int get textColorArgb => textColor.toARGB32();

  int get backgroundColorArgb {
    final color = backgroundColorWithOpacity;
    return color.toARGB32();
  }

  double get effectivePaddingHorizontal {
    if (transparencyMode == TransparencyMode.card) {
      return paddingHorizontal + 8;
    }
    return paddingHorizontal;
  }

  double get effectivePaddingVertical {
    if (transparencyMode == TransparencyMode.card) {
      return paddingVertical + 6;
    }
    return paddingVertical;
  }

  double get effectiveCornerRadius {
    if (transparencyMode == TransparencyMode.card) {
      return cornerRadius + 4;
    }
    return cornerRadius;
  }
}

/// Floating lyric style Provider
final floatingLyricStyleProvider =
    StateNotifierProvider<FloatingLyricStyleNotifier, FloatingLyricStyle>(
        (ref) {
  return FloatingLyricStyleNotifier(ref);
});

class FloatingLyricStyleNotifier extends StateNotifier<FloatingLyricStyle>
    with WidgetsBindingObserver {
  static const _keyPrefix = 'floating_lyric_style_';
  final Ref ref;
  ProviderSubscription? _themeSubscription;

  FloatingLyricStyleNotifier(this.ref) : super(const FloatingLyricStyle()) {
    WidgetsBinding.instance.addObserver(this);
    _load();
    _listenToThemeChanges();
  }

  @override
  void dispose() {
    _themeSubscription?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _updateColorsFromThemeIfDefault();
  }

  void _listenToThemeChanges() {
    _themeSubscription = ref.listen<ThemeSettings>(themeSettingsProvider, (previous, next) async {
      if (previous == next) return;
      await _updateColorsFromThemeIfDefault();
    });
  }

  Future<void> _updateColorsFromThemeIfDefault() async {
    final prefs = await SharedPreferences.getInstance();
    final hasCustomTextColor = prefs.containsKey('${_keyPrefix}textColor');
    final hasCustomBackgroundColor =
        prefs.containsKey('${_keyPrefix}backgroundColor');

    if (hasCustomTextColor && hasCustomBackgroundColor) return;

    final themeSettings = ref.read(themeSettingsProvider);
    final isDark = themeSettings.themeMode == AppThemeMode.dark ||
        (themeSettings.themeMode == AppThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final colorScheme =
        AppTheme.getColorScheme(themeSettings.colorSchemeType, isDark);

    var newState = state;
    if (!hasCustomTextColor) {
      newState = newState.copyWith(textColor: colorScheme.onPrimary);
    }
    if (!hasCustomBackgroundColor) {
      newState = newState.copyWith(backgroundColor: colorScheme.primary);
    }

    if (newState != state) {
      state = newState;
      _applyStyle();
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeSettings = ref.read(themeSettingsProvider);
    final isDark = themeSettings.themeMode == AppThemeMode.dark ||
        (themeSettings.themeMode == AppThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final colorScheme =
        AppTheme.getColorScheme(themeSettings.colorSchemeType, isDark);

    final fontSize = prefs.getDouble('${_keyPrefix}fontSize') ?? 14.0;
    final opacity = prefs.getDouble('${_keyPrefix}opacity') ?? 0.88;
    final textColor = prefs.containsKey('${_keyPrefix}textColor')
        ? Color(prefs.getInt('${_keyPrefix}textColor')!)
        : colorScheme.onPrimary;
    final backgroundColor = prefs.containsKey('${_keyPrefix}backgroundColor')
        ? Color(prefs.getInt('${_keyPrefix}backgroundColor')!)
        : colorScheme.primary;
    final cornerRadius = prefs.getDouble('${_keyPrefix}cornerRadius') ?? 16.0;
    final paddingHorizontal =
        prefs.getDouble('${_keyPrefix}paddingHorizontal') ?? 20.0;
    final paddingVertical =
        prefs.getDouble('${_keyPrefix}paddingVertical') ?? 10.0;
    final fontFamily = prefs.getString('${_keyPrefix}fontFamily') ?? '';
    final fontWeightIdx = prefs.getInt('${_keyPrefix}fontWeight');
    final fontWeight = fontWeightIdx != null && fontWeightIdx < FontWeight.values.length
        ? FontWeight.values[fontWeightIdx]
        : FontWeight.bold;
    final shadowEnabled = prefs.getBool('${_keyPrefix}shadowEnabled') ?? true;
    final shadowBlur = prefs.getDouble('${_keyPrefix}shadowBlur') ?? 3.0;
    final transparencyModeIdx = prefs.getInt('${_keyPrefix}transparencyMode');
    final transparencyMode = transparencyModeIdx != null && transparencyModeIdx < TransparencyMode.values.length
        ? TransparencyMode.values[transparencyModeIdx]
        : TransparencyMode.pill;
    final showCloseButton = prefs.getBool('${_keyPrefix}showCloseButton') ?? false;
    final shadowColor = prefs.containsKey('${_keyPrefix}shadowColor')
        ? Color(prefs.getInt('${_keyPrefix}shadowColor')!)
        : const Color(0xCC000000);

    state = FloatingLyricStyle(
      fontSize: fontSize,
      opacity: opacity,
      textColor: textColor,
      backgroundColor: backgroundColor,
      cornerRadius: cornerRadius,
      paddingHorizontal: paddingHorizontal,
      paddingVertical: paddingVertical,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      shadowEnabled: shadowEnabled,
      shadowBlur: shadowBlur,
      transparencyMode: transparencyMode,
      showCloseButton: showCloseButton,
      shadowColor: shadowColor,
    );

    _applyStyle();
  }

  Future<void> _save({bool saveColors = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_keyPrefix}fontSize', state.fontSize);
    await prefs.setDouble('${_keyPrefix}opacity', state.opacity);
    if (saveColors) {
      await prefs.setInt('${_keyPrefix}textColor', state.textColor.toARGB32());
      await prefs.setInt(
          '${_keyPrefix}backgroundColor', state.backgroundColor.toARGB32());
    }
    await prefs.setDouble('${_keyPrefix}cornerRadius', state.cornerRadius);
    await prefs.setDouble(
        '${_keyPrefix}paddingHorizontal', state.paddingHorizontal);
    await prefs.setDouble(
        '${_keyPrefix}paddingVertical', state.paddingVertical);
    await prefs.setString('${_keyPrefix}fontFamily', state.fontFamily);
    await prefs.setInt('${_keyPrefix}fontWeight', state.fontWeight.index);
    await prefs.setBool('${_keyPrefix}shadowEnabled', state.shadowEnabled);
    await prefs.setDouble('${_keyPrefix}shadowBlur', state.shadowBlur);
    await prefs.setInt('${_keyPrefix}transparencyMode', state.transparencyMode.index);
    await prefs.setBool('${_keyPrefix}showCloseButton', state.showCloseButton);
    await prefs.setInt('${_keyPrefix}shadowColor', state.shadowColor.toARGB32());
  }

  void applyStyle() {
    FloatingLyricService.instance.updateStyle(
      fontSize: state.fontSize,
      textColor: state.textColorArgb,
      backgroundColor: state.backgroundColorArgb,
      cornerRadius: state.effectiveCornerRadius,
      paddingHorizontal: state.effectivePaddingHorizontal,
      paddingVertical: state.effectivePaddingVertical,
      fontFamily: state.fontFamily,
      fontWeight: state.fontWeight.index,
      shadowEnabled: state.shadowEnabled,
      shadowBlur: state.shadowBlur,
      shadowColor: state.shadowColor.toARGB32(),
      showCloseButton: state.showCloseButton,
    );
  }

  void _applyStyle() => applyStyle();

  Future<void> updateFontSize(double size) async {
    state = state.copyWith(fontSize: size);
    await _save();
    _applyStyle();
  }

  Future<void> updateOpacity(double opacity) async {
    state = state.copyWith(opacity: opacity);
    await _save();
    _applyStyle();
  }

  Future<void> updateTextColor(Color color) async {
    state = state.copyWith(textColor: color);
    await _save(saveColors: true);
    _applyStyle();
  }

  Future<void> updateBackgroundColor(Color color) async {
    state = state.copyWith(backgroundColor: color);
    await _save(saveColors: true);
    _applyStyle();
  }

  Future<void> updateCornerRadius(double radius) async {
    state = state.copyWith(cornerRadius: radius);
    await _save();
    _applyStyle();
  }

  Future<void> updatePaddingHorizontal(double padding) async {
    state = state.copyWith(paddingHorizontal: padding);
    await _save();
    _applyStyle();
  }

  Future<void> updatePaddingVertical(double padding) async {
    state = state.copyWith(paddingVertical: padding);
    await _save();
    _applyStyle();
  }

  Future<void> updateFontFamily(String family) async {
    state = state.copyWith(fontFamily: family);
    await _save();
    _applyStyle();
  }

  Future<void> updateFontWeight(FontWeight weight) async {
    state = state.copyWith(fontWeight: weight);
    await _save();
    _applyStyle();
  }

  Future<void> updateShadowEnabled(bool enabled) async {
    state = state.copyWith(shadowEnabled: enabled);
    await _save();
    _applyStyle();
  }

  Future<void> updateShadowBlur(double blur) async {
    state = state.copyWith(shadowBlur: blur);
    await _save();
    _applyStyle();
  }

  Future<void> updateShadowColor(Color color) async {
    state = state.copyWith(shadowColor: color);
    await _save();
    _applyStyle();
  }

  Future<void> updateTransparencyMode(TransparencyMode mode) async {
    state = state.copyWith(transparencyMode: mode);
    await _save();
    _applyStyle();
  }

  Future<void> updateShowCloseButton(bool show) async {
    state = state.copyWith(showCloseButton: show);
    await _save();
    _applyStyle();
  }

  /// Reset to default style
  Future<void> reset() async {
    final themeSettings = ref.read(themeSettingsProvider);
    final isDark = themeSettings.themeMode == AppThemeMode.dark ||
        (themeSettings.themeMode == AppThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final colorScheme =
        AppTheme.getColorScheme(themeSettings.colorSchemeType, isDark);

    state = FloatingLyricStyle(
      textColor: colorScheme.onPrimary,
      backgroundColor: colorScheme.primary,
    );

    await _save(saveColors: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_keyPrefix}textColor');
    await prefs.remove('${_keyPrefix}backgroundColor');
    await prefs.remove('${_keyPrefix}fontFamily');
    await prefs.remove('${_keyPrefix}fontWeight');
    await prefs.remove('${_keyPrefix}shadowEnabled');
    await prefs.remove('${_keyPrefix}shadowBlur');
    await prefs.remove('${_keyPrefix}transparencyMode');
    await prefs.remove('${_keyPrefix}showCloseButton');
    await prefs.remove('${_keyPrefix}shadowColor');

    _applyStyle();
  }

  /// Apply preset style
  Future<void> applyPreset(FloatingLyricStylePreset preset,
      [BuildContext? context]) async {
    state = preset.getStyle(context);

    if (preset == FloatingLyricStylePreset.dynamic) {
      await _save(saveColors: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_keyPrefix}textColor');
      await prefs.remove('${_keyPrefix}backgroundColor');
      await _updateColorsFromThemeIfDefault();
    } else {
      await _save(saveColors: true);
    }

    _applyStyle();
  }
}

/// Preset styles
enum FloatingLyricStylePreset {
  dynamic,
  classic,
  modern,
  minimal,
  vibrant,
  elegant,
}

extension FloatingLyricStylePresetExtension on FloatingLyricStylePreset {
  String get name {
    switch (this) {
      case FloatingLyricStylePreset.dynamic:
        return 'Dynamic';
      case FloatingLyricStylePreset.classic:
        return 'Classic';
      case FloatingLyricStylePreset.modern:
        return 'Modern';
      case FloatingLyricStylePreset.minimal:
        return 'Minimal';
      case FloatingLyricStylePreset.vibrant:
        return 'Vibrant';
      case FloatingLyricStylePreset.elegant:
        return 'Elegant';
    }
  }

  String get description {
    switch (this) {
      case FloatingLyricStylePreset.dynamic:
        return 'Follows system theme colors';
      case FloatingLyricStylePreset.classic:
        return 'Black background, white text';
      case FloatingLyricStylePreset.modern:
        return 'Dark blue, modern style';
      case FloatingLyricStylePreset.minimal:
        return 'Light & transparent';
      case FloatingLyricStylePreset.vibrant:
        return 'Bold pink, vibrant';
      case FloatingLyricStylePreset.elegant:
        return 'Deep blue, elegant';
    }
  }

  /// Preview colors for the preset chip
  Color get previewBg {
    switch (this) {
      case FloatingLyricStylePreset.dynamic:
        return const Color(0xFF2196F3);
      case FloatingLyricStylePreset.classic:
        return Colors.black;
      case FloatingLyricStylePreset.modern:
        return const Color(0xFF1A237E);
      case FloatingLyricStylePreset.minimal:
        return const Color(0xFFF5F5F5);
      case FloatingLyricStylePreset.vibrant:
        return const Color(0xFFE91E63);
      case FloatingLyricStylePreset.elegant:
        return const Color(0xFF0D47A1);
    }
  }

  Color get previewTextColor {
    switch (this) {
      case FloatingLyricStylePreset.minimal:
        return const Color(0xFF212121);
      default:
        return Colors.white;
    }
  }

  FloatingLyricStyle getStyle([BuildContext? context]) {
    switch (this) {
      case FloatingLyricStylePreset.dynamic:
        if (context != null) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final isDark = theme.brightness == Brightness.dark;

          return FloatingLyricStyle(
            fontSize: 14.0,
            opacity: isDark ? 0.90 : 0.85,
            textColor: colorScheme.onPrimary,
            backgroundColor: colorScheme.primary,
            cornerRadius: 16.0,
            paddingHorizontal: 20.0,
            paddingVertical: 10.0,
            fontWeight: FontWeight.bold,
            shadowEnabled: true,
            shadowBlur: 3.0,
            transparencyMode: TransparencyMode.pill,
            showCloseButton: false,
          );
        }
        return const FloatingLyricStyle(
          fontSize: 14.0,
          opacity: 0.88,
          textColor: Colors.white,
          backgroundColor: Color(0xFF2196F3),
          cornerRadius: 16.0,
          paddingHorizontal: 20.0,
          paddingVertical: 10.0,
        );
      case FloatingLyricStylePreset.classic:
        return const FloatingLyricStyle(
          fontSize: 14.0,
          opacity: 0.95,
          textColor: Colors.white,
          backgroundColor: Color(0xFF000000),
          cornerRadius: 16.0,
          paddingHorizontal: 20.0,
          paddingVertical: 10.0,
          fontWeight: FontWeight.bold,
          shadowEnabled: true,
          shadowBlur: 2.0,
          transparencyMode: TransparencyMode.pill,
        );
      case FloatingLyricStylePreset.modern:
        return const FloatingLyricStyle(
          fontSize: 16.0,
          opacity: 0.90,
          textColor: Colors.white,
          backgroundColor: Color(0xFF1A237E),
          cornerRadius: 20.0,
          paddingHorizontal: 24.0,
          paddingVertical: 12.0,
          fontWeight: FontWeight.w600,
          shadowEnabled: true,
          shadowBlur: 4.0,
          transparencyMode: TransparencyMode.pill,
        );
      case FloatingLyricStylePreset.minimal:
        return const FloatingLyricStyle(
          fontSize: 13.0,
          opacity: 0.75,
          textColor: Color(0xFF212121),
          backgroundColor: Color(0xFFFFFFFF),
          cornerRadius: 12.0,
          paddingHorizontal: 16.0,
          paddingVertical: 8.0,
          fontWeight: FontWeight.w500,
          shadowEnabled: false,
          shadowBlur: 0,
          transparencyMode: TransparencyMode.pill,
        );
      case FloatingLyricStylePreset.vibrant:
        return const FloatingLyricStyle(
          fontSize: 15.0,
          opacity: 0.92,
          textColor: Colors.white,
          backgroundColor: Color(0xFFE91E63),
          cornerRadius: 18.0,
          paddingHorizontal: 22.0,
          paddingVertical: 11.0,
          fontWeight: FontWeight.bold,
          shadowEnabled: true,
          shadowBlur: 3.0,
          transparencyMode: TransparencyMode.pill,
        );
      case FloatingLyricStylePreset.elegant:
        return const FloatingLyricStyle(
          fontSize: 14.0,
          opacity: 0.88,
          textColor: Color(0xFFE3F2FD),
          backgroundColor: Color(0xFF0D47A1),
          cornerRadius: 16.0,
          paddingHorizontal: 20.0,
          paddingVertical: 10.0,
          fontWeight: FontWeight.w600,
          shadowEnabled: true,
          shadowBlur: 3.0,
          transparencyMode: TransparencyMode.pill,
        );
    }
  }
}
