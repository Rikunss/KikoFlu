import 'dart:ui';
import 'tag_translations.dart';

/// Utility for getting localized tag names.
///
/// Uses the static translation map generated from asmr.one API.
/// Falls back to the original name if no translation is available.
class TagLocalizer {
  TagLocalizer._();

  /// Get the localized name for a tag given its ID and the current locale.
  /// [tagId] - the tag's numeric ID
  /// [defaultName] - the original name to fall back to
  /// [locale] - the current app locale
  static String localize(int tagId, String defaultName, Locale locale) {
    final translations = tagTranslations[tagId];
    if (translations == null) return defaultName;

    final key = _localeKey(locale);
    return translations[key] ?? translations['zh'] ?? defaultName;
  }

  /// Get the localized name for a tag, looking up by original name if ID is unknown.
  static String localizeByName(String name, Locale locale) {
    final key = _localeKey(locale);
    if (key == 'zh') return name;

    final id = tagNameToId[name.toLowerCase()];
    if (id == null) return name;

    final translations = tagTranslations[id];
    if (translations == null) return name;

    return translations[key] ?? name;
  }

  static String _localeKey(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return 'en';
      case 'ja':
        return 'ja';
      case 'ru':
        return 'ru';
      case 'zh':
        if (locale.scriptCode == 'Hant' ||
            locale.countryCode == 'TW' ||
            locale.countryCode == 'HK' ||
            locale.countryCode == 'MO') {
          return 'zh_Hant';
        }
        return 'zh';
      default:
        return 'en';
    }
  }
}