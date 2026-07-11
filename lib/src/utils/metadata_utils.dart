import '../services/log_service.dart';

/// Sanitize metadata map for use with [Work.fromJson].
/// Converts nested objects with `toJson()` to plain maps,
/// recursively handling lists and maps.
Map<String, dynamic> sanitizeMetadata(Map<String, dynamic> metadata) {
  try {
    return _deepSanitize(metadata) as Map<String, dynamic>;
  } catch (e) {
    LogService.instance.error('Error sanitizing metadata: $e', tag: 'Metadata');
    rethrow;
  }
}

dynamic _deepSanitize(dynamic value) {
  if (value == null) return null;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), _deepSanitize(val)));
  }
  if (value is List) {
    return value.map(_deepSanitize).toList();
  }
  if (const [
    'Va',
    'Tag',
    'AudioFile',
    'RatingDetail',
    'OtherLanguageEdition',
  ].contains(value.runtimeType.toString())) {
    try {
      return _deepSanitize((value as dynamic).toJson());
    } catch (e) {
      LogService.instance.warning(
          'Serialization failed ${value.runtimeType}: $e', tag: 'Metadata');
      return null;
    }
  }
  return value;
}