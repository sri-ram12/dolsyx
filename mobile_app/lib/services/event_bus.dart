import 'dart:async';

/// Centralized Reactive App Event Bus for WhatsApp-grade 0ms Instant UI Synchronization.
/// Enables cross-screen reactivity without requiring manual pull-to-refresh.
class AppEventBus {
  static final AppEventBus _instance = AppEventBus._internal();
  factory AppEventBus() => _instance;
  AppEventBus._internal();

  // Chat updates (new message, unread count change, read receipt)
  final StreamController<Map<String, dynamic>> _chatUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onChatUpdated => _chatUpdateController.stream;

  // Chat deletion / removal
  final StreamController<String> _chatDeletedController =
      StreamController<String>.broadcast();
  Stream<String> get onChatDeleted => _chatDeletedController.stream;

  // Contact added, edited, or deleted
  final StreamController<void> _contactUpdatedController =
      StreamController<void>.broadcast();
  Stream<void> get onContactUpdated => _contactUpdatedController.stream;

  // Status/Story added, viewed, or deleted
  final StreamController<String?> _statusUpdatedController =
      StreamController<String?>.broadcast();
  Stream<String?> get onStatusUpdated => _statusUpdatedController.stream;

  // Block/unblock updates
  final StreamController<Map<String, dynamic>> _userBlockController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onUserBlockUpdated => _userBlockController.stream;

  // Emit methods
  void emitChatUpdated(Map<String, dynamic> data) {
    if (!_chatUpdateController.isClosed) {
      _chatUpdateController.add(data);
    }
  }

  void emitChatDeleted(String conversationId) {
    if (!_chatDeletedController.isClosed) {
      _chatDeletedController.add(conversationId);
    }
  }

  void emitContactUpdated() {
    if (!_contactUpdatedController.isClosed) {
      _contactUpdatedController.add(null);
    }
  }

  void emitStatusUpdated([String? statusId]) {
    if (!_statusUpdatedController.isClosed) {
      _statusUpdatedController.add(statusId);
    }
  }

  void emitUserBlockUpdated(String userId, bool isBlocked) {
    if (!_userBlockController.isClosed) {
      _userBlockController.add({'userId': userId, 'isBlocked': isBlocked});
    }
  }
}
