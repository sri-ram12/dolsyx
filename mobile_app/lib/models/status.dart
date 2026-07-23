class StatusModel {
  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType;
  final String content;
  final DateTime expiresAt;
  final DateTime createdAt;
  final Map<String, dynamic>? user;
  final List<dynamic>? viewers;

  StatusModel({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    required this.content,
    required this.expiresAt,
    required this.createdAt,
    this.user,
    this.viewers,
  });

  factory StatusModel.fromJson(Map<String, dynamic> json) {
    return StatusModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      mediaUrl: json['mediaUrl'] ?? '',
      mediaType: json['mediaType'] ?? 'IMAGE',
      content: json['content'] ?? '',
      expiresAt: DateTime.parse(json['expiresAt'] ?? DateTime.now().toIso8601String()),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      user: json['user'],
      viewers: json['viewers'],
    );
  }
}
