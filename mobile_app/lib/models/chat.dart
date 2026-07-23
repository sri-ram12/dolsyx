class Chat {
  final String id;
  final String? name;
  final bool isGroup;
  final String? avatarUrl;
  final List<dynamic>? participants;
  final List<dynamic>? messages;

  Chat({
    required this.id,
    this.name,
    this.isGroup = false,
    this.avatarUrl,
    this.participants,
    this.messages,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      name: json['name'],
      isGroup: json['isGroup'] ?? false,
      avatarUrl: json['avatarUrl'],
      participants: json['participants'],
      messages: json['messages'],
    );
  }
}
