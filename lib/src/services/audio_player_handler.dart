import 'package:audio_service/audio_service.dart';
import 'audio_player_service.dart';
import 'playback_history_service.dart';

/// [AudioHandler] implementation for system media controls integration
/// (notification bar, lock screen, Bluetooth/Wearable controls).
///
/// Delegates all operations to [AudioPlayerService].
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayerService _service;

  AudioPlayerHandler(this._service);

  @override
  Future<void> play() => _service.play();

  @override
  Future<void> pause() async {
    await _service.pause();
    PlaybackHistoryService.instance.onPaused();
  }

  @override
  Future<void> stop() async {
    await _service.stop();
    PlaybackHistoryService.instance.onStopped();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    mediaItem.add(null);
  }

  @override
  Future<void> seek(Duration position) async {
    await _service.seek(position);
    PlaybackHistoryService.instance.onSeekCommitted(position);
  }

  @override
  Future<void> skipToNext() => _service.skipToNext();

  @override
  Future<void> skipToPrevious() => _service.skipToPrevious();
}