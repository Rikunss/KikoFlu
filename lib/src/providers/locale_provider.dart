import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleNotifier extends StateNotifier<Locale?> {
  static const String _localeLanguageKey = 'locale_language';
  static const String _localeScriptKey = 'locale_script';

  /// null means follow system
  LocaleNotifier() : super(null) {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString(_localeLanguageKey);
    if (language == null) {
      state = null;
      return;
    }
    final script = prefs.getString(_localeScriptKey);
    state = script != null
        ? Locale.fromSubtags(languageCode: language, scriptCode: script)
        : Locale(language);
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_localeLanguageKey);
      await prefs.remove(_localeScriptKey);
    } else {
      await prefs.setString(_localeLanguageKey, locale.languageCode);
      if (locale.scriptCode != null) {
        await prefs.setString(_localeScriptKey, locale.scriptCode!);
      } else {
        await prefs.remove(_localeScriptKey);
      }
    }
    state = locale;
  }
}

/// null = follow system locale
final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  return LocaleNotifier();
});