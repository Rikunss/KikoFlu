import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Types of rules that can be applied to a smart playlist.
enum SmartPlaylistRuleType {
  tag('tag'),
  va('va'),
  circle('circle'),
  age('age'),
  rating('rating'),
  subtitle('subtitle');

  final String value;
  const SmartPlaylistRuleType(this.value);

  static SmartPlaylistRuleType fromValue(String value) {
    return SmartPlaylistRuleType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SmartPlaylistRuleType.tag,
    );
  }
}

/// A single rule for a smart playlist.
class SmartPlaylistRule extends Equatable {
  final SmartPlaylistRuleType type;
  final String value;
  final bool isExclude;

  const SmartPlaylistRule({
    required this.type,
    required this.value,
    this.isExclude = false,
  });

  factory SmartPlaylistRule.fromJson(Map<String, dynamic> json) {
    return SmartPlaylistRule(
      type: SmartPlaylistRuleType.fromValue(json['type'] as String),
      value: json['value'] as String,
      isExclude: (json['isExclude'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.value,
        'value': value,
        'isExclude': isExclude,
      };

  @override
  List<Object?> get props => [type, value, isExclude];
}

/// Sort options for smart playlist evaluation.
enum SmartPlaylistSortField {
  release('release'),
  createDate('create_date'),
  rating('rating'),
  dlCount('dl_count'),
  price('price');

  final String value;
  const SmartPlaylistSortField(this.value);

  static SmartPlaylistSortField fromValue(String value) {
    return SmartPlaylistSortField.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SmartPlaylistSortField.release,
    );
  }
}

/// A smart playlist that auto-generates its contents based on rules.
/// Stored locally via SharedPreferences.
class SmartPlaylist extends Equatable {
  final String id;
  final String name;
  final String description;
  final List<SmartPlaylistRule> rules;
  final SmartPlaylistSortField sortField;
  final String sortDirection; // 'asc' or 'desc'
  final DateTime createdAt;
  final DateTime updatedAt;
  final int cachedWorksCount; // cached from last evaluation

  const SmartPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    this.rules = const [],
    this.sortField = SmartPlaylistSortField.release,
    this.sortDirection = 'desc',
    required this.createdAt,
    required this.updatedAt,
    this.cachedWorksCount = 0,
  });

  SmartPlaylist copyWith({
    String? id,
    String? name,
    String? description,
    List<SmartPlaylistRule>? rules,
    SmartPlaylistSortField? sortField,
    String? sortDirection,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? cachedWorksCount,
  }) {
    return SmartPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      rules: rules ?? this.rules,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cachedWorksCount: cachedWorksCount ?? this.cachedWorksCount,
    );
  }

  factory SmartPlaylist.fromJson(Map<String, dynamic> json) {
    return SmartPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      rules: (json['rules'] as List<dynamic>?)
              ?.map((r) => SmartPlaylistRule.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      sortField: SmartPlaylistSortField.fromValue(
          (json['sortField'] as String?) ?? 'release'),
      sortDirection: (json['sortDirection'] as String?) ?? 'desc',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      cachedWorksCount: (json['cachedWorksCount'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'rules': rules.map((r) => r.toJson()).toList(),
        'sortField': sortField.value,
        'sortDirection': sortDirection,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'cachedWorksCount': cachedWorksCount,
      };

  /// Convert to JSON string for storage.
  String toJsonString() => jsonEncode(toJson());

  /// Create from JSON string.
  factory SmartPlaylist.fromJsonString(String jsonString) {
    return SmartPlaylist.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Human-readable summary of rules.
  String get rulesSummary {
    if (rules.isEmpty) return 'No rules';
    final parts = <String>[];
    for (final rule in rules) {
      switch (rule.type) {
        case SmartPlaylistRuleType.tag:
          parts.add(rule.isExclude ? '✕ ${rule.value}' : rule.value);
        case SmartPlaylistRuleType.va:
          parts.add('VA: ${rule.value}');
        case SmartPlaylistRuleType.circle:
          parts.add('Circle: ${rule.value}');
        case SmartPlaylistRuleType.age:
          parts.add('Age: ${rule.value}');
        case SmartPlaylistRuleType.rating:
          parts.add('☆${rule.value}+');
        case SmartPlaylistRuleType.subtitle:
          parts.add(rule.value == 'true' ? 'Subbed' : 'No sub');
      }
    }
    return parts.join(', ');
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        rules,
        sortField,
        sortDirection,
        createdAt,
        updatedAt,
        cachedWorksCount,
      ];
}
