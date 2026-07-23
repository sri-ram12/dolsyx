class Message {
  final String id;
  final String content;
  final String senderId;
  final String conversationId;
  final String? parentMessageId;
  final bool isEdited;
  final bool isDeleted;
  final String? mediaUrl;
  final String? mediaType;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.content,
    required this.senderId,
    required this.conversationId,
    this.parentMessageId,
    this.isEdited = false,
    this.isDeleted = false,
    this.mediaUrl,
    this.mediaType,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      content: json['content'] ?? '',
      senderId: json['senderId'],
      conversationId: json['conversationId'],
      parentMessageId: json['parentMessageId'],
      isEdited: json['isEdited'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      mediaUrl: json['mediaUrl'],
      mediaType: json['mediaType'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}
