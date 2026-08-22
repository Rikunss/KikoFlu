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
      if (!_remoteConfig.isConfigured) {
        print('[InfoPopup] Skipped: Firebase not configured');
        return null;
      }

      final raw =
          await _remoteConfig.getString(FirebaseConfig.informationPopupParam);
      print('[InfoPopup] Raw value length: ${raw.length}');
      print('[InfoPopup] Raw value preview: ${raw.substring(0, raw.length > 200 ? 200 : raw.length)}');
      if (raw.isEmpty) return null;

      final popup = InformationPopup.fromJson(raw);
      if (popup == null) {
        print('[InfoPopup] JSON parse returned null!');
        return null;
      }
      if (!popup.isActiveOn(DateTime.now())) {
        print('[InfoPopup] Popup not active (startDate/endDate check failed)');
        return null;
      }

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
