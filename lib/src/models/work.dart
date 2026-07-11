import 'package:json_annotation/json_annotation.dart';
import 'package:equatable/equatable.dart';

part 'work.g.dart';

@JsonSerializable()
class Work extends Equatable {
  final int id;
  final String title;

  @JsonKey(name: 'circle_id')
  final int? circleId;

  final String? name;

  final List<Va>? vas;
  final List<Tag>? tags;
  final String? age;
  final String? release;

  @JsonKey(name: 'dl_count')
  final int? dlCount;

  final int? price;

  @JsonKey(name: 'review_count')
  final int? reviewCount;

  @JsonKey(name: 'rate_count')
  final int? rateCount;

  @JsonKey(name: 'rate_average_2dp')
  final double? rateAverage;

  @JsonKey(name: 'has_subtitle')
  final bool? hasSubtitle;

  final int? duration;

  final String?
      progress;

  @JsonKey(name: 'userRating')
  final int? userRating;

  @JsonKey(name: 'rate_count_detail')
  final List<RatingDetail>? rateCountDetail;

  final List<String>? images;
  final String? description;
  final List<AudioFile>? children;

  @JsonKey(name: 'blur_hash')
  final String? blurHash;

  @JsonKey(name: 'source_url')
  final String? sourceUrl;

  @JsonKey(name: 'other_language_editions_in_db')
  final List<OtherLanguageEdition>? otherLanguageEditions;

  /// For imported local works — path to the original folder on disk.
  /// Null for works downloaded from the server.
  final String? localImportPath;

  const Work({
    required this.id,
    required this.title,
    this.circleId,
    this.name,
    this.vas,
    this.tags,
    this.age,
    this.release,
    this.dlCount,
    this.price,
    this.reviewCount,
    this.rateCount,
    this.rateAverage,
    this.hasSubtitle,
    this.duration,
    this.progress,
    this.userRating,
    this.rateCountDetail,
    this.images,
    this.description,
    this.children,
    this.blurHash,
    this.sourceUrl,
    this.otherLanguageEditions,
    this.localImportPath,
  });

  factory Work.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> processingJson = json;
    bool isModified = false;

    if (processingJson['duration'] == null || processingJson['duration'] == 0) {
      if (processingJson['memo'] != null && processingJson['memo'] is Map) {
        final memo = processingJson['memo'] as Map;
        if (memo['totalDuration'] != null && memo['totalDuration'] is num) {
          if (!isModified) {
            processingJson = Map<String, dynamic>.from(json);
            isModified = true;
          }
          processingJson['duration'] = (memo['totalDuration'] as num).toInt();
        }
      }
    }

    if (processingJson['has_subtitle'] == null) {
      final lyricStatus = processingJson['lyric_status'];
      if (lyricStatus != null &&
          lyricStatus is String &&
          lyricStatus.isNotEmpty) {
        if (!isModified) {
          processingJson = Map<String, dynamic>.from(json);
          isModified = true;
        }
        processingJson['has_subtitle'] = true;
      }
    }

    final localImportPath = json['local_import_path'] as String?;
    return _$WorkFromJson(processingJson).copyWith(
      localImportPath: localImportPath,
    );
  }

  Map<String, dynamic> toJson() {
    final map = _$WorkToJson(this);
    if (localImportPath != null) {
      map['local_import_path'] = localImportPath;
    }
    return map;
  }

  String getCoverImageUrl(String baseUrl, {String? token}) {
    String normalizedUrl = baseUrl;
    if (baseUrl.isNotEmpty &&
        !baseUrl.startsWith('http://') &&
        !baseUrl.startsWith('https://')) {
      normalizedUrl = 'https://$baseUrl';
    }

    if (token != null && token.isNotEmpty) {
      return '$normalizedUrl/api/cover/$id?token=$token';
    }
    return '$normalizedUrl/api/cover/$id';
  }

  String get circleTitle => name ?? '';

  /// 创建 Work 的副本，可选择性地覆盖某些字段
  Work copyWith({
    int? id,
    String? title,
    int? circleId,
    String? name,
    List<Va>? vas,
    List<Tag>? tags,
    String? age,
    String? release,
    int? dlCount,
    int? price,
    int? reviewCount,
    int? rateCount,
    double? rateAverage,
    bool? hasSubtitle,
    int? duration,
    String? progress,
    int? userRating,
    List<RatingDetail>? rateCountDetail,
    List<String>? images,
    String? description,
    List<AudioFile>? children,
    String? sourceUrl,
    List<OtherLanguageEdition>? otherLanguageEditions,
    String? localImportPath,
  }) {
    return Work(
      id: id ?? this.id,
      title: title ?? this.title,
      circleId: circleId ?? this.circleId,
      name: name ?? this.name,
      vas: vas ?? this.vas,
      tags: tags ?? this.tags,
      age: age ?? this.age,
      release: release ?? this.release,
      dlCount: dlCount ?? this.dlCount,
      price: price ?? this.price,
      reviewCount: reviewCount ?? this.reviewCount,
      rateCount: rateCount ?? this.rateCount,
      rateAverage: rateAverage ?? this.rateAverage,
      hasSubtitle: hasSubtitle ?? this.hasSubtitle,
      duration: duration ?? this.duration,
      progress: progress ?? this.progress,
      userRating: userRating ?? this.userRating,
      rateCountDetail: rateCountDetail ?? this.rateCountDetail,
      images: images ?? this.images,
      description: description ?? this.description,
      children: children ?? this.children,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      otherLanguageEditions:
          otherLanguageEditions ?? this.otherLanguageEditions,
      localImportPath: localImportPath ?? this.localImportPath,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        circleId,
        name,
        vas,
        tags,
        age,
        release,
        dlCount,
        price,
        reviewCount,
        rateCount,
        rateAverage,
        hasSubtitle,
        duration,
        progress,
        userRating,
        rateCountDetail,
        images,
        description,
        children,
        blurHash,
        sourceUrl,
        otherLanguageEditions,
        localImportPath,
      ];
}

@JsonSerializable()
class OtherLanguageEdition extends Equatable {
  final int id;
  final String lang;
  final String title;

  @JsonKey(name: 'source_id')
  final String sourceId;

  @JsonKey(name: 'is_original')
  final bool isOriginal;

  @JsonKey(name: 'source_type')
  final String sourceType;

  const OtherLanguageEdition({
    required this.id,
    required this.lang,
    required this.title,
    required this.sourceId,
    required this.isOriginal,
    required this.sourceType,
  });

  factory OtherLanguageEdition.fromJson(Map<String, dynamic> json) =>
      _$OtherLanguageEditionFromJson(json);

  Map<String, dynamic> toJson() => _$OtherLanguageEditionToJson(this);

  @override
  List<Object?> get props =>
      [id, lang, title, sourceId, isOriginal, sourceType];
}

@JsonSerializable()
class RatingDetail extends Equatable {
  @JsonKey(name: 'review_point')
  final int reviewPoint;

  final int count;
  final int ratio;

  const RatingDetail({
    required this.reviewPoint,
    required this.count,
    required this.ratio,
  });

  factory RatingDetail.fromJson(Map<String, dynamic> json) =>
      _$RatingDetailFromJson(json);

  Map<String, dynamic> toJson() => _$RatingDetailToJson(this);

  @override
  List<Object?> get props => [reviewPoint, count, ratio];
}

@JsonSerializable()
class Circle extends Equatable {
  final int id;

  @JsonKey(name: 'name')
  final String title;

  const Circle({required this.id, required this.title});

  factory Circle.fromJson(Map<String, dynamic> json) => _$CircleFromJson(json);

  Map<String, dynamic> toJson() => _$CircleToJson(this);

  @override
  List<Object?> get props => [id, title];
}

@JsonSerializable()
class Va extends Equatable {
  final String id;
  final String name;

  const Va({required this.id, required this.name});

  factory Va.fromJson(Map<String, dynamic> json) => _$VaFromJson(json);

  Map<String, dynamic> toJson() => _$VaToJson(this);

  @override
  List<Object?> get props => [id, name];
}

@JsonSerializable()
class Tag extends Equatable {
  final int id;
  final String name;
  final int? upvote;
  final int? downvote;

  @JsonKey(name: 'myVote')
  final int? myVote;

  @JsonKey(name: 'voteStatus')
  final int? voteStatus;

  const Tag({
    required this.id,
    required this.name,
    this.upvote,
    this.downvote,
    this.myVote,
    this.voteStatus,
  });

  /// 是否为用户添加的标签（非默认标签）
  bool get isUserAdded => voteStatus == 0;

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);

  Map<String, dynamic> toJson() => _$TagToJson(this);

  @override
  List<Object?> get props => [id, name, upvote, downvote, myVote, voteStatus];
}

@JsonSerializable()
class AudioFile extends Equatable {
  final String title;
  final String? type;
  final String? hash;
  final List<AudioFile>? children;

  @JsonKey(name: 'mediaDownloadUrl')
  final String? mediaDownloadUrl;

  final int? size;
  final double? duration;

  const AudioFile({
    required this.title,
    this.type,
    this.hash,
    this.children,
    this.mediaDownloadUrl,
    this.size,
    this.duration,
  });

  factory AudioFile.fromJson(Map<String, dynamic> json) =>
      _$AudioFileFromJson(json);

  Map<String, dynamic> toJson() => _$AudioFileToJson(this);

  bool get isFolder => type == 'folder';

  bool get isAudio {
    if (type == 'audio') return true;
    final lowerTitle = title.toLowerCase();
    return lowerTitle.endsWith('.mp3') ||
        lowerTitle.endsWith('.wav') ||
        lowerTitle.endsWith('.flac') ||
        lowerTitle.endsWith('.m4a') ||
        lowerTitle.endsWith('.aac') ||
        lowerTitle.endsWith('.ogg') ||
        lowerTitle.endsWith('.wma') ||
        lowerTitle.endsWith('.opus') ||
        lowerTitle.endsWith('.m4b');
  }

  bool get isText {
    if (type == 'text') return true;
    final lowerTitle = title.toLowerCase();
    return lowerTitle.endsWith('.txt') ||
        lowerTitle.endsWith('.vtt') ||
        lowerTitle.endsWith('.srt') ||
        lowerTitle.endsWith('.lrc') ||
        lowerTitle.endsWith('.md') ||
        lowerTitle.endsWith('.log') ||
        lowerTitle.endsWith('.json') ||
        lowerTitle.endsWith('.xml');
  }

  bool get isImage {
    if (type == 'image') return true;
    final lowerTitle = title.toLowerCase();
    return lowerTitle.endsWith('.jpg') ||
        lowerTitle.endsWith('.jpeg') ||
        lowerTitle.endsWith('.png') ||
        lowerTitle.endsWith('.gif') ||
        lowerTitle.endsWith('.bmp') ||
        lowerTitle.endsWith('.webp');
  }

  @override
  List<Object?> get props =>
      [title, type, hash, children, mediaDownloadUrl, size, duration];
}