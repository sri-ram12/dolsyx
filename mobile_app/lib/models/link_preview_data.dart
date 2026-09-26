import 'dart:convert';

/// OpenGraph & Rich Link Preview metadata model (Phase 10)
class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String domain;

  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    required this.domain,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'description': description,
    'imageUrl': imageUrl,
    'domain': domain,
  };

  factory LinkPreviewData.fromJson(Map<String, dynamic> json) {
    return LinkPreviewData(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      domain: json['domain']?.toString() ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static LinkPreviewData? fromJsonString(String? str) {
    if (str == null || str.isEmpty) return null;
    try {
      final map = jsonDecode(str);
      if (map is Map<String, dynamic>) {
        return LinkPreviewData.fromJson(map);
      }
    } catch (_) {}
    return null;
  }
}
