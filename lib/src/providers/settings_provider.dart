import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sort_options.dart';
import '../services/audio_conversion_service.dart';
import '../services/progress_sync_service.dart';

/// Triggers when Settings screen should refresh cache-related information.
final settingsCacheRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Triggers when Subtitle Library screen should refresh (e.g., after path change).
final subtitleLibraryRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// 字幕库匹配优先级
enum SubtitleLibraryPriority {
  /// 最优先 - 字幕库优先于文件树匹配
  highest('优先', 'highest'),

  /// 最后 - 字幕库在文件树匹配之后
  lowest('滞后', 'lowest');

  final String displayName;
  final String value;
  const SubtitleLibraryPriority(this.displayName, this.value);
}

/// 字幕库优先级设置
class SubtitleLibraryPriorityNotifier
    extends StateNotifier<SubtitleLibraryPriority> {
  static const String _preferenceKey = 'subtitle_library_priority';

  SubtitleLibraryPriorityNotifier() : super(SubtitleLibraryPriority.highest) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getString(_preferenceKey);

      if (savedValue != null) {
        final priority = SubtitleLibraryPriority.values.firstWhere(
          (p) => p.value == savedValue,
          orElse: () => SubtitleLibraryPriority.highest,
        );
        state = priority;
      }
    } catch (e) {
      // 加载失败，使用默认值
      state = SubtitleLibraryPriority.highest;
    }
  }

  Future<void> updatePriority(SubtitleLibraryPriority priority) async {
    state = priority;
    await _savePreference();
  }

  Future<void> _savePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKey, state.value);
    } catch (e) {
      // 保存失败时静默处理
    }
  }
}

/// 字幕库优先级提供者
final subtitleLibraryPriorityProvider = StateNotifierProvider<
    SubtitleLibraryPriorityNotifier, SubtitleLibraryPriority>((ref) {
  return SubtitleLibraryPriorityNotifier();
});

/// 音频格式类型
enum AudioFormat {
  mp3('MP3', 'mp3'),
  flac('FLAC', 'flac'),
  wav('WAV', 'wav'),
  opus('Opus', 'opus'),
  m4a('M4A', 'm4a'),
  aac('AAC', 'aac');

  final String displayName;
  final String extension;
  const AudioFormat(this.displayName, this.extension);
}

/// 翻译源
enum TranslationSource {
  google('Google 翻译', 'google'),
  llm('LLM 翻译', 'llm');

  final String displayName;
  final String value;
  const TranslationSource(this.displayName, this.value);
}

class LLMSettings {
  final String apiUrl;
  final String apiKey;
  final String model;
  final String prompt;
  final int concurrency;

  const LLMSettings({
    this.apiUrl = 'https://api.openai.com/v1/chat/completions',
    this.apiKey = '',
    this.model = 'gpt-3.5-turbo',
    this.prompt = '',
    this.concurrency = 3,
  });

  LLMSettings copyWith({
    String? apiUrl,
    String? apiKey,
    String? model,
    String? prompt,
    int? concurrency,
  }) {
    return LLMSettings(
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      prompt: prompt ?? this.prompt,
      concurrency: concurrency ?? this.concurrency,
    );
  }
}

class LLMSettingsNotifier extends StateNotifier<LLMSettings> {
  static const String _prefix = 'llm_settings_';

  LLMSettingsNotifier() : super(const LLMSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = LLMSettings(
        apiUrl: prefs.getString('${_prefix}api_url') ?? state.apiUrl,
        apiKey: prefs.getString('${_prefix}api_key') ?? state.apiKey,
        model: prefs.getString('${_prefix}model') ?? state.model,
        prompt: prefs.getString('${_prefix}prompt') ?? state.prompt,
        concurrency: prefs.getInt('${_prefix}concurrency') ?? state.concurrency,
      );
    } catch (e) {
      // ignore
    }
  }

  Future<void> updateSettings(LLMSettings settings) async {
    state = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_prefix}api_url', settings.apiUrl);
      await prefs.setString('${_prefix}api_key', settings.apiKey);
      await prefs.setString('${_prefix}model', settings.model);
      await prefs.setString('${_prefix}prompt', settings.prompt);
      await prefs.setInt('${_prefix}concurrency', settings.concurrency);
    } catch (e) {
      // ignore
    }
  }
}

final llmSettingsProvider =
    StateNotifierProvider<LLMSettingsNotifier, LLMSettings>((ref) {
  return LLMSettingsNotifier();
});

/// 翻译源设置
class TranslationSourceNotifier extends StateNotifier<TranslationSource> {
  static const String _preferenceKey = 'translation_source';

  TranslationSourceNotifier() : super(TranslationSource.google) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getString(_preferenceKey);

      if (savedValue != null) {
        final source = TranslationSource.values.firstWhere(
          (s) => s.value == savedValue,
          orElse: () => TranslationSource.google,
        );
        state = source;
      }
    } catch (e) {
      state = TranslationSource.google;
    }
  }

  Future<void> updateSource(TranslationSource source) async {
    state = source;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKey, state.value);
    } catch (e) {
      // ignore
    }
  }
}

final translationSourceProvider =
    StateNotifierProvider<TranslationSourceNotifier, TranslationSource>((ref) {
  return TranslationSourceNotifier();
});

/// 音频格式优先级设置
class AudioFormatPreference {
  final List<AudioFormat> priority;

  const AudioFormatPreference({
    this.priority = const [
      AudioFormat.mp3,
      AudioFormat.flac,
      AudioFormat.wav,
      AudioFormat.opus,
      AudioFormat.m4a,
      AudioFormat.aac,
    ],
  });

  AudioFormatPreference copyWith({List<AudioFormat>? priority}) {
    return AudioFormatPreference(
      priority: priority ?? this.priority,
    );
  }
}

/// 音频格式优先级控制器
class AudioFormatPreferenceNotifier
    extends StateNotifier<AudioFormatPreference> {
  static const String _preferenceKey = 'audio_format_preference';

  AudioFormatPreferenceNotifier() : super(const AudioFormatPreference()) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getStringList(_preferenceKey);

      if (savedOrder != null && savedOrder.isNotEmpty) {
        final priority = savedOrder
            .map((ext) => AudioFormat.values.firstWhere(
                  (format) => format.extension == ext,
                  orElse: () => AudioFormat.mp3,
                ))
            .toList();

        // 确保所有格式都存在
        for (final format in AudioFormat.values) {
          if (!priority.contains(format)) {
            priority.add(format);
          }
        }

        state = AudioFormatPreference(priority: priority);
      }
    } catch (e) {
      // 加载失败，使用默认值
      state = const AudioFormatPreference();
    }
  }

  Future<void> updatePriority(List<AudioFormat> newPriority) async {
    state = state.copyWith(priority: newPriority);
    await _savePreference();
  }

  Future<void> _savePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final order = state.priority.map((format) => format.extension).toList();
      await prefs.setStringList(_preferenceKey, order);
    } catch (e) {
      // 保存失败时静默处理
    }
  }

  Future<void> resetToDefault() async {
    state = const AudioFormatPreference();
    await _savePreference();
  }
}

/// 音频格式优先级提供者
final audioFormatPreferenceProvider =
    StateNotifierProvider<AudioFormatPreferenceNotifier, AudioFormatPreference>(
        (ref) {
  return AudioFormatPreferenceNotifier();
});

/// 防社死设置
class PrivacyModeSettings {
  final bool enabled;
  final bool blurCover;
  final bool blurCoverInApp;
  final bool maskTitle;
  final String customTitle;

  const PrivacyModeSettings({
    this.enabled = false,
    this.blurCover = true,
    this.blurCoverInApp = false,
    this.maskTitle = false,
    this.customTitle = '正在播放音频',
  });

  PrivacyModeSettings copyWith({
    bool? enabled,
    bool? blurCover,
    bool? blurCoverInApp,
    bool? maskTitle,
    String? customTitle,
  }) {
    return PrivacyModeSettings(
      enabled: enabled ?? this.enabled,
      blurCover: blurCover ?? this.blurCover,
      blurCoverInApp: blurCoverInApp ?? this.blurCoverInApp,
      maskTitle: maskTitle ?? this.maskTitle,
      customTitle: customTitle ?? this.customTitle,
    );
  }
}

/// 防社死设置控制器
class PrivacyModeSettingsNotifier extends StateNotifier<PrivacyModeSettings> {
  static const String _enabledKey = 'privacy_mode_enabled';
  static const String _blurCoverKey = 'privacy_mode_blur_cover';
  static const String _blurCoverInAppKey = 'privacy_mode_blur_cover_in_app';
  static const String _maskTitleKey = 'privacy_mode_mask_title';
  static const String _customTitleKey = 'privacy_mode_custom_title';

  PrivacyModeSettingsNotifier() : super(const PrivacyModeSettings()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blurCover = prefs.getBool(_blurCoverKey) ?? true;
      final blurCoverInApp = prefs.getBool(_blurCoverInAppKey) ?? false;

      state = PrivacyModeSettings(
        enabled: prefs.getBool(_enabledKey) ?? false,
        blurCover: blurCover,
        blurCoverInApp: blurCoverInApp,
        maskTitle: prefs.getBool(_maskTitleKey) ?? false,
        customTitle: prefs.getString(_customTitleKey) ?? '正在播放音频',
      );
    } catch (e) {
      // 加载失败，使用默认值
      state = const PrivacyModeSettings();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    await _savePreference(_enabledKey, enabled);
  }

  Future<void> setBlurCover(bool blur) async {
    state = state.copyWith(blurCover: blur);
    await _savePreference(_blurCoverKey, blur);
  }

  Future<void> setBlurCoverInApp(bool blur) async {
    state = state.copyWith(blurCoverInApp: blur);
    await _savePreference(_blurCoverInAppKey, blur);
  }

  Future<void> setMaskTitle(bool mask) async {
    state = state.copyWith(maskTitle: mask);
    await _savePreference(_maskTitleKey, mask);
  }

  Future<void> setCustomTitle(String title) async {
    state = state.copyWith(customTitle: title);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customTitleKey, title);
  }

  Future<void> _savePreference(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      // 保存失败时静默处理
    }
  }
}

/// 防社死设置提供者
final privacyModeSettingsProvider =
    StateNotifierProvider<PrivacyModeSettingsNotifier, PrivacyModeSettings>(
        (ref) {
  return PrivacyModeSettingsNotifier();
});

/// 分页大小设置
class PageSizeNotifier extends StateNotifier<int> {
  static const String _preferenceKey = 'page_size_preference';
  static const int defaultSize = 40;

  PageSizeNotifier() : super(defaultSize) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getInt(_preferenceKey);
      if (savedValue != null && [20, 40, 60, 100].contains(savedValue)) {
        state = savedValue;
      }
    } catch (e) {
      state = defaultSize;
    }
  }

  Future<void> updatePageSize(int size) async {
    if (![20, 40, 60, 100].contains(size)) return;
    state = size;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_preferenceKey, size);
    } catch (e) {
      // ignore
    }
  }
}

/// 分页大小提供者
final pageSizeProvider = StateNotifierProvider<PageSizeNotifier, int>((ref) {
  return PageSizeNotifier();
});

/// 默认排序设置状态
class DefaultSortState {
  final SortOrder order;
  final SortDirection direction;

  const DefaultSortState({
    this.order = SortOrder.release,
    this.direction = SortDirection.desc,
  });
}

/// 音频直通模式设置
class AudioPassthroughNotifier extends StateNotifier<bool> {
  static const String _preferenceKey = 'audio_passthrough_enabled';

  AudioPassthroughNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_preferenceKey) ?? false;
    } catch (e) {
      state = false;
    }
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferenceKey, enabled);
    } catch (e) {
      // ignore
    }
  }
}

/// 音频直通模式提供者
final audioPassthroughProvider =
    StateNotifierProvider<AudioPassthroughNotifier, bool>((ref) {
  return AudioPassthroughNotifier();
});

/// 默认排序设置
class DefaultSortNotifier extends StateNotifier<DefaultSortState> {
  static const String _orderKey = 'default_sort_order';
  static const String _directionKey = 'default_sort_direction';

  DefaultSortNotifier() : super(const DefaultSortState()) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderValue = prefs.getString(_orderKey);
      final directionValue = prefs.getString(_directionKey);

      SortOrder order = SortOrder.release;
      if (orderValue != null) {
        order = SortOrder.values.firstWhere(
          (e) => e.value == orderValue,
          orElse: () => SortOrder.release,
        );
      }

      SortDirection direction = SortDirection.desc;
      if (directionValue != null) {
        direction = SortDirection.values.firstWhere(
          (e) => e.value == directionValue,
          orElse: () => SortDirection.desc,
        );
      }

      state = DefaultSortState(order: order, direction: direction);
    } catch (e) {
      // ignore
    }
  }

  Future<void> updateDefaultSort(
      SortOrder order, SortDirection direction) async {
    state = DefaultSortState(order: order, direction: direction);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_orderKey, order.value);
      await prefs.setString(_directionKey, direction.value);
    } catch (e) {
      // ignore
    }
  }
}

/// 默认排序提供者
final defaultSortProvider =
    StateNotifierProvider<DefaultSortNotifier, DefaultSortState>((ref) {
  return DefaultSortNotifier();
});

/// 屏蔽列表状态
class BlockedItemsState {
  final List<String> tags;
  final List<String> cvs;
  final List<String> circles;

  const BlockedItemsState({
    this.tags = const [],
    this.cvs = const [],
    this.circles = const [],
  });

  BlockedItemsState copyWith({
    List<String>? tags,
    List<String>? cvs,
    List<String>? circles,
  }) {
    return BlockedItemsState(
      tags: tags ?? this.tags,
      cvs: cvs ?? this.cvs,
      circles: circles ?? this.circles,
    );
  }
}

/// 屏蔽列表通知器
class BlockedItemsNotifier extends StateNotifier<BlockedItemsState> {
  static const String _tagsKey = 'blocked_tags';
  static const String _cvsKey = 'blocked_cvs';
  static const String _circlesKey = 'blocked_circles';

  BlockedItemsNotifier() : super(const BlockedItemsState()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tags = prefs.getStringList(_tagsKey) ?? [];
      final cvs = prefs.getStringList(_cvsKey) ?? [];
      final circles = prefs.getStringList(_circlesKey) ?? [];
      state = BlockedItemsState(tags: tags, cvs: cvs, circles: circles);
    } catch (e) {
      // ignore
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_tagsKey, state.tags);
      await prefs.setStringList(_cvsKey, state.cvs);
      await prefs.setStringList(_circlesKey, state.circles);
    } catch (e) {
      // ignore
    }
  }

  Future<void> addTag(String tag) async {
    if (!state.tags.contains(tag)) {
      state = state.copyWith(tags: [...state.tags, tag]);
      await _savePreferences();
    }
  }

  Future<void> removeTag(String tag) async {
    state = state.copyWith(tags: state.tags.where((t) => t != tag).toList());
    await _savePreferences();
  }

  Future<void> addCv(String cv) async {
    if (!state.cvs.contains(cv)) {
      state = state.copyWith(cvs: [...state.cvs, cv]);
      await _savePreferences();
    }
  }

  Future<void> removeCv(String cv) async {
    state = state.copyWith(cvs: state.cvs.where((c) => c != cv).toList());
    await _savePreferences();
  }

  Future<void> addCircle(String circle) async {
    if (!state.circles.contains(circle)) {
      state = state.copyWith(circles: [...state.circles, circle]);
      await _savePreferences();
    }
  }

  Future<void> removeCircle(String circle) async {
    state = state.copyWith(
        circles: state.circles.where((c) => c != circle).toList());
    await _savePreferences();
  }
}

/// 屏蔽列表提供者
final blockedItemsProvider =
    StateNotifierProvider<BlockedItemsNotifier, BlockedItemsState>((ref) {
  return BlockedItemsNotifier();
});

/// Preferred sample rate for hi-res audio
enum PreferredSampleRate {
  auto('Auto', 0, 'auto'),
  sr44100('44100 Hz', 44100, '44100'),
  sr48000('48000 Hz', 48000, '48000'),
  sr96000('96000 Hz', 96000, '96000'),
  sr192000('192000 Hz', 192000, '192000');

  final String displayName;
  final int sampleRate;
  final String value;
  const PreferredSampleRate(this.displayName, this.sampleRate, this.value);
}

/// Preferred sample rate setting
class PreferredSampleRateNotifier extends StateNotifier<PreferredSampleRate> {
  static const String _preferenceKey = 'preferred_sample_rate';

  PreferredSampleRateNotifier() : super(PreferredSampleRate.auto) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getString(_preferenceKey);
      if (savedValue != null) {
        final rate = PreferredSampleRate.values.firstWhere(
          (r) => r.value == savedValue,
          orElse: () => PreferredSampleRate.auto,
        );
        state = rate;
      }
    } catch (e) {
      state = PreferredSampleRate.auto;
    }
  }

  Future<void> updateRate(PreferredSampleRate rate) async {
    state = rate;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKey, rate.value);
    } catch (e) {
      // ignore
    }
  }
}

/// Preferred sample rate provider
final preferredSampleRateProvider =
    StateNotifierProvider<PreferredSampleRateNotifier, PreferredSampleRate>((ref) {
  return PreferredSampleRateNotifier();
});

/// Crossfade duration setting (in milliseconds, 0 = off/gapless)
class CrossfadeDurationNotifier extends StateNotifier<int> {
  static const String _preferenceKey = 'crossfade_duration_ms';

  CrossfadeDurationNotifier() : super(0) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getInt(_preferenceKey);
      if (savedValue != null && savedValue >= 0 && savedValue <= 10000) {
        state = savedValue;
      }
    } catch (e) {
      state = 0;
    }
  }

  Future<void> updateDuration(int ms) async {
    state = ms.clamp(0, 10000);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_preferenceKey, state);
    } catch (e) {
      // ignore
    }
  }
}

/// Crossfade duration provider
final crossfadeDurationProvider =
    StateNotifierProvider<CrossfadeDurationNotifier, int>((ref) {
  return CrossfadeDurationNotifier();
});/// ReplayGain setting.
class ReplayGainSettings {
  final bool enabled;
  final double preampDb;

  const ReplayGainSettings({
    this.enabled = false,
    this.preampDb = 0.0,
  });

  ReplayGainSettings copyWith({bool? enabled, double? preampDb}) {
    return ReplayGainSettings(
      enabled: enabled ?? this.enabled,
      preampDb: preampDb ?? this.preampDb,
    );
  }
}

class ReplayGainNotifier extends StateNotifier<ReplayGainSettings> {
  static const String _enabledKey = 'replay_gain_enabled';
  static const String _preampKey = 'replay_gain_preamp_db';

  ReplayGainNotifier() : super(const ReplayGainSettings()) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ReplayGainSettings(
        enabled: prefs.getBool(_enabledKey) ?? false,
        preampDb: prefs.getDouble(_preampKey) ?? 0.0,
      );
    } catch (e) {
      state = const ReplayGainSettings();
    }
  }

  Future<void> toggle(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
    } catch (e) {/* ignore */}
  }

  Future<void> setPreampDb(double db) async {
    state = state.copyWith(preampDb: db.clamp(-12.0, 12.0));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_preampKey, state.preampDb);
    } catch (e) {/* ignore */}
  }
}

final replayGainSettingsProvider =
    StateNotifierProvider<ReplayGainNotifier, ReplayGainSettings>((ref) {
  return ReplayGainNotifier();
});

/// Volume Normalization setting.
class VolumeNormalizationSettings {
  final bool enabled;
  final double targetLevelDb;

  const VolumeNormalizationSettings({
    this.enabled = false,
    this.targetLevelDb = -14.0,
  });

  VolumeNormalizationSettings copyWith({bool? enabled, double? targetLevelDb}) {
    return VolumeNormalizationSettings(
      enabled: enabled ?? this.enabled,
      targetLevelDb: targetLevelDb ?? this.targetLevelDb,
    );
  }
}

class VolumeNormalizationNotifier extends StateNotifier<VolumeNormalizationSettings> {
  static const String _enabledKey = 'volume_normalization_enabled';
  static const String _targetKey = 'volume_normalization_target_db';

  VolumeNormalizationNotifier() : super(const VolumeNormalizationSettings()) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = VolumeNormalizationSettings(
        enabled: prefs.getBool(_enabledKey) ?? false,
        targetLevelDb: prefs.getDouble(_targetKey) ?? -14.0,
      );
    } catch (e) {
      state = const VolumeNormalizationSettings();
    }
  }

  Future<void> toggle(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
    } catch (e) {/* ignore */}
  }

  Future<void> setTargetLevel(double db) async {
    state = state.copyWith(targetLevelDb: db.clamp(-24.0, -6.0));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_targetKey, state.targetLevelDb);
    } catch (e) {/* ignore */}
  }
}

final volumeNormalizationProvider =
    StateNotifierProvider<VolumeNormalizationNotifier, VolumeNormalizationSettings>(
        (ref) {
  return VolumeNormalizationNotifier();
});

/// Bit-Perfect Playback mode setting (Android only).
///
/// Merges the old Hi-Res Exclusive Mode and USB DAC Bypass into one toggle.
/// When enabled, USB DAC detection is active, device picker appears, and
/// audio can be streamed directly to the external DAC via libusb,
/// bypassing Android's audio mixer for pristine bit-perfect output.
class BitPerfectPlaybackSettings {
  final bool enabled;
  final int? preferredDeviceId;

  const BitPerfectPlaybackSettings({
    this.enabled = false,
    this.preferredDeviceId,
  });

  BitPerfectPlaybackSettings copyWith({bool? enabled, int? preferredDeviceId}) {
    return BitPerfectPlaybackSettings(
      enabled: enabled ?? this.enabled,
      preferredDeviceId: preferredDeviceId ?? this.preferredDeviceId,
    );
  }
}

class BitPerfectPlaybackNotifier extends StateNotifier<BitPerfectPlaybackSettings> {
  static const String _enabledKey = 'bit_perfect_playback_enabled';
  static const String _deviceIdKey = 'bit_perfect_playback_device_id';

  BitPerfectPlaybackNotifier() : super(const BitPerfectPlaybackSettings()) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = BitPerfectPlaybackSettings(
        enabled: prefs.getBool(_enabledKey) ?? false,
        preferredDeviceId: prefs.getInt(_deviceIdKey),
      );
    } catch (e) {
      state = const BitPerfectPlaybackSettings();
    }
  }

  Future<void> toggle(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
    } catch (e) {
      // ignore
    }
  }

  Future<void> setPreferredDevice(int? deviceId) async {
    state = state.copyWith(preferredDeviceId: deviceId);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (deviceId != null) {
        await prefs.setInt(_deviceIdKey, deviceId);
      } else {
        await prefs.remove(_deviceIdKey);
      }
    } catch (e) {
      // ignore
    }
  }
}

/// Bit-Perfect Playback provider
final bitPerfectPlaybackProvider =
    StateNotifierProvider<BitPerfectPlaybackNotifier, BitPerfectPlaybackSettings>((ref) {
  return BitPerfectPlaybackNotifier();
});

/// Progress Sync (cross-device) setting.
class ProgressSyncNotifier extends StateNotifier<bool> {
  static const String _preferenceKey = 'progress_sync_enabled';

  ProgressSyncNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_preferenceKey) ?? true;
    } catch (e) {
      state = true;
    }
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    ProgressSyncService.instance.setEnabled(enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferenceKey, enabled);
    } catch (e) {
      // ignore
    }
  }
}

/// Progress Sync provider
final progressSyncProvider =
    StateNotifierProvider<ProgressSyncNotifier, bool>((ref) {
  return ProgressSyncNotifier();
});

/// Auto-translate lyrics setting.
class AutoTranslateLyricsNotifier extends StateNotifier<bool> {
  static const String _preferenceKey = 'auto_translate_lyrics';

  AutoTranslateLyricsNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_preferenceKey) ?? false;
    } catch (e) {
      state = false;
    }
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferenceKey, enabled);
    } catch (e) {
      // ignore
    }
  }
}

/// Auto-translate lyrics provider
final autoTranslateLyricsProvider =
    StateNotifierProvider<AutoTranslateLyricsNotifier, bool>((ref) {
  return AutoTranslateLyricsNotifier();
});

/// Convert WAV files to another format after download.
class WavConversionFormatNotifier extends StateNotifier<WavConversionFormat> {
  static const String _preferenceKeyNew = 'wav_conversion_format';
  static const String _preferenceKeyOld = 'convert_wav_after_download';

  WavConversionFormatNotifier() : super(WavConversionFormat.none) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Try new key (string-based)
      final savedValue = prefs.getString(_preferenceKeyNew);
      if (savedValue != null) {
        final format = WavConversionFormat.values.firstWhere(
          (f) => f.value == savedValue,
          orElse: () => WavConversionFormat.none,
        );
        state = format;
        return;
      }

      // Migrate from old bool key
      final oldEnabled = prefs.getBool(_preferenceKeyOld);
      if (oldEnabled == true) {
        state = WavConversionFormat.flac; // old default
        // Save to new key and remove old
        await prefs.setString(_preferenceKeyNew, WavConversionFormat.flac.value);
        await prefs.remove(_preferenceKeyOld);
      }
    } catch (e) {
      state = WavConversionFormat.none;
    }
  }

  Future<void> setFormat(WavConversionFormat format) async {
    state = format;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKeyNew, format.value);
      // Clean up old key if present
      if (prefs.containsKey(_preferenceKeyOld)) {
        await prefs.remove(_preferenceKeyOld);
      }
    } catch (e) {
      // ignore
    }
  }
}

final wavConversionFormatProvider =
    StateNotifierProvider<WavConversionFormatNotifier, WavConversionFormat>((ref) {
  return WavConversionFormatNotifier();
});

/// Show FPS overlay (debug only — persisted in SharedPreferences).
class FpsOverlayNotifier extends StateNotifier<bool> {
  static const String _preferenceKey = 'show_fps_overlay';

  FpsOverlayNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_preferenceKey) ?? false;
    } catch (e) {
      state = false;
    }
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferenceKey, enabled);
    } catch (e) {
      // ignore
    }
  }
}

final showFpsOverlayProvider =
    StateNotifierProvider<FpsOverlayNotifier, bool>((ref) {
  return FpsOverlayNotifier();
});

