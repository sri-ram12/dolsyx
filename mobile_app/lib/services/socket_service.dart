import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'dart:async';
import 'api_service.dart';
import '../main.dart';
import '../screens/call_screen.dart';

class SocketService {
  IO.Socket? socket;
  final String _socketUrl = 'https://dolsyx-app.onrender.com';

  final _messageStreamController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get onMessageStream => _messageStreamController.stream;

  Future<void> connect(String userId) async {
    final token = await ApiService().getToken();
    if (token == null) return;

    if (socket != null && socket!.connected) return;

    socket = IO.io(_socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
      'auth': {'token': token},
    });

    socket?.connect();

    socket?.onConnect((_) {
      print('✅ Socket Connected');
      socket?.emit('register', userId);
    });

    socket?.on('call_incoming', _handleIncomingCall);
    socket?.on('new_message', (data) {
      _messageStreamController.add(data);
    });
    socket?.on('messages_read', (data) {
      _messageStreamController.add({'type': 'read', 'data': data});
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

  void sendMessage(String conversationId, String content, {String? mediaUrl, String? mediaType}) {
    print('Sending message. Socket connected: ${socket?.connected}');
    if (socket != null && socket!.connected) {
      socket!.emit('send_message', {
        'conversationId': conversationId,
        'content': content,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (mediaType != null) 'mediaType': mediaType,
      });
      print('Message emitted to socket.');
    } else {
      print('Failed to send: socket is null or disconnected.');
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

  void _handleIncomingCall(dynamic data) {
    print('Incoming call: $data');
    final context = navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('${data['callerName'] ?? 'Someone'} is calling...'),
          content: Text('Incoming ${data['callType'] == 'video' ? 'Video' : 'Audio'} Call'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                socket?.emit('call_reject', {
                  'callerId': data['callerId'],
                  'conversationId': data['conversationId']
                });
              },
              child: const Text('Decline', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      remoteUserId: data['callerId'],
                      remoteUserName: data['callerName'] ?? 'Unknown User',
                      conversationId: data['conversationId'],
                      isVideo: data['callType'] == 'video',
                      isIncoming: true,
                    ),
                  ),
                );
              },
              child: const Text('Accept', style: TextStyle(color: Colors.green)),
            ),
          ],
        ),
      );
    }
  }

  void disconnect() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
  }
}
