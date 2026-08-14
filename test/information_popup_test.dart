import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru_flutter/src/models/information_popup.dart';

void main() {
  group('InformationPopup.fromJson', () {
    test('parses clean JSON', () {
      final popup = InformationPopup.fromJson('''
      {
        "id": "promo-2026-08-14",
        "enabled": true,
        "title": "🎉 Promo Spesial!",
        "message": "Diskon 50%",
        "buttonText": "Lihat Detail",
        "buttonUrl": "https://example.com/promo"
      }
      ''');
      expect(popup, isNotNull);
      expect(popup!.id, 'promo-2026-08-14');
      expect(popup.title, '🎉 Promo Spesial!');
      expect(popup.buttonUrl, 'https://example.com/promo');
    });

    test('parses value with // json prefix (as stored in Firebase Console)', () {
      final popup = InformationPopup.fromJson(
        ' // json {   "id": "promo-2026-08-14",   "enabled": true,   '
        '"title": "🎉 Promo Spesial!",   "message": "Diskon 50%",   '
        '"imageUrl": "https://contoh.com/promo.jpg",   '
        '"buttonText": "Lihat Detail",   "buttonUrl": "https://contoh.com/promo" }',
      );
      expect(popup, isNotNull);
      expect(popup!.id, 'promo-2026-08-14');
      expect(popup.title, '🎉 Promo Spesial!');
    });

    test('returns null for invalid JSON', () {
      expect(InformationPopup.fromJson('not json at all'), isNull);
      expect(InformationPopup.fromJson(''), isNull);
    });

    test('returns null when disabled or missing required fields', () {
      expect(
        InformationPopup.fromJson('{"id":"x","enabled":false,"title":"T"}'),
        isNull,
      );
      expect(
        InformationPopup.fromJson('{"id":"x","enabled":true}'),
        isNull,
      );
    });

    test('isActiveOn respects start/end dates', () {
      final popup = InformationPopup.fromJson(
        '{"id":"x","title":"T","startDate":"2026-08-14","endDate":"2026-08-20"}',
      );
      expect(popup, isNotNull);
      expect(popup!.isActiveOn(DateTime(2026, 8, 15)), isTrue);
      expect(popup.isActiveOn(DateTime(2026, 8, 13)), isFalse);
      expect(popup.isActiveOn(DateTime(2026, 8, 21)), isFalse);
    });
  });
}
