import 'package:shared_preferences/shared_preferences.dart';

import '../config/firebase_config.dart';
import '../models/information_popup.dart';
import 'log_service.dart';
import 'remote_config_service.dart';

class InformationPopupService {
  InformationPopupService({RemoteConfigService? remoteConfig})
      : _remoteConfig = remoteConfig ?? RemoteConfigService();

  final RemoteConfigService _remoteConfig;

  static const String _dismissPrefix = 'information_popup_dismissed_';

  /// The active popup to show, or null if there is none.
  /// Never throws — all failures return null.
  Future<InformationPopup?> getActivePopup() async {
    try {
      if (!_remoteConfig.isConfigured) return null;

      final raw =
          await _remoteConfig.getString(FirebaseConfig.informationPopupParam);
      if (raw.isEmpty) return null;

      final popup = InformationPopup.fromJson(raw);
      if (popup == null) return null;
      if (!popup.isActiveOn(DateTime.now())) return null;

      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool('$_dismissPrefix${popup.id}') ?? false;
      if (dismissed) return null;

      return popup;
    } catch (e) {
      LogService.instance.warning(
        '[InfoPopup] Failed to load popup: $e',
        tag: 'InfoPopup',
      );
      return null;
    }
  }

  Future<void> dismiss(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_dismissPrefix$id', true);
    } catch (e) {
      LogService.instance.warning(
        '[InfoPopup] Failed to persist dismissal: $e',
        tag: 'InfoPopup',
      );
    }
  }

  Future<void> resetDismissal(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_dismissPrefix$id');
    } catch (e) {
      LogService.instance.warning(
        '[InfoPopup] Failed to reset dismissal: $e',
        tag: 'InfoPopup',
      );
    }
  }
}
