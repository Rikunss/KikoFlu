import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_service.dart';

/// Persisted AI/Whisper model settings.
class AISettings {
  final bool modelDownloaded;
  final String? modelPath;
  final int? modelSizeBytes;
  final String selectedModel;
  final int transcriptionThreads;
  final bool splitOnWord;

  const AISettings({
    this.modelDownloaded = false,
    this.modelPath,
    this.modelSizeBytes,
    this.selectedModel = 'base',
    this.transcriptionThreads = 4,
    this.splitOnWord = false,
  });

  AISettings copyWith({
    bool? modelDownloaded,
    String? modelPath,
    int? modelSizeBytes,
    String? selectedModel,
    int? transcriptionThreads,
    bool? splitOnWord,
  }) {
    return AISettings(
      modelDownloaded: modelDownloaded ?? this.modelDownloaded,
      modelPath: modelPath ?? this.modelPath,
      modelSizeBytes: modelSizeBytes ?? this.modelSizeBytes,
      selectedModel: selectedModel ?? this.selectedModel,
      transcriptionThreads: transcriptionThreads ?? this.transcriptionThreads,
      splitOnWord: splitOnWord ?? this.splitOnWord,
    );
  }
}

class AISettingsNotifier extends StateNotifier<AISettings> {
  static const String _downloadedKey = 'ai_model_downloaded';
  static const String _pathKey = 'ai_model_path';
  static const String _sizeKey = 'ai_model_size_bytes';
  static const String _modelKey = 'ai_selected_model';
  static const String _threadsKey = 'ai_transcription_threads';
  static const String _splitOnWordKey = 'ai_split_on_word';

  AISettingsNotifier() : super(const AISettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AISettings(
        modelDownloaded: prefs.getBool(_downloadedKey) ?? false,
        modelPath: prefs.getString(_pathKey),
        modelSizeBytes: prefs.getInt(_sizeKey),
        selectedModel: prefs.getString(_modelKey) ?? 'base',
        transcriptionThreads: prefs.getInt(_threadsKey) ?? 4,
        splitOnWord: prefs.getBool(_splitOnWordKey) ?? false,
      );
    } catch (e) {
      LogService.instance.warning('[AISettingsNotifier] error: $e', tag: 'AISettings');
    }
  }

  Future<void> setSelectedModel(String model) async {
    state = state.copyWith(selectedModel: model);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelKey, model);
    } catch (e) {
      LogService.instance.warning('[AISettingsNotifier] error: $e', tag: 'AISettings');
    }
  }

  Future<void> setTranscriptionThreads(int threads) async {
    state = state.copyWith(transcriptionThreads: threads);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_threadsKey, threads);
    } catch (e) {
      LogService.instance.warning('[AISettingsNotifier] error: $e', tag: 'AISettings');
    }
  }

  Future<void> setSplitOnWord(bool value) async {
    state = state.copyWith(splitOnWord: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_splitOnWordKey, value);
    } catch (e) {
      LogService.instance.warning('[AISettingsNotifier] error: $e', tag: 'AISettings');
    }
  }

  Future<void> markModelDownloaded(String path, int sizeBytes) async {
    state = AISettings(
      modelDownloaded: true,
      modelPath: path,
      modelSizeBytes: sizeBytes,
      selectedModel: state.selectedModel,
      transcriptionThreads: state.transcriptionThreads,
      splitOnWord: state.splitOnWord,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_downloadedKey, true);
      await prefs.setString(_pathKey, path);
      await prefs.setInt(_sizeKey, sizeBytes);
    } catch (e) {
      LogService.instance.warning('[AISettingsNotifier] error: $e', tag: 'AISettings');
    }
  }

  Future<void> markModelDeleted() async {
    state = const AISettings(selectedModel: 'base');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_downloadedKey);
      await prefs.remove(_pathKey);
      await prefs.remove(_sizeKey);
    } catch (e) {
      LogService.instance.warning('[AISettingsNotifier] error: $e', tag: 'AISettings');
    }
  }
}

final aiSettingsProvider =
    StateNotifierProvider<AISettingsNotifier, AISettings>((ref) {
  return AISettingsNotifier();
});