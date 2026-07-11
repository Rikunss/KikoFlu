/// Data model representing the complete audio playback chain information.
///
/// Collected from [AudioPlayerService], [EqualizerService], [HiResAudioService],
/// and various Riverpod providers to display a Poweramp-style Audio Info panel.
class AudioInfoData {
  final String? fileName;
  final String? format;
  final Duration? duration;
  final int? sampleRate;
  final int? bitDepth;
  final int? channels;
  final int? bitrate;

  final String decoder;

  final bool equalizerEnabled;
  final String? equalizerPreset;
  final Duration crossfadeDuration;
  final double volume;
  final double speed;
  final bool repeatEnabled;
  final bool shuffleEnabled;
  final bool replayGainEnabled;
  final double? replayGainValue;
  final bool volumeNormalizationEnabled;

  final int? originalSampleRate;
  final int? outputSampleRate;
  final bool resamplerActive;

  final String output;
  final bool exclusiveMode;
  final bool? bitPerfect;

  final String? deviceName;
  final String? usbDacName;
  final String? usbDacVid;
  final String? usbDacPid;

  final bool usbDacConnected;
  final String? usbDacDeviceName;
  final String? usbDacVendorId;
  final String? usbDacProductId;
  final int? usbDacSampleRate;
  final bool usbDacExclusiveMode;
  final String? usbDacStreamingState;

  final bool androidMixerBypassed;

  final int? audioSessionId;
  final String playerState;
  final Duration currentPosition;
  final Duration? totalDuration;
  final String? outputDevice;
  final String? bufferState;

  /// Human-readable AAudio mode description (e.g. "Exclusive", "Shared", "N/A").
  final String aaudioFormatDesc;

  const AudioInfoData({
    this.fileName,
    this.format,
    this.duration,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    this.bitrate,
    this.decoder = 'Unknown',
    this.equalizerEnabled = false,
    this.equalizerPreset,
    this.crossfadeDuration = Duration.zero,
    this.volume = 1.0,
    this.speed = 1.0,
    this.repeatEnabled = false,
    this.shuffleEnabled = false,
    this.replayGainEnabled = false,
    this.replayGainValue,
    this.volumeNormalizationEnabled = false,
    this.originalSampleRate,
    this.outputSampleRate,
    this.resamplerActive = false,
    this.output = 'Default',
    this.exclusiveMode = false,
    this.bitPerfect,
    this.deviceName,
    this.usbDacName,
    this.usbDacVid,
    this.usbDacPid,
    this.usbDacConnected = false,
    this.usbDacDeviceName,
    this.usbDacVendorId,
    this.usbDacProductId,
    this.usbDacSampleRate,
    this.usbDacExclusiveMode = false,
    this.usbDacStreamingState,
    this.androidMixerBypassed = false,
    this.audioSessionId,
    this.playerState = 'Stopped',
    this.currentPosition = Duration.zero,
    this.totalDuration,
    this.outputDevice,
    this.aaudioFormatDesc = 'N/A',
    this.bufferState,
  });

  /// Whether the source track is hi-res (sample rate > 48kHz).
  bool get isHiRes => (sampleRate ?? 0) > 48000;
}