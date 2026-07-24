import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'dart:async';
import 'api_service.dart';
import '../main.dart';
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

  void onCallInvite(Function(dynamic) callback) {
    if (socket != null) {
      socket!.on('call_invite', callback);
    }
  }

  void offCallInvite(Function(dynamic) callback) {
    if (socket != null) {
      socket!.off('call_invite', callback);
    }
  }

  void onCallAccepted(Function(dynamic) callback) {
    if (socket != null) socket!.on('call_accepted', callback);
  }

  void offCallAccepted(Function(dynamic) callback) {
    if (socket != null) socket!.off('call_accepted', callback);
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
