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
    return StatusModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      mediaUrl: json['mediaUrl'] ?? '',
      mediaType: json['mediaType'] ?? 'TEXT',
      caption: json['caption'] ?? json['content'] ?? '',
      bgColor: json['bgColor'],
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : DateTime.now(),
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
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
