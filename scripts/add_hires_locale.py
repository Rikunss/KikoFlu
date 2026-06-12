import json
import sys

arb_path = 'lib/l10n/app_en.arb'
dart_path = 'lib/l10n/app_localizations.dart'
en_dart_path = 'lib/l10n/app_localizations_en.dart'

# 1. Add keys to app_en.arb
with open(arb_path, 'r', encoding='utf-8') as f:
    arb = json.load(f)

new_keys = {
    "hiResExclusiveMode": "Hi-Res Exclusive Mode",
    "hiResExclusiveModeSubtitle": "Use native ExoPlayer for FLAC/WAV hi-res tracks",
    "hiResExclusiveModeDesc": "When enabled, hi-res tracks (FLAC/WAV >48kHz) play through the native ExoPlayer. May cause brief interruption when switching players.",
    "hiResExclusiveModeEnabled": "Hi-Res Exclusive Mode enabled",
    "hiResExclusiveModeDisabled": "Hi-Res Exclusive Mode disabled",
    "enable": "Enable",
}

for k, v in new_keys.items():
    if k not in arb:
        arb[k] = v
        print(f'  Added: {k}')
    else:
        print(f'  Skipped (exists): {k}')

with open(arb_path, 'w', encoding='utf-8') as f:
    json.dump(arb, f, ensure_ascii=False, indent=2)
print(f'\nUpdated {arb_path}')

# 2. Add abstract getters to app_localizations.dart
with open(dart_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find the last getter before the closing brace
lines = content.split('\n')
last_getter_idx = -1
for i in range(len(lines) - 1, -1, -1):
    line = lines[i].strip()
    if line.startswith('String get ') and line.endswith(';'):
        last_getter_idx = i
        break

if last_getter_idx >= 0:
    indent = '  '
    getters = []
    for k in new_keys:
        comment = f'  /// No description provided for @{k}.\n'
        getter = f'  String get {k};\n'
        getters.append(f'{comment}{getter}')
    
    abstract_section = '\n'.join(getters)
    new_lines = lines[:last_getter_idx + 1] + [''] + [abstract_section] + lines[last_getter_idx + 1:]
    
    with open(dart_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(new_lines))
    print(f'Updated {dart_path}')

print('\nDone!')
