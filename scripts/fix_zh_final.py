import re

with open('lib/l10n/app_localizations_zh.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the first occurrence of settingsPlayback => and insert preferredSampleRate getters after it
old = "    String get settingsPlayback => '播放';\n"
new = """    String get settingsPlayback => '播放';

  @override
    String get preferredSampleRate => '首选采样率';

  @override
    String get preferredSampleRateSubtitle =>
        'Hi-Res 音频输出目标 (Android)';

  @override
    String get preferredSampleRateAuto => '自动 (跟随文件)';

  @override
    String get preferredSampleRateDesc =>
        '设置音频输出的采样率。较高的采样率可能降低兼容性，但在支持的DAC上提升音质。';
"""

# Only replace the first occurrence (in SZh class, not SZhHant which inherits it)
content = content.replace(old, new, 1)

with open('lib/l10n/app_localizations_zh.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Done!")
