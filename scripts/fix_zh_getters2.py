# -*- coding: utf-8 -*-
import sys

with open('lib/l10n/app_localizations_zh.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ---- Names section 1 (Simplified Chinese) ----
old_n1 = "  String get colorSchemeForestGreen => '草原绿';\n\n  @override\n  String get colorSchemeSunsetOrange => '今日橙';"
new_n1 = "  String get colorSchemeForestGreen => '草原绿';\n\n  @override\n  String get colorSchemeCrimsonRed => '赤焰红';\n\n  @override\n  String get colorSchemeAmberGold => '琥珀金';\n\n  @override\n  String get colorSchemeSlateGray => '岩板灰';\n\n  @override\n  String get colorSchemeSunsetOrange => '今日橙';"

cnt_n1 = content.count(old_n1)
print(f'Names section 1 (Simplified) found: {cnt_n1}')
if cnt_n1 == 1:
    content = content.replace(old_n1, new_n1, 1)
    print('Names section 1 replaced OK')
else:
    print(f'WARNING: found {cnt_n1}')

# ---- Names section 2 (Traditional Chinese) ----
old_n2 = "  String get colorSchemeForestGreen => '草原綠';\n\n  @override\n  String get colorSchemeSunsetOrange => '今日橙';"
new_n2 = "  String get colorSchemeForestGreen => '草原綠';\n\n  @override\n  String get colorSchemeCrimsonRed => '赤焰紅';\n\n  @override\n  String get colorSchemeAmberGold => '琥珀金';\n\n  @override\n  String get colorSchemeSlateGray => '岩板灰';\n\n  @override\n  String get colorSchemeSunsetOrange => '今日橙';"

cnt_n2 = content.count(old_n2)
print(f'Names section 2 (Traditional) found: {cnt_n2}')
if cnt_n2 == 1:
    content = content.replace(old_n2, new_n2, 1)
    print('Names section 2 replaced OK')
else:
    print(f'WARNING: found {cnt_n2}')

# ---- Descriptions section 1 (Simplified Chinese) ----
old_d1 = "  String get colorSchemeForestGreenDesc => '艹艹艹';\n\n  @override\n  String get colorSchemeDynamicDesc => '使用系统壁纸的颜色 (Android 12+)';"
new_d1 = "  String get colorSchemeForestGreenDesc => '艹艹艹';\n\n  @override\n  String get colorSchemeCrimsonRedDesc => '红红火火！🔴';\n\n  @override\n  String get colorSchemeAmberGoldDesc => '金色辉煌！';\n\n  @override\n  String get colorSchemeSlateGrayDesc => '中性优雅，冷静专业';\n\n  @override\n  String get colorSchemeDynamicDesc => '使用系统壁纸的颜色 (Android 12+)';"

cnt_d1 = content.count(old_d1)
print(f'Desc section 1 (Simplified) found: {cnt_d1}')
if cnt_d1 == 1:
    content = content.replace(old_d1, new_d1, 1)
    print('Desc section 1 replaced OK')
else:
    print(f'WARNING: found {cnt_d1}')

# ---- Descriptions section 2 (Traditional Chinese) ----
old_d2 = "  String get colorSchemeForestGreenDesc => '草草草';\n\n  @override\n  String get colorSchemeDynamicDesc => '使用系統桌布的顏色 (Android 12+)';"
new_d2 = "  String get colorSchemeForestGreenDesc => '草草草';\n\n  @override\n  String get colorSchemeCrimsonRedDesc => '紅紅火火！🔴';\n\n  @override\n  String get colorSchemeAmberGoldDesc => '金色輝煌！';\n\n  @override\n  String get colorSchemeSlateGrayDesc => '中性優雅，冷靜專業';\n\n  @override\n  String get colorSchemeDynamicDesc => '使用系統桌布的顏色 (Android 12+)';"

cnt_d2 = content.count(old_d2)
print(f'Desc section 2 (Traditional) found: {cnt_d2}')
if cnt_d2 == 1:
    content = content.replace(old_d2, new_d2, 1)
    print('Desc section 2 replaced OK')
else:
    print(f'WARNING: found {cnt_d2}')

with open('lib/l10n/app_localizations_zh.dart', 'w', encoding='utf-8', newline='') as f:
    f.write(content)

print('\nAll done!')
