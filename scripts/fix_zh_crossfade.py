# Fix Simplified Chinese crossfade strings in app_localizations_zh.dart
# The file has TWO S classes: Simplified (line ~3369) and Traditional (line ~6734)

with open("lib/l10n/app_localizations_zh.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Simplified Chinese strings
simplified_code = """
  @override
  String get crossfadeTitle => '交叉淡化';

  @override
  String crossfadeEnabledWithDuration(int ms) {
    if (ms >= 1000) {
      return '交叉淡化: ${(ms / 1000).toStringAsFixed(1)}s';
    }
    return '交叉淡化: ${ms}ms';
  }

  @override
  String get gaplessPlaybackEnabled => '无缝播放（无交叉淡化）';

  @override
  String get crossfadeDurationLabel => '交叉淡化时长';

  @override
  String get crossfadeMinLabel => '0.5秒';

  @override
  String get crossfadeMaxLabel => '10秒';

  @override
  String get crossfadeDescription =>
      '在曲目之间平滑过渡。关闭时，无缝播放最小化间隙。';
"""

# Find the FIRST occurrence of "get logEmpty" - this is Simplified Chinese
first_log_empty = content.find("String get logEmpty")
# Find the closing brace after this
close_brace_after_first = content.find("}", first_log_empty)
if close_brace_after_first != -1:
    # Check if crossfade strings already exist after this closing brace
    after_close = content[close_brace_after_first:close_brace_after_first+50]
    if "crossfadeTitle" not in after_close:
        content = content[:close_brace_after_first] + simplified_code + "\n" + content[close_brace_after_first:]
        print("Added Simplified Chinese crossfade strings")
    else:
        print("Simplified Chinese crossfade strings already exist")

with open("lib/l10n/app_localizations_zh.dart", "w", encoding="utf-8") as f:
    f.write(content)

print("Done")
