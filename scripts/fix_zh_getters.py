import sys

with open('lib/l10n/app_localizations_zh.dart', 'rb') as f:
    content = f.read()

# ---- Names section 1 (Simplified Chinese) ----
old_names1 = b'  String get colorSchemeForestGreen => \xe2\x80\x98\xe8\x8d\x89\xe5\x8e\x9f\xe7\xbb\xbf\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeSunsetOrange => \xe2\x80\x98\xe4\xbb\x8a\xe6\x97\xa5\xe6\xa9\x99\xe2\x80\x99;'
# ForestGreen => 草原绿

new_names1 = b'  String get colorSchemeForestGreen => \xe2\x80\x98\xe8\x8d\x89\xe5\x8e\x9f\xe7\xbb\xbf\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeCrimsonRed => \xe2\x80\x98\xe8\xb5\xa4\xe7\x84\xb0\xe7\xba\xa2\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeAmberGold => \xe2\x80\x98\xe7\x90\xa5\xe7\x8f\x80\xe9\x87\x91\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeSlateGray => \xe2\x80\x98\xe5\xb2\xa9\xe6\x9d\xbf\xe7\x81\xb0\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeSunsetOrange => \xe2\x80\x98\xe4\xbb\x8a\xe6\x97\xa5\xe6\xa9\x99\xe2\x80\x99;'

count_n1 = content.count(old_names1)
print(f'Names section 1 (Simplified) found: {count_n1}')
if count_n1 == 1:
    content = content.replace(old_names1, new_names1, 1)
    print('Names section 1 replaced OK')
else:
    print(f'WARNING: Names section 1 found {count_n1} times')

# ---- Names section 2 (Traditional Chinese) ----
old_names2 = b'  String get colorSchemeForestGreen => \xe2\x80\x98\xe8\x8d\x89\xe5\x8e\x9f\xe7\xb6\xa0\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeSunsetOrange => \xe2\x80\x98\xe4\xbb\x8a\xe6\x97\xa5\xe6\xa9\x99\xe2\x80\x99;'
# ForestGreen => 草原綠

new_names2 = b'  String get colorSchemeForestGreen => \xe2\x80\x98\xe8\x8d\x89\xe5\x8e\x9f\xe7\xb6\xa0\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeCrimsonRed => \xe2\x80\x98\xe8\xb5\xa4\xe7\x84\xb0\xe7\xb4\x85\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeAmberGold => \xe2\x80\x98\xe7\x90\xa5\xe7\x8f\x80\xe9\x87\x91\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeSlateGray => \xe2\x80\x98\xe5\xb2\xa9\xe6\x9d\xbf\xe7\x81\xb0\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeSunsetOrange => \xe2\x80\x98\xe4\xbb\x8a\xe6\x97\xa5\xe6\xa9\x99\xe2\x80\x99;'

count_n2 = content.count(old_names2)
print(f'Names section 2 (Traditional) found: {count_n2}')
if count_n2 == 1:
    content = content.replace(old_names2, new_names2, 1)
    print('Names section 2 replaced OK')
else:
    print(f'WARNING: Names section 2 found {count_n2} times')

# ---- Descriptions section 1 (Simplified Chinese) ----
old_desc1 = b'  String get colorSchemeForestGreenDesc => \xe2\x80\x98\xe8\x89\xb9\xe8\x89\xb9\xe8\x89\xb9\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeDynamicDesc => \xe2\x80\x98\xe4\xbd\xbf\xe7\x94\xa8\xe7\xb3\xbb\xe7\xbb\x9f\xe5\xa3\x81\xe7\xba\xb8\xe7\x9a\x84\xe9\xa2\x9c\xe8\x89\xb2 (Android 12+)\xe2\x80\x99;'

new_desc1 = b'  String get colorSchemeForestGreenDesc => \xe2\x80\x98\xe8\x89\xb9\xe8\x89\xb9\xe8\x89\xb9\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeCrimsonRedDesc => \xe2\x80\x98\xe7\xba\xa2\xe7\xba\xa2\xe7\x81\xab\xe7\x81\xab\xef\xbc\x81\U0001f534\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeAmberGoldDesc => \xe2\x80\x98\xe9\x87\x91\xe8\x89\xb2\xe8\xbe\x89\xe7\x85\x8c\xef\xbc\x81\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeSlateGrayDesc => \xe2\x80\x98\xe4\xb8\xad\xe6\x80\xa7\xe4\xbc\x98\xe9\x9b\x85\xef\xbc\x8c\xe5\x86\xb7\xe9\x9d\x99\xe4\xb8\x93\xe4\xb8\x9a\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeDynamicDesc => \xe2\x80\x98\xe4\xbd\xbf\xe7\x94\xa8\xe7\xb3\xbb\xe7\xbb\x9f\xe5\xa3\x81\xe7\xba\xb8\xe7\x9a\x84\xe9\xa2\x9c\xe8\x89\xb2 (Android 12+)\xe2\x80\x99;'

count_d1 = content.count(old_desc1)
print(f'Desc section 1 (Simplified) found: {count_d1}')
if count_d1 == 1:
    content = content.replace(old_desc1, new_desc1, 1)
    print('Desc section 1 replaced OK')
else:
    print(f'WARNING: Desc section 1 found {count_d1} times')

# ---- Descriptions section 2 (Traditional Chinese) ----
old_desc2 = b'  String get colorSchemeForestGreenDesc => \xe2\x80\x98\xe8\x8d\x89\xe8\x8d\x89\xe8\x8d\x89\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeDynamicDesc => \xe2\x80\x98\xe4\xbd\xbf\xe7\x94\xa8\xe7\xb3\xbb\xe7\xb5\xb1\xe5\xa4\xa2\xe5\xb8\x83\xe7\x9a\x84\xe9\xa1\x8f\xe8\x89\xb2 (Android 12+)\xe2\x80\x99;'

new_desc2 = b'  String get colorSchemeForestGreenDesc => \xe2\x80\x98\xe8\x8d\x89\xe8\x8d\x89\xe8\x8d\x89\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeCrimsonRedDesc => \xe2\x80\x98\xe7\xb4\x85\xe7\xb4\x85\xe7\x81\xab\xe7\x81\xab\xef\xbc\x81\U0001f534\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeAmberGoldDesc => \xe2\x80\x98\xe9\x87\x91\xe8\x89\xb2\xe8\xbc\x9d\xe7\x85\x8c\xef\xbc\x81\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeSlateGrayDesc => \xe2\x80\x98\xe4\xb8\xad\xe6\x80\xa7\xe5\x84\xaa\xe9\x9b\x85\xef\xbc\x8c\xe5\x86\xb7\xe9\x9d\x9c\xe5\xb0\x88\xe6\xa5\xad\xe2\x80\x99;\r\n\r\n  @override\r\n  String get colorSchemeDynamicDesc => \xe2\x80\x98\xe4\xbd\xbf\xe7\x94\xa8\xe7\xb3\xbb\xe7\xb5\xb1\xe5\xa4\xa2\xe5\xb8\x83\xe7\x9a\x84\xe9\xa1\x8f\xe8\x89\xb2 (Android 12+)\xe2\x80\x99;'

count_d2 = content.count(old_desc2)
print(f'Desc section 2 (Traditional) found: {count_d2}')
if count_d2 == 1:
    content = content.replace(old_desc2, new_desc2, 1)
    print('Desc section 2 replaced OK')
else:
    print(f'WARNING: Desc section 2 found {count_d2} times')

with open('lib/l10n/app_localizations_zh.dart', 'wb') as f:
    f.write(content)

print('\nAll done!')
