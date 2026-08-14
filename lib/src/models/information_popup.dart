import 'dart:convert';

class InformationPopup {
  final String id;

  final bool enabled;
  final String title;
  final String message;
  final String imageUrl;
  final String buttonText;
  final String buttonUrl;
  final DateTime? startDate;
  final DateTime? endDate;

  const InformationPopup({
    required this.id,
    this.enabled = true,
    this.title = '',
    this.message = '',
    this.imageUrl = '',
    this.buttonText = '',
    this.buttonUrl = '',
    this.startDate,
    this.endDate,
  });

  /// Parses the JSON string sent by the server.
  /// Returns null if the JSON is invalid or the popup is not fit to show.
  static InformationPopup? fromJson(String raw) {
    try {
      final decoded = jsonDecode(_sanitize(raw));
      if (decoded is! Map<String, dynamic>) return null;

      final enabled = decoded['enabled'] as bool? ?? true;
      final id = (decoded['id'] as String? ?? '').trim();
      final title = (decoded['title'] as String? ?? '').trim();

      if (!enabled || id.isEmpty || title.isEmpty) return null;

      return InformationPopup(
        id: id,
        enabled: enabled,
        title: title,
        message: decoded['message'] as String? ?? '',
        imageUrl: decoded['imageUrl'] as String? ?? '',
        buttonText: decoded['buttonText'] as String? ?? '',
        buttonUrl: decoded['buttonUrl'] as String? ?? '',
        startDate: _parseDate(decoded['startDate']),
        endDate: _parseDate(decoded['endDate']),
      );
    } catch (_) {
      return null;
    }
  }

  bool isActiveOn(DateTime now) {
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Trims from the first `{` — Console values sometimes carry a prefix
  /// like `// json { ... }` that is not part of the JSON.
  static String _sanitize(String raw) {
    final braceIdx = raw.indexOf('{');
    if (braceIdx >= 0) {
      return raw.substring(braceIdx).trim();
    }
    return raw.trim();
  }
}
