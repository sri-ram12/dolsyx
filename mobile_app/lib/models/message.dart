import 'dart:convert';
import '../utils/media_size_helper.dart';

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
  final bool isViewOnce;
  bool isViewed;
  final double? latitude;
  final double? longitude;
  final String? locationTitle;
  final bool isLiveLocation;
  final DateTime? liveExpiresAt;
  final bool isLiveEnded;
  final List<dynamic>? receipts;
  List<dynamic>? reactions;
  final DateTime createdAt;

  final bool isPending;
  final Map<String, dynamic>? parentMessage;
  final Map<String, dynamic>? sender;
  final bool isPinned;
  final String? mediaKey;
  final String? nonce;
  final bool isE2EEMedia;
  final int? fileSize;
  final String? fileName;

  String get formattedFileSize => MediaSizeHelper.formatBytes(fileSize);

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
    this.isViewOnce = false,
    this.isViewed = false,
    this.latitude,
    this.longitude,
    this.locationTitle,
    this.isLiveLocation = false,
    this.liveExpiresAt,
    this.isLiveEnded = false,
    this.receipts,
    this.reactions,
    required this.createdAt,
    this.parentMessage,
    this.sender,
    this.isPending = false,
    this.isPinned = false,
    this.mediaKey,
    this.nonce,
    this.isE2EEMedia = false,
    this.fileSize,
    this.fileName,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    String contentStr = json['content'] ?? '';
    String? mediaUrl = json['mediaUrl'];
    String? mediaType = json['mediaType'];
    bool isViewOnce = json['isViewOnce'] ?? false;
    double? latitude = json['latitude'] != null ? (json['latitude'] as num).toDouble() : null;
    double? longitude = json['longitude'] != null ? (json['longitude'] as num).toDouble() : null;
    String? locationTitle = json['locationTitle'];
    bool isLiveLocation = json['isLiveLocation'] ?? false;
    String? mediaKey = json['mediaKey'];
    String? nonce = json['nonce'];
    bool isE2EEMedia = json['isE2EEMedia'] ?? false;
    int? fileSize = (json['fileSize'] as num?)?.toInt() ?? (json['size'] as num?)?.toInt();
    String? fileName = json['fileName'];

    // Smart JSON content parsing for E2EE media, Poll, or Location payloads
    if (contentStr.startsWith('{') && contentStr.endsWith('}')) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(contentStr);
        if (decoded['question'] != null || decoded['mediaType'] == 'POLL' || json['mediaType'] == 'POLL') {
          mediaType = 'POLL';
        } else if (decoded['encryptedMedia'] == true || decoded['mediaUrl'] != null) {
          mediaUrl = decoded['mediaUrl'] ?? mediaUrl;
          mediaType = decoded['mediaType'] ?? mediaType;
          isViewOnce = decoded['isViewOnce'] ?? isViewOnce;
          mediaKey = decoded['mediaKey'] ?? mediaKey;
          nonce = decoded['nonce'] ?? nonce;
          isE2EEMedia = (mediaKey != null && nonce != null) || (json['isE2EEMedia'] == true);
          contentStr = decoded['caption'] ?? '';
          fileSize = (decoded['fileSize'] as num?)?.toInt() ?? (decoded['size'] as num?)?.toInt() ?? fileSize;
          fileName = decoded['fileName'] ?? fileName;
        } else if (decoded['mediaType'] == 'LOCATION' || decoded['latitude'] != null || json['mediaType'] == 'LOCATION') {
          mediaType = 'LOCATION';
          latitude = (decoded['latitude'] as num?)?.toDouble() ?? 12.9716;
          longitude = (decoded['longitude'] as num?)?.toDouble() ?? 77.5946;
          locationTitle = decoded['locationTitle'] ?? 'Current Location';
          isLiveLocation = decoded['isLiveLocation'] ?? false;
          contentStr = '';
        }
      } catch (_) {}
    } else if (json['mediaType'] == 'POLL') {
      mediaType = 'POLL';
    } else if (json['mediaType'] == 'LOCATION') {
      mediaType = 'LOCATION';
    }

    if (fileSize != null && mediaUrl != null) {
      MediaSizeHelper.cacheSize(mediaUrl, fileSize);
    }

    return Message(
      id: json['id'] ?? json['_id'] ?? '',
      content: contentStr,
      senderId: json['senderId'] ?? (json['sender'] != null ? (json['sender']['id'] ?? json['sender']['_id']) : '') ?? '',
      conversationId: json['conversationId'] ?? json['chatId'] ?? '',
      parentMessageId: json['parentMessageId'],
      isEdited: json['isEdited'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      isForwarded: json['isForwarded'] ?? false,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      isViewOnce: isViewOnce,
      isViewed: json['isViewed'] ?? false,
      latitude: latitude,
      longitude: longitude,
      locationTitle: locationTitle,
      isLiveLocation: isLiveLocation,
      liveExpiresAt: json['liveExpiresAt'] != null ? DateTime.tryParse(json['liveExpiresAt']) : null,
      isLiveEnded: json['isLiveEnded'] ?? false,
      receipts: json['receipts'],
      reactions: json['reactions'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      parentMessage: json['parentMessage'],
      sender: json['sender'],
      isPending: json['isPending'] ?? false,
      isPinned: json['isPinned'] ?? false,
      mediaKey: mediaKey,
      nonce: nonce,
      isE2EEMedia: isE2EEMedia,
      fileSize: fileSize,
      fileName: fileName,
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
      'fileSize': fileSize,
      'fileName': fileName,
      'isViewOnce': isViewOnce,
      'isViewed': isViewed,
      'latitude': latitude,
      'longitude': longitude,
      'locationTitle': locationTitle,
      'isLiveLocation': isLiveLocation,
      'liveExpiresAt': liveExpiresAt?.toIso8601String(),
      'isLiveEnded': isLiveEnded,
      'receipts': receipts,
      'reactions': reactions,
      'createdAt': createdAt.toIso8601String(),
      'parentMessage': parentMessage,
      'sender': sender,
      'isPending': isPending,
      'isPinned': isPinned,
      'mediaKey': mediaKey,
      'nonce': nonce,
      'isE2EEMedia': isE2EEMedia,
    };
  }

  Message copyWith({
    String? id,
    String? content,
    String? senderId,
    String? conversationId,
    String? parentMessageId,
    bool? isEdited,
    bool? isDeleted,
    bool? isForwarded,
    String? mediaUrl,
    String? mediaType,
    bool? isViewOnce,
    bool? isViewed,
    double? latitude,
    double? longitude,
    String? locationTitle,
    bool? isLiveLocation,
    DateTime? liveExpiresAt,
    bool? isLiveEnded,
    List<dynamic>? receipts,
    List<dynamic>? reactions,
    DateTime? createdAt,
    Map<String, dynamic>? parentMessage,
    Map<String, dynamic>? sender,
    bool? isPending,
    bool? isPinned,
    String? mediaKey,
    String? nonce,
    bool? isE2EEMedia,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      conversationId: conversationId ?? this.conversationId,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      isForwarded: isForwarded ?? this.isForwarded,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      isViewOnce: isViewOnce ?? this.isViewOnce,
      isViewed: isViewed ?? this.isViewed,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationTitle: locationTitle ?? this.locationTitle,
      isLiveLocation: isLiveLocation ?? this.isLiveLocation,
      liveExpiresAt: liveExpiresAt ?? this.liveExpiresAt,
      isLiveEnded: isLiveEnded ?? this.isLiveEnded,
      receipts: receipts ?? this.receipts,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt ?? this.createdAt,
      parentMessage: parentMessage ?? this.parentMessage,
      sender: sender ?? this.sender,
      isPending: isPending ?? this.isPending,
      isPinned: isPinned ?? this.isPinned,
      mediaKey: mediaKey ?? this.mediaKey,
      nonce: nonce ?? this.nonce,
      isE2EEMedia: isE2EEMedia ?? this.isE2EEMedia,
    );
  }
}
