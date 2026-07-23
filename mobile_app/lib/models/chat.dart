class Chat {
  final String id;
  final String? name;
  final bool isGroup;
  final String? avatarUrl;
  final List<dynamic>? participants;
  final Map<String, dynamic>? lastMessage;
  final int unreadCount;

  Chat({
    required this.id,
    this.name,
    this.isGroup = false,
    this.avatarUrl,
    this.participants,
    this.lastMessage,
    this.unreadCount = 0,
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
    );
  }
}
