class StatusModel {
  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType;
  final String caption;
  final String? bgColor;
  final DateTime expiresAt;
  final DateTime createdAt;
  final bool isViewed;
  final List<dynamic>? views;

  StatusModel({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    required this.caption,
    this.bgColor,
    required this.expiresAt,
    required this.createdAt,
    this.isViewed = false,
    this.views,
  });

  /// Fraction [0.0–1.0] of the 24-hour lifetime that has elapsed.
  /// Used to render the countdown arc ring on the status list tile.
  double get timeElapsedFraction {
    final totalDuration = const Duration(hours: 24);
    final elapsed = DateTime.now().difference(createdAt);
    final fraction = elapsed.inMilliseconds / totalDuration.inMilliseconds;
    return fraction.clamp(0.0, 1.0);
  }

  /// Human-readable time remaining string e.g. "18h left", "45m left".
  String get timeRemainingLabel {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inHours >= 1) return '${remaining.inHours}h left';
    return '${remaining.inMinutes}m left';
  }

  StatusModel copyWith({bool? isViewed, List<dynamic>? views}) {
    return StatusModel(
      id: id,
      userId: userId,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      caption: caption,
      bgColor: bgColor,
      expiresAt: expiresAt,
      createdAt: createdAt,
      isViewed: isViewed ?? this.isViewed,
      views: views ?? this.views,
    );
  }

  factory StatusModel.fromJson(Map<String, dynamic> json) {
    String extractUserId() {
      if (json['userId'] != null && json['userId'].toString().isNotEmpty) {
        return json['userId'].toString();
      }
      if (json['user'] is Map) {
        final u = json['user'];
        return (u['id'] ?? u['_id'] ?? '').toString();
      }
      if (json['user'] != null) {
        return json['user'].toString();
      }
      return '';
    }

    return StatusModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      userId: extractUserId(),
      mediaUrl: json['mediaUrl'] ?? '',
      mediaType: json['mediaType'] ?? 'TEXT',
      caption: json['caption'] ?? json['content'] ?? '',
      bgColor: json['bgColor'],
      expiresAt: json['expiresAt'] != null
          ? (DateTime.tryParse(json['expiresAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
      isViewed: json['isViewed'] ?? false,
      views: json['views'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'mediaUrl': mediaUrl,
        'mediaType': mediaType,
        'caption': caption,
        'bgColor': bgColor,
        'expiresAt': expiresAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'isViewed': isViewed,
        'views': views,
      };
}

class UserStatusGroup {
  final Map<String, dynamic> user;
  final List<StatusModel> statuses;
  final bool hasUnread;
  final bool isMuted;

  UserStatusGroup({
    required this.user,
    required this.statuses,
    this.hasUnread = false,
    this.isMuted = false,
  });

  UserStatusGroup copyWith({
    List<StatusModel>? statuses,
    bool? hasUnread,
    bool? isMuted,
  }) {
    return UserStatusGroup(
      user: user,
      statuses: statuses ?? this.statuses,
      hasUnread: hasUnread ?? this.hasUnread,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  factory UserStatusGroup.fromJson(Map<String, dynamic> json) {
    return UserStatusGroup(
      user: json['user'] ?? {},
      statuses: (json['statuses'] as List<dynamic>?)
              ?.map((s) => StatusModel.fromJson(s))
              .toList() ??
          [],
      hasUnread: json['hasUnread'] ?? false,
      isMuted: json['isMuted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user,
        'statuses': statuses.map((s) => s.toJson()).toList(),
        'hasUnread': hasUnread,
        'isMuted': isMuted,
      };
}
