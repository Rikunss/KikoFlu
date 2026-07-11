import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translator/translator.dart';

void main() {
  group('Translation Sources Availability Test', () {
    test('Google Translator should translate "Hello" to Chinese', () async {
      final translator = GoogleTranslator();
      const sourceText = 'Hello';

      debugPrint('Testing Google Translator...');
      final startTime = DateTime.now();

      try {
        final result = await translator.translate(sourceText, to: 'zh-cn');

        final duration = DateTime.now().difference(startTime);
        debugPrint('Google Translation Result: "$sourceText" -> "${result.text}"');
        debugPrint('Time taken: ${duration.inMilliseconds}ms');

        expect(result.text, isNotEmpty);
        expect(result.text, isNot(equals(sourceText)));
        expect(result.text, anyOf(contains('你好'), contains('您好')));
      } catch (e) {
        debugPrint('Google Translator failed: $e');
        debugPrint('Note: Google Translate might be blocked in your region.');
        rethrow;
      }
    });
  });
}