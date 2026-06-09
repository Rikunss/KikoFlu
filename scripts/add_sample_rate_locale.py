# Add localization getters for preferredSampleRate to app_localizations.dart (abstract)
# and app_localizations_en.dart (implementation)
import sys

# ---- Add to abstract class ----
with open('lib/l10n/app_localizations.dart', 'rb') as f:
    content = f.read()

old_abstract = (
    b'  /// No description provided for @searchSettingsComingSoon.\r\n'
    b'  ///\r\n'
    b'  /// In en, this message translates to:\r\n'
    b"  /// **'Full settings search will be available in a future update.'**\r\n"
    b'  String get searchSettingsComingSoon;\r\n'
    b'\r\n'
    b'  /// No description provided for @settingsPlayback.'
)

new_abstract = (
    b'  /// No description provided for @searchSettingsComingSoon.\r\n'
    b'  ///\r\n'
    b'  /// In en, this message translates to:\r\n'
    b"  /// **'Full settings search will be available in a future update.'**\r\n"
    b'  String get searchSettingsComingSoon;\r\n'
    b'\r\n'
    b'  /// No description provided for @preferredSampleRate.\r\n'
    b'  ///\r\n'
    b'  /// In en, this message translates to:\r\n'
    b"  /// **'Preferred Sample Rate'**\r\n"
    b'  String get preferredSampleRate;\r\n'
    b'\r\n'
    b'  /// No description provided for @preferredSampleRateSubtitle.\r\n'
    b'  ///\r\n'
    b'  /// In en, this message translates to:\r\n'
    b"  /// **'Hi-res audio output target (Android)'**\r\n"
    b'  String get preferredSampleRateSubtitle;\r\n'
    b'\r\n'
    b'  /// No description provided for @preferredSampleRateAuto.\r\n'
    b'  ///\r\n'
    b'  /// In en, this message translates to:\r\n'
    b"  /// **'Auto (follow file)'**\r\n"
    b'  String get preferredSampleRateAuto;\r\n'
    b'\r\n'
    b'  /// No description provided for @preferredSampleRateDesc.\r\n'
    b'  ///\r\n'
    b'  /// In en, this message translates to:\r\n'
    b"  /// **'Sets the preferred sample rate for audio output. Higher rates may reduce compatibility but improve quality on supported DACs.'**\r\n"
    b'  String get preferredSampleRateDesc;\r\n'
    b'\r\n'
    b'  /// No description provided for @settingsPlayback.'
)

cnt_abs = content.count(old_abstract)
print('Abstract section found:', cnt_abs)
if cnt_abs == 1:
    content = content.replace(old_abstract, new_abstract, 1)
    print('Abstract replaced OK')
else:
    print('WARNING: found', cnt_abs)

with open('lib/l10n/app_localizations.dart', 'wb') as f:
    f.write(content)
print('Abstract file written')

# ---- Add to en implementation ----
with open('lib/l10n/app_localizations_en.dart', 'rb') as f:
    content = f.read()

old_en = (
    b"  String get searchSettingsComingSoon =>\n"
    b"      'Full settings search will be available in a future update.';\n"
    b"\n"
    b"  @override\n"
    b"  String get settingsPlayback"
)

new_en = (
    b"  String get searchSettingsComingSoon =>\n"
    b"      'Full settings search will be available in a future update.';\n"
    b"\n"
    b"  @override\n"
    b"  String get preferredSampleRate => 'Preferred Sample Rate';\n"
    b"\n"
    b"  @override\n"
    b"  String get preferredSampleRateSubtitle =>\n"
    b"      'Hi-res audio output target (Android)';\n"
    b"\n"
    b"  @override\n"
    b"  String get preferredSampleRateAuto => 'Auto (follow file)';\n"
    b"\n"
    b"  @override\n"
    b"  String get preferredSampleRateDesc =>\n"
    b"      'Sets the preferred sample rate for audio output. Higher rates may reduce compatibility but improve quality on supported DACs.';\n"
    b"\n"
    b"  @override\n"
    b"  String get settingsPlayback"
)

cnt_en = content.count(old_en)
print('En section found:', cnt_en)
if cnt_en == 1:
    content = content.replace(old_en, new_en, 1)
    print('En replaced OK')
else:
    print('WARNING: found', cnt_en)

with open('lib/l10n/app_localizations_en.dart', 'wb') as f:
    f.write(content)
print('En file written')

print('\nAll done!')
