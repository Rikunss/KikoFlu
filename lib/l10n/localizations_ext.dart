import 'package:flutter/material.dart';
import 'app_localizations.dart';
import 'app_localizations_en.dart';

/// Safe accessor for [S] that never throws.
/// Returns English fallback if localization delegate hasn't loaded yet.
S sLoc(BuildContext context) {
  try {
    return S.of(context);
  } catch (_) {
    return SEn();
  }
}
