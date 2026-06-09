with open('lib/l10n/app_localizations_zh.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old = "  String get advancedAllSettingsLegacySubtitle => '原来的完整设置页面';\n}\n\n/// The translations for Chinese, using the Han script (`zh_Hant`)."

new = """  String get advancedAllSettingsLegacySubtitle => '原来的完整设置页面';

  @override
  String get hiResExclusiveMode => 'Hi-Res 独占模式';

  @override
  String get hiResExclusiveModeSubtitle =>
      '使用原生ExoPlayer播放FLAC/WAV高解析音频';

  @override
  String get hiResExclusiveModeDesc =>
      '启用后，高解析音轨（FLAC/WAV >48kHz）将通过原生ExoPlayer播放。切换播放器时可能导致短暂中断。';

  @override
  String get hiResExclusiveModeEnabled => 'Hi-Res 独占模式已启用';

  @override
  String get hiResExclusiveModeDisabled => 'Hi-Res 独占模式已禁用';

  @override
  String get enable => '启用';
}

/// The translations for Chinese, using the Han script (`zh_Hant`)."""

if old in content:
    content = content.replace(old, new, 1)
    with open('lib/l10n/app_localizations_zh.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('zh.dart updated successfully')
else:
    print('ERROR: old string not found!')
