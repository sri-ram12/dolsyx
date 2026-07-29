class Message {
  final String id;
  final String content;
  final String senderId;
  final String conversationId;
  final String? parentMessageId;
  final bool isEdited;
  final bool isDeleted;
  final bool isForwarded;
  final String? mediaUrl;
  final String? mediaType;
  final List<dynamic>? receipts;
  List<dynamic>? reactions;
  final DateTime createdAt;

  final bool isPending;

  final Map<String, dynamic>? parentMessage;

  Message({
    required this.id,
    required this.content,
    required this.senderId,
    required this.conversationId,
    this.parentMessageId,
    this.isEdited = false,
    this.isDeleted = false,
    this.isForwarded = false,
    this.mediaUrl,
    this.mediaType,
    this.receipts,
    this.reactions,
    required this.createdAt,
    this.parentMessage,
    this.isPending = false,
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
      isForwarded: json['isForwarded'] ?? false,
      mediaUrl: json['mediaUrl'],
      mediaType: json['mediaType'],
      receipts: json['receipts'],
      reactions: json['reactions'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      parentMessage: json['parentMessage'],
      isPending: json['isPending'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'senderId': senderId,
      'conversationId': conversationId,
      'parentMessageId': parentMessageId,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'isForwarded': isForwarded,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'receipts': receipts,
      'reactions': reactions,
      'createdAt': createdAt.toIso8601String(),
      'parentMessage': parentMessage,
      'isPending': isPending,
    };
  }
}
