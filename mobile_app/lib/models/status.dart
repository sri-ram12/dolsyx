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
      expiresAt: json['expiresAt'] != null ? (DateTime.tryParse(json['expiresAt'].toString()) ?? DateTime.now()) : DateTime.now(),
      createdAt: json['createdAt'] != null ? (DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()) : DateTime.now(),
      isViewed: json['isViewed'] ?? false,
      views: json['views'],
    );
  }
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
}
