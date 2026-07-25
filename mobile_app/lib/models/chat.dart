class Chat {
  String id;
  String? name;
  bool isGroup;
  String? avatarUrl;
  List<dynamic>? participants;
  Map<String, dynamic>? lastMessage;
  int unreadCount;
  DateTime? updatedAt;
  bool isArchived;

  Chat({
    required this.id,
    this.name,
    this.isGroup = false,
    this.avatarUrl,
    this.participants,
    this.lastMessage,
    this.unreadCount = 0,
    this.updatedAt,
    this.isArchived = false,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      name: json['name'],
      isGroup: json['isGroup'] ?? false,
      avatarUrl: json['avatarUrl'],
      participants: json['participants'],
      lastMessage: json['lastMessage'],
      unreadCount: json['unreadCount'] ?? 0,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      isArchived: json['isArchived'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isGroup': isGroup,
      'avatarUrl': avatarUrl,
      'participants': participants,
      'lastMessage': lastMessage,
      'unreadCount': unreadCount,
      'updatedAt': updatedAt?.toIso8601String(),
      'isArchived': isArchived,
    };
  }
}
