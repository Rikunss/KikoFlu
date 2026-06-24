import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'translation_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

class LLMTranslator {
  final Dio _dio = Dio();
  static const _secureStorage = FlutterSecureStorage();

  Future<String> translate(String text,
      {String? sourceLang, Locale? locale}) async {
    if (text.isEmpty) return text;

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('llm_settings_api_url') ??
          'https://api.openai.com/v1/chat/completions';
      final apiKey = await _secureStorage.read(key: 'llm_api_key') ?? '';
      final model = prefs.getString('llm_settings_model') ?? 'gpt-3.5-turbo';
      final savedPrompt = prefs.getString('llm_settings_prompt');
      final prompt = (savedPrompt == null || savedPrompt.isEmpty)
          ? TranslationService.getDefaultLLMPrompt(
              locale ?? const Locale('zh'))
          : savedPrompt;

      if (apiKey.isEmpty) {
        return 'Error: API Key is missing. Please configure LLM settings.';
      }

      final response = await _dio.post(
        apiUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
        ),
        data: {
          'model': model,
          'messages': [
            {'role': 'system', 'content': prompt},
            {'role': 'user', 'content': text},
          ],
          'temperature': 0.3,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null &&
            data['choices'] != null &&
            data['choices'].isNotEmpty) {
          final choice = data['choices'][0];
          final message = choice is Map ? choice['message'] : null;
          final content = message is Map ? message['content'] : null;
          return content?.toString().trim() ?? text;
        }
      }
      return text;
    } catch (e) {
      _log.error('LLM translation error: $e');
      if (e is DioException) {
        if (e.response != null) {
          _log.info('Response data: ${e.response?.data}');
          return 'Error: ${e.response?.statusCode} - ${e.response?.statusMessage}';
        }
      }
      return text;
    }
  }
}
