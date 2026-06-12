#!/usr/bin/env python3
"""Add missing ColorScheme getters to app_localizations.dart abstract class."""
import sys
from pathlib import Path

filepath = Path(sys.argv[1] if len(sys.argv) > 1 else "lib/l10n/app_localizations.dart")
content = filepath.read_bytes()

# 1. Add CrimsonRed, AmberGold, SlateGray after SakuraPink
old1 = b"  String get colorSchemeSakuraPink;\r\n\r\n  /// No description provided for @colorSchemeDynamic."
new1 = b"""  String get colorSchemeSakuraPink;

  /// No description provided for @colorSchemeCrimsonRed.
  ///
  /// In en, this message translates to:
  /// **'Crimson Red'**
  String get colorSchemeCrimsonRed;

  /// No description provided for @colorSchemeAmberGold.
  ///
  /// In en, this message translates to:
  /// **'Amber Gold'**
  String get colorSchemeAmberGold;

  /// No description provided for @colorSchemeSlateGray.
  ///
  /// In en, this message translates to:
  /// **'Slate Gray'**
  String get colorSchemeSlateGray;

  /// No description provided for @colorSchemeDynamic."""

if content.count(old1) != 1:
    print(f"ERROR: Names section found {content.count(old1)} times (expected 1)")
    sys.exit(1)

content = content.replace(old1, new1, 1)
print("Names replaced OK")

# 2. Add CrimsonRedDesc, AmberGoldDesc, SlateGrayDesc after ForestGreenDesc
old2 = b"  String get colorSchemeForestGreenDesc;\r\n\r\n  /// No description provided for @colorSchemeDynamicDesc."
new2 = b"""  String get colorSchemeForestGreenDesc;

  /// No description provided for @colorSchemeCrimsonRedDesc.
  ///
  /// In en, this message translates to:
  /// **'Red, red, red! \xf0\x9f\x94\xb4'**
  String get colorSchemeCrimsonRedDesc;

  /// No description provided for @colorSchemeAmberGoldDesc.
  ///
  /// In en, this message translates to:
  /// **'Golden and bright!'**
  String get colorSchemeAmberGoldDesc;

  /// No description provided for @colorSchemeSlateGrayDesc.
  ///
  /// In en, this message translates to:
  /// **'Neutral, elegant, cool'**
  String get colorSchemeSlateGrayDesc;

  /// No description provided for @colorSchemeDynamicDesc."""

if content.count(old2) != 1:
    print(f"ERROR: Descs section found {content.count(old2)} times (expected 1)")
    sys.exit(1)

content = content.replace(old2, new2, 1)
print("Descs replaced OK")

filepath.write_bytes(content)
print("File written successfully!")
