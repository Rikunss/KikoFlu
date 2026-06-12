import 'package:home_widget/home_widget.dart';

import '../models/audio_track.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Service to manage Android home screen widget state.
/// Saves current track info and triggers widget updates via home_widget plugin.
class HomeWidgetService {
  static final HomeWidgetService instance = HomeWidgetService._();
  HomeWidgetService._();

  static const String _widgetName = 'KikoFluWidgetProvider';

  /// Initialize the home widget plugin.
  Future<void> init() async {
    try {
      await HomeWidget.registerInteractivityCallback(backgroundCallback);
    } catch (e) {
      _log.warning('[HomeWidget] init failed: $e');
    }
  }

  /// Update the widget with the current track state.
  Future<void> updateTrackState({
    required AudioTrack? track,
    required bool isPlaying,
  }) async {
    try {
      final title = track?.title ?? 'No track';
      final artist = track?.artist ?? '';

      await HomeWidget.saveWidgetData<String>('widget_track_title', title);
      await HomeWidget.saveWidgetData<String>('widget_track_artist', artist);
      await HomeWidget.saveWidgetData<bool>('widget_is_playing', isPlaying);

      await HomeWidget.updateWidget(
        name: _widgetName,
        androidName: _widgetName,
      );

      _log.debug('[HomeWidget] Updated: "$title" - ${isPlaying ? "playing" : "paused"}');
    } catch (e) {
      _log.warning('[HomeWidget] updateTrackState failed: $e');
    }
  }

  /// Called when a widget background action is triggered.
  @pragma('vm:entry-point')
  static Future<void> backgroundCallback(Uri? uri) async {
    // Actions are handled via intents sent to MainActivity
    // on the Dart side through the MethodChannel
  }
}
