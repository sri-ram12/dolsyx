import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'sound_service.dart';
import '../main.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/e2ee/crypto_service.dart';
import '../utils/e2ee/e2ee_api.dart';

class SocketService {
  IO.Socket? socket;
  final CryptoService _crypto = CryptoService();
  
  // Stream to broadcast profile updates globally
  final StreamController<Map<String, dynamic>> profileUpdates = StreamController<Map<String, dynamic>>.broadcast();
  final String _socketUrl = 'https://dolsyx-app.onrender.com';
  
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

  String? _currentUserId;

  Future<void> connect(String userId) async {
    _currentUserId = userId;
    final token = await ApiService().getToken();
    if (token == null) return;

    if (socket != null && socket!.connected) return;

    if (socket != null) {
      socket!.connect();
      return;
    }

    socket = IO.io(_socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 20,
      'reconnectionDelay': 1000,
      'auth': {'token': token},
    });

    socket?.connect();

    socket?.onConnect((_) {
      print('✅ Socket Connected');
      socket?.emit('register', userId);
      _processOfflineQueue();
    });

    socket?.on('new_message', (data) {
      SoundService().playNotificationSound();
      _messageStreamController.add(data);
      
      try {
        final message = data['message'] ?? data;
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
      } catch (_) {}
    });

    // Listen for real-time E2EE encrypted messages and auto-decrypt them
    socket?.on('receive_encrypted_message', (data) async {
      try {
        final message = data['message'] as Map<String, dynamic>;
        final conversationId = data['conversationId'] as String;
        final content = message['content'] as String;
        final senderUserId = message['senderId'] as String;
        
        final payloadJson = jsonDecode(content) as Map<String, dynamic>;
        final payload = MessagePayload.fromJson(payloadJson);
        final plaintext = await _crypto.decryptMessage(
          senderUserId: senderUserId,
          payload: payload,
        );
        SoundService().playNotificationSound();
        _encryptedMessageController.add({
          'conversationId': conversationId,
          'message': {
            ...message,
            'content': plaintext,
          }
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

    socket?.onDisconnect((_) {
      print('❌ Socket Disconnected');
    });

    socket?.onConnectError((err) {
      print('⚠️ Socket Connection Error: $err');
    });
  }

  void joinConversation(String conversationId) {
    if (socket != null && socket!.connected) {
      socket!.emit('join_conversation', conversationId);
    }
  }

  void leaveConversation(String conversationId) {
    if (socket != null && socket!.connected) {
      socket!.emit('leave_conversation', conversationId);
    }
  }

  Future<void> _processOfflineQueue() async {
    try {
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
  }) async {
    try {
      // Fetch recipient's public key bundle
      final recipientBundle = await E2EEApi.fetchKeys(recipientEmail, token);

      // Store sender identity key so we can decrypt future messages from them
      final devices = recipientBundle['devices'] as List<dynamic>;
      if (devices.isNotEmpty) {
        final recipientUserId = recipientBundle['userId'] as String;
        final identityKey = devices.first['identityKeyPublic'] as String;
        await _crypto.storeSenderIdentityKey(recipientUserId, identityKey);
      }

      // Encrypt the message
      final messagePayload = await _crypto.encryptMessage(
        recipientKeyBundle: recipientBundle,
        plaintext: plaintext,
      );

      // Build recipient list and send to server
      final recipients = devices.map((device) => {
        'recipientDeviceId': device['id'],
        'recipientUserId': recipientBundle['userId'],
        'type': messagePayload.type,
        'ciphertext': jsonEncode(messagePayload.toJson()),
      }).toList();

      await E2EEApi.sendEncryptedMessage({
        'senderDeviceId': 1,
        'conversationId': conversationId,
        'recipients': recipients,
      }, token);
    } catch (e) {
      print('⚠️ Failed to send encrypted message: $e');
      rethrow;
    }
  }

  void sendMessage(String conversationId, String content, {String? mediaUrl, String? mediaType, String? parentMessageId, bool isForwarded = false}) async {
    print('Sending message. Socket connected: ${socket?.connected}');
    final msgData = {
      'conversationId': conversationId,
      'content': content,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
      if (parentMessageId != null) 'parentMessageId': parentMessageId,
      if (isForwarded) 'isForwarded': true,
    };

    if (socket != null && socket!.connected) {
      socket!.emit('send_message', msgData);
      print('Message emitted to socket.');
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
