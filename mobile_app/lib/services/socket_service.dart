import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'sound_service.dart';
import '../main.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/e2ee/crypto_service.dart';
import '../utils/e2ee/e2ee_api.dart';
import 'local_database_service.dart';
import '../models/message.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;
  final CryptoService _crypto = CryptoService();
  
  // Stream to broadcast profile updates globally
  final StreamController<Map<String, dynamic>> profileUpdates = StreamController<Map<String, dynamic>>.broadcast();
  String get _socketUrl {
    final base = ApiService.baseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }
  
  bool get isConnected => socket?.connected ?? false;

  final _messageStreamController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get onMessageStream => _messageStreamController.stream;

  // Dedicated stream for decrypted E2EE messages
  final _encryptedMessageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onEncryptedMessageStream => _encryptedMessageController.stream;

  final _statusStreamController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get onStatusStream => _statusStreamController.stream;

  final Set<String> onlineUserIds = {};
  final StreamController<Set<String>> onlineUsersStream = StreamController<Set<String>>.broadcast();
  final StreamController<Map<String, dynamic>> typingUpdates = StreamController<Map<String, dynamic>>.broadcast();
  final Set<String> _recentMessageIds = {};

  String? _currentUserId;
  String? _activeConversationId;

  Future<void> connect(String userId) async {
    _currentUserId = userId;
    final token = await ApiService().getToken();
    if (token == null) return;

    if (socket != null && socket!.connected) return;

    if (socket != null) {
      socket?.io.options?['auth'] = {'token': token};
      socket!.connect();
      return;
    }

    socket = IO.io(_socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 999999,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'auth': {'token': token},
    });

    socket?.connect();

    void onConnectedHandler(_) {
      print('✅ Socket Connected/Reconnected');
      socket?.emit('register', userId);
      if (_activeConversationId != null && _activeConversationId!.isNotEmpty) {
        socket?.emit('join_conversation', _activeConversationId);
      }
      _processOfflineQueue();
    }

    socket?.onConnect(onConnectedHandler);
    socket?.onReconnect(onConnectedHandler);

    socket?.on('new_message', (data) async {
      if (data == null || data is! Map) return;

      final rawMsg = data['message'] ?? data;
      final msgId = (rawMsg is Map) ? (rawMsg['id'] ?? rawMsg['_id'])?.toString() : null;
      if (msgId != null && msgId.isNotEmpty) {
        if (_recentMessageIds.contains(msgId)) return;
        if (_recentMessageIds.length > 250) {
          _recentMessageIds.remove(_recentMessageIds.first);
        }
        _recentMessageIds.add(msgId);
      }

      final rawSenderId = (rawMsg is Map) ? (rawMsg['senderId'] ?? rawMsg['sender']?['id'])?.toString() : null;
      if (rawSenderId != null && rawSenderId != _currentUserId) {
        SoundService().playNotificationSound();
        // WhatsApp auto-acknowledgment: Tell sender device the message was delivered to this device
        final convId = (data['conversationId'] ?? (rawMsg is Map ? rawMsg['conversationId'] : null))?.toString();
        if (convId != null && msgId != null) {
          socket?.emit('mark_delivered', {
            'conversationId': convId,
            'messageIds': [msgId],
          });
        }
      }
      
      try {
        if (rawMsg is Map) {
          final message = Map<String, dynamic>.from(rawMsg);
          final conversationId = (data['conversationId'] ?? message['conversationId'] ?? '').toString();
          final senderId = (message['senderId'] ?? message['sender']?['id'] ?? '').toString();
          final content = (message['content'] ?? '').toString();

            if (content.isNotEmpty && senderId.isNotEmpty) {
              final decrypted = await _crypto.decryptIncomingContent(
                content: content,
                senderUserId: senderId,
                conversationId: conversationId,
              );
              message['content'] = decrypted;

              // Check if decrypted content is an encrypted media descriptor
              try {
                if (decrypted.startsWith('{') && decrypted.endsWith('}')) {
                  final decodedMedia = jsonDecode(decrypted);
                  if (decodedMedia is Map<String, dynamic> && decodedMedia['encryptedMedia'] == true) {
                    message['content'] = decodedMedia['caption'] ?? '';
                    message['mediaUrl'] = decodedMedia['mediaUrl'];
                    message['mediaType'] = decodedMedia['mediaType'];
                    message['mediaKey'] = decodedMedia['mediaKey'];
                    message['nonce'] = decodedMedia['nonce'];
                    message['isE2EEMedia'] = true;
                  }
                }
              } catch (_) {}

              data = {
                ...Map<String, dynamic>.from(data),
                'message': message,
              };
            }
          }

          // WhatsApp Instant Local SQLite Persistence (sub-millisecond indexed writes)
          try {
            final rawMessageMap = (data is Map) ? (data['message'] ?? data) : null;
            if (rawMessageMap != null && rawMessageMap is Map) {
              final msgObj = Message.fromJson(Map<String, dynamic>.from(rawMessageMap));
              LocalDatabaseService().saveSingleMessage(msgObj);
              LocalDatabaseService().updateConversationLastMessage(
                msgObj.conversationId,
                msgObj.toJson(),
                unreadIncrement: (rawSenderId != null && rawSenderId != _currentUserId) ? 1 : null,
              );
            }
          } catch (_) {}
        } catch (e) {
          print('Error processing incoming new_message: $e');
        }

      _messageStreamController.add(data);
      
      try {
        final message = (data is Map) ? (data['message'] ?? data) : null;
        if (message != null && message is Map) {
          final senderId = message['senderId'] ?? message['sender']?['id'];
          
          // Don't show popups for outgoing messages
          if (senderId != null && senderId == _currentUserId) return;

          final senderName = message['sender']?['username'] ?? 'New Message';
          final content = message['content'] ?? (message['mediaType'] != null ? 'Shared ${message['mediaType']}' : 'New message');
          if (content.toString().isNotEmpty) {
            flutterLocalNotificationsPlugin.show(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: senderName.toString(),
              body: content.toString(),
              payload: jsonEncode({
                'conversationId': message['conversationId'],
                'senderId': senderId,
              }),
              notificationDetails: NotificationDetails(
                android: AndroidNotificationDetails(
                  channel.id,
                  channel.name,
                  channelDescription: channel.description,
                  icon: '@mipmap/ic_launcher',
                  priority: Priority.max,
                  importance: Importance.max,
                  sound: const RawResourceAndroidNotificationSound('dolsyx_message'),
                  playSound: true,
                  actions: <AndroidNotificationAction>[
                    const AndroidNotificationAction(
                      'reply_msg',
                      'Reply',
                      inputs: <AndroidNotificationActionInput>[
                        AndroidNotificationActionInput(label: 'Type a message...'),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }
        }
      } catch (_) {}
    });

    // Listen for real-time E2EE encrypted messages and auto-decrypt them
    socket?.on('receive_encrypted_message', (data) async {
      try {
        if (data == null || data is! Map) return;
        final rawMsg = data['message'];
        if (rawMsg == null || rawMsg is! Map) return;

        final message = Map<String, dynamic>.from(rawMsg);
        final conversationId = (data['conversationId'] ?? '').toString();
        final content = (message['content'] ?? '').toString();
        final senderUserId = (message['senderId'] ?? message['sender']?['id'] ?? message['sender']?['_id'] ?? '').toString();
        
        if (content.isEmpty || senderUserId.isEmpty) return;

        final payloadJson = jsonDecode(content) as Map<String, dynamic>;
        final payload = MessagePayload.fromJson(payloadJson);
        final plaintext = await _crypto.decryptMessage(
          senderUserId: senderUserId,
          payload: payload,
        );
        SoundService().playNotificationSound();

        Map<String, dynamic> updatedMsg = {
          ...message,
          'content': plaintext,
        };

        try {
          final decodedJson = jsonDecode(plaintext);
          if (decodedJson is Map<String, dynamic> && decodedJson['encryptedMedia'] == true) {
            updatedMsg['content'] = '';
            updatedMsg['mediaUrl'] = decodedJson['mediaUrl'];
            updatedMsg['mediaType'] = decodedJson['mediaType'];
            updatedMsg['mediaKey'] = decodedJson['mediaKey'];
            updatedMsg['nonce'] = decodedJson['nonce'];
            updatedMsg['isE2EEMedia'] = true;
          }
        } catch (_) {}

        _encryptedMessageController.add({
          'conversationId': conversationId,
          'message': updatedMsg,
        });
        
        // Don't show popups for outgoing messages
        if (senderUserId == _currentUserId) return;

        flutterLocalNotificationsPlugin.show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'Encrypted Message',
          body: plaintext,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: '@mipmap/ic_launcher',
              priority: Priority.max,
              importance: Importance.max,
            ),
          ),
        );
      } catch (e) {
        print('⚠️ Failed to decrypt incoming message: $e');
      }
    });

    socket?.on('messages_read', (data) {
      _messageStreamController.add({'type': 'read', 'data': data});
    });

    socket?.on('new_status', (data) => _statusStreamController.add({'type': 'new_status', 'data': data}));
    socket?.on('status_viewed', (data) => _statusStreamController.add({'type': 'status_viewed', 'data': data}));
    socket?.on('status_deleted', (data) => _statusStreamController.add({'type': 'status_deleted', 'data': data}));

    socket?.on('profile_updated', (data) {
      if (data['user'] != null) {
        profileUpdates.add(data['user']);
      }
    });

    socket?.on('online_users_list', (data) {
      if (data is List) {
        onlineUserIds.clear();
        onlineUserIds.addAll(data.map((e) => e.toString()));
        onlineUsersStream.add(onlineUserIds);
      }
    });

    socket?.on('user_status_change', (data) {
      if (data['userId'] != null && data['status'] != null) {
        if (data['status'] == 'online') {
          onlineUserIds.add(data['userId'].toString());
        } else {
          onlineUserIds.remove(data['userId'].toString());
        }
        onlineUsersStream.add(onlineUserIds);
      }
    });

    socket?.on('user_typing', (data) {
      typingUpdates.add(data);
    });

    // Global WhatsApp ACK handler: transitions pending messages to SENT in local SQLite
    socket?.on('message_sent', (data) async {
      if (data == null || data is! Map) return;
      final tempId = data['tempId']?.toString();
      final messageId = data['messageId']?.toString();
      if (tempId != null && messageId != null) {
        await LocalDatabaseService().confirmPendingMessage(
          tempId: tempId,
          confirmedId: messageId,
        );
      }
    });

    // Global WhatsApp Delivery receipt handler: transitions messages to DELIVERED in local SQLite
    socket?.on('messages_delivered', (data) async {
      if (data == null || data is! Map) return;
      final convId = data['conversationId']?.toString();
      final userId = data['userId']?.toString();
      final messageIds = data['messageIds'] as List<dynamic>?;
      if (convId != null && userId != null) {
        await LocalDatabaseService().markMessagesDeliveredLocally(
          conversationId: convId,
          userId: userId,
          messageIds: messageIds,
        );
      }
    });

    // Global WhatsApp Read receipt handler: transitions messages to READ in local SQLite
    socket?.on('messages_read', (data) async {
      if (data == null || data is! Map) return;
      final convId = data['conversationId']?.toString();
      final userId = data['userId']?.toString();
      if (convId != null && userId != null) {
        await LocalDatabaseService().markMessagesReadLocally(
          conversationId: convId,
          userId: userId,
        );
      }
    });

    socket?.onDisconnect((_) {
      print('❌ Socket Disconnected');
    });

    socket?.onConnectError((err) {
      print('⚠️ Socket Connection Error: $err');
    });
  }

  void joinConversation(String conversationId) {
    _activeConversationId = conversationId;
    if (socket != null && socket!.connected) {
      socket!.emit('join_conversation', conversationId);
    }
  }

  void leaveConversation(String conversationId) {
    if (_activeConversationId == conversationId) {
      _activeConversationId = null;
    }
    if (socket != null && socket!.connected) {
      socket!.emit('leave_conversation', conversationId);
    }
  }

  Future<void> _processOfflineQueue() async {
    try {
      // 1. Drain pending outbox messages from WhatsApp-grade SQLite engine
      final pendingMessages = await LocalDatabaseService().getPendingMessages();
      for (final msg in pendingMessages) {
        if (socket != null && socket!.connected) {
          sendMessage(
            msg.conversationId,
            msg.content,
            mediaUrl: msg.mediaUrl,
            mediaType: msg.mediaType,
            parentMessageId: msg.parentMessageId,
            isForwarded: msg.isForwarded,
            isViewOnce: msg.isViewOnce,
            latitude: msg.latitude,
            longitude: msg.longitude,
            locationTitle: msg.locationTitle,
            isLiveLocation: msg.isLiveLocation,
            tempId: msg.id,
          );
        }
      }

      // 2. Legacy SharedPreferences offline queue migration fallback
      final prefs = await SharedPreferences.getInstance();
      final queueStr = prefs.getString('offline_message_queue');
      if (queueStr != null && queueStr.isNotEmpty) {
        final List<dynamic> queue = jsonDecode(queueStr);
        for (var msg in queue) {
          if (socket != null && socket!.connected) {
            socket!.emit('send_message', msg);
          }
        }
        await prefs.remove('offline_message_queue');
      }
    } catch (e) {
      print('Error processing offline queue: $e');
    }
  }

  /// Sends an E2EE encrypted message to [recipientEmail] in [conversationId].
  /// Fetches the recipient's public key bundle, performs X3DH, and POSTs to the backend.
  Future<void> sendEncryptedMessage({
    required String conversationId,
    required String recipientEmail,
    required String plaintext,
    required String token,
    required String myUserId,
    String? parentMessageId,
  }) async {
    try {
      // Fetch recipient's public key bundle
      final recipientBundle = await E2EEApi.fetchKeys(recipientEmail, token);

      // Store sender identity key so we can decrypt future messages from them
      final List<dynamic> devices = (recipientBundle['devices'] as List<dynamic>?) ?? [];
      final recipientUserId = (recipientBundle['userId'] ?? recipientBundle['id'] ?? recipientBundle['_id'] ?? '').toString();

      if (devices.isNotEmpty && recipientUserId.isNotEmpty) {
        final identityKey = (devices.first['identityKeyPublic'] ?? '').toString();
        if (identityKey.isNotEmpty) {
          await _crypto.storeSenderIdentityKey(recipientUserId, identityKey);
        }
      }

      // Encrypt the message
      final messagePayload = await _crypto.encryptMessage(
        recipientKeyBundle: recipientBundle,
        plaintext: plaintext,
      );

      // Build recipient list and send to server
      final recipients = devices.map((device) => {
        'recipientDeviceId': device['id'] ?? device['_id'],
        'recipientUserId': recipientUserId,
        'type': messagePayload.type,
        'ciphertext': jsonEncode(messagePayload.toJson()),
      }).toList();

      await E2EEApi.sendEncryptedMessage({
        'senderDeviceId': 1,
        'conversationId': conversationId,
        'recipients': recipients,
        if (parentMessageId != null) 'parentMessageId': parentMessageId,
      }, token);
    } catch (e) {
      print('⚠️ E2EE encrypted message failed ($e). Falling back to standard socket delivery...');
      String? extractedType;
      try {
        if (plaintext.startsWith('{') && plaintext.endsWith('}')) {
          final decoded = jsonDecode(plaintext);
          extractedType = decoded['mediaType'];
        }
      } catch (_) {}
      sendMessage(conversationId, plaintext, mediaType: extractedType, parentMessageId: parentMessageId);
    }
  }
  /// Sends an E2EE encrypted message to all members in a Group Chat.
  /// Encrypts individual payloads for each member's devices using Signal X3DH + Double Ratchet.
  Future<void> sendEncryptedGroupMessage({
    required String conversationId,
    required List<String> memberEmails,
    required String plaintext,
    required String token,
    required String myUserId,
    String? parentMessageId,
  }) async {
    try {
      final List<Map<String, dynamic>> allRecipients = [];

      for (final email in memberEmails) {
        if (email.isEmpty) continue;
        try {
          final recipientBundle = await E2EEApi.fetchKeys(email, token);
          final List<dynamic> devices = (recipientBundle['devices'] as List<dynamic>?) ?? [];
          final recipientUserId = (recipientBundle['userId'] ?? recipientBundle['id'] ?? recipientBundle['_id'] ?? '').toString();

          if (recipientUserId == myUserId) continue; // Skip self

          if (devices.isNotEmpty && recipientUserId.isNotEmpty) {
            final identityKey = (devices.first['identityKeyPublic'] ?? '').toString();
            if (identityKey.isNotEmpty) {
              await _crypto.storeSenderIdentityKey(recipientUserId, identityKey);
            }
          }

          final messagePayload = await _crypto.encryptMessage(
            recipientKeyBundle: recipientBundle,
            plaintext: plaintext,
          );

          for (final device in devices) {
            allRecipients.add({
              'recipientDeviceId': device['id'] ?? device['_id'],
              'recipientUserId': recipientUserId,
              'type': messagePayload.type,
              'ciphertext': jsonEncode(messagePayload.toJson()),
            });
          }
        } catch (memberErr) {
          print('Group member E2EE key fetch failed for $email: $memberErr');
        }
      }

      if (allRecipients.isNotEmpty) {
        await E2EEApi.sendEncryptedMessage({
          'senderDeviceId': 1,
          'conversationId': conversationId,
          'recipients': allRecipients,
          if (parentMessageId != null) 'parentMessageId': parentMessageId,
        }, token);
      } else {
        sendMessage(conversationId, plaintext, parentMessageId: parentMessageId);
      }
    } catch (e) {
      print('⚠️ Group E2EE encrypted message failed ($e). Falling back to standard socket delivery...');
      sendMessage(conversationId, plaintext, parentMessageId: parentMessageId);
    }
  }

  void sendMessage(
    String conversationId,
    String content, {
    String? mediaUrl,
    String? mediaType,
    String? parentMessageId,
    bool isForwarded = false,
    bool isViewOnce = false,
    double? latitude,
    double? longitude,
    String? locationTitle,
    bool isLiveLocation = false,
    String? liveExpiresAt,
    String? tempId,
  }) async {
    print('Sending message. Socket connected: ${socket?.connected}');
    
    // 100% E2EE Zero-Knowledge: Pre-encrypt plaintext client-side before transmission
    String payloadContent = content;
    if (content.isNotEmpty && (!content.startsWith('{') || !content.contains('ciphertext'))) {
      try {
        payloadContent = await _crypto.encryptConversationPayload(
          conversationId: conversationId,
          plaintext: content,
        );
        _crypto.cachePlaintext(payloadContent, content);
      } catch (e) {
        print('⚠️ Failed to pre-encrypt outgoing content: $e');
      }
    }

    final msgData = {
      'conversationId': conversationId,
      'content': payloadContent,
      if (tempId != null) 'tempId': tempId,
      if (tempId != null) 'id': tempId,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
      if (parentMessageId != null) 'parentMessageId': parentMessageId,
      if (isForwarded) 'isForwarded': true,
      if (isViewOnce) 'isViewOnce': true,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationTitle != null) 'locationTitle': locationTitle,
      if (isLiveLocation) 'isLiveLocation': true,
      if (liveExpiresAt != null) 'liveExpiresAt': liveExpiresAt,
    };

    if (socket != null && socket!.connected) {
      socket!.emitWithAck('send_message', msgData, ack: (response) {
        if (response != null && response is Map) {
          final confirmedId = response['messageId']?.toString();
          final ackTempId = response['tempId']?.toString() ?? tempId;
          if (confirmedId != null && ackTempId != null) {
            LocalDatabaseService().confirmPendingMessage(tempId: ackTempId, confirmedId: confirmedId);
          }
        }
      });
      print('Message emitted to socket with ACK callback.');
    } else {
      print('Socket disconnected. Queuing message for offline sending.');
      try {
        final prefs = await SharedPreferences.getInstance();
        final queueStr = prefs.getString('offline_message_queue') ?? '[]';
        final List<dynamic> queue = jsonDecode(queueStr);
        queue.add(msgData);
        await prefs.setString('offline_message_queue', jsonEncode(queue));
      } catch (e) {
        print('Error queueing message: $e');
      }
    }
  }

  void onMessageReceived(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('new_message', callback);
    }
  }

  void offMessageReceived(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('new_message', callback);
    }
  }

  void onEncryptedMessageReceived(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('receive_encrypted_message', callback);
    }
  }

  void offEncryptedMessageReceived(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('receive_encrypted_message', callback);
    }
  }

  void onChatCleared(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('chat_cleared', callback);
    }
  }

  void offChatCleared(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('chat_cleared', callback);
    }
  }

  void onMessageDeleted(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('message_deleted', callback);
    }
  }

  void offMessageDeleted(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('message_deleted', callback);
    }
  }

  void onMessageEdited(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('message_edited', callback);
    }
  }

  void offMessageEdited(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('message_edited', callback);
    }
  }

  void emitTyping(String conversationId, bool isTyping) {
    if (socket != null && socket!.connected) {
      socket!.emit('typing', {
        'conversationId': conversationId,
        'isTyping': isTyping,
      });
    }
  }

  void onTypingChange(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('user_typing', callback);
    }
  }

  void offTypingChange(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('user_typing', callback);
    }
  }

  void onStatusChange(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('user_status_change', callback);
    }
  }

  void offStatusChange(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('user_status_change', callback);
    }
  }

  void onMessagesRead(Function(dynamic) callback) {
    if (socket != null) socket!.on('messages_read', callback);
  }

  void offMessagesRead(Function(dynamic) callback) {
    if (socket != null) socket!.off('messages_read', callback);
  }

  void onMessagesDelivered(Function(dynamic) callback) {
    if (socket != null) socket!.on('messages_delivered', callback);
  }

  void offMessagesDelivered(Function(dynamic) callback) {
    if (socket != null) socket!.off('messages_delivered', callback);
  }

  void onProfileUpdated(Function(dynamic) callback) {
    if (socket != null) socket!.on('profile_updated', callback);
  }

  void offProfileUpdated(Function(dynamic) callback) {
    if (socket != null) socket!.off('profile_updated', callback);
  }

  void onReactionAdded(Function(dynamic) callback) {
    if (socket != null) socket!.on('reaction_added', callback);
  }

  void offReactionAdded(Function(dynamic) callback) {
    if (socket != null) socket!.off('reaction_added', callback);
  }

  void onReactionRemoved(Function(dynamic) callback) {
    if (socket != null) socket!.on('reaction_removed', callback);
  }

  void offReactionRemoved(Function(dynamic) callback) {
    if (socket != null) socket!.off('reaction_removed', callback);
  }

  void onCallIncoming(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('call_incoming', callback);
    }
  }

  void offCallIncoming(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('call_incoming', callback);
    }
  }

  void onCallAnswered(Function(dynamic) callback) {
    if (socket != null) socket!.on('call_answered', callback);
  }

  void offCallAnswered(Function(dynamic) callback) {
    if (socket != null) socket!.off('call_answered', callback);
  }

  void onCallRejected(Function(dynamic) callback) {
    if (socket != null) socket!.on('call_rejected', callback);
  }

  void offCallRejected(Function(dynamic) callback) {
    if (socket != null) socket!.off('call_rejected', callback);
  }

  void onOffer(Function(dynamic) callback) {
    if (socket != null) socket!.on('offer', callback);
  }

  void offOffer(Function(dynamic) callback) {
    if (socket != null) socket!.off('offer', callback);
  }

  void onAnswer(Function(dynamic) callback) {
    if (socket != null) socket!.on('answer', callback);
  }

  void offAnswer(Function(dynamic) callback) {
    if (socket != null) socket!.off('answer', callback);
  }

  void onIceCandidate(Function(dynamic) callback) {
    if (socket != null) socket!.on('ice_candidate', callback);
  }

  void offIceCandidate(Function(dynamic) callback) {
    if (socket != null) socket!.off('ice_candidate', callback);
  }

  void onCallEnded(Function(dynamic) callback) {
    if (socket != null) socket!.on('call_ended', callback);
  }

  void offCallEnded(Function(dynamic) callback) {
    if (socket != null) socket!.off('call_ended', callback);
  }

  void disconnect() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
  }
}
