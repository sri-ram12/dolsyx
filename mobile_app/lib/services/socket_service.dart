import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_service.dart';

class SocketService {
  IO.Socket? socket;
  final String _socketUrl = 'https://dolsyx-app.onrender.com';

  Future<void> connect(String userId) async {
    final token = await ApiService().getToken();
    if (token == null) return;

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

  void disconnect() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
  }
}
