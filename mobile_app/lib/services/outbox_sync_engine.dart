import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_database_service.dart';
import 'socket_service.dart';

/// WhatsApp-grade Cross-Platform Unified Outbox & Sync Queue Engine (Phase 15)
///
/// Features:
/// 1. FIFO ordering guarantee for offline messages and reactions.
/// 2. Atomic SQLite WAL state tracking (isPending = 1 -> 🕒, isPending = 0 -> ✓).
/// 3. Exponential backoff retry loop (1s, 2s, 4s, 8s, up to 30s) on network disconnects.
/// 4. Concurrency lock preventing duplicated socket transmissions.
/// 5. Persistent offline outbox actions for Reactions and Read Receipts.
class OutboxSyncEngine {
  static final OutboxSyncEngine _instance = OutboxSyncEngine._internal();
  factory OutboxSyncEngine() => _instance;
  OutboxSyncEngine._internal();

  bool _isFlushing = false;
  Timer? _retryTimer;
  int _currentBackoffMs = 1000;
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  /// Initializes the outbox listener with SocketService
  void initialize(SocketService socketService) {
    _refreshPendingCount();

    // Hook into socket connection & reconnection events
    socketService.socket?.on('connect', (_) {
      debugPrint('[OutboxSyncEngine] Socket connected. Triggering outbox flush...');
      _currentBackoffMs = 1000;
      flushOutbox(socketService);
    });

    socketService.socket?.on('reconnect', (_) {
      debugPrint('[OutboxSyncEngine] Socket reconnected. Triggering outbox flush...');
      _currentBackoffMs = 1000;
      flushOutbox(socketService);
    });
  }

  /// Recalculates total pending items in the outbox
  Future<void> _refreshPendingCount() async {
    try {
      final pending = await LocalDatabaseService().getPendingMessages();
      pendingCountNotifier.value = pending.length;
    } catch (_) {}
  }

  /// Drains all pending messages and actions in strict FIFO order
  Future<void> flushOutbox(SocketService socketService) async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      if (socketService.socket == null || !socketService.socket!.connected) {
        debugPrint('[OutboxSyncEngine] Socket offline. Scheduling exponential retry in ${_currentBackoffMs}ms');
        _scheduleRetry(socketService);
        _isFlushing = false;
        return;
      }

      // 1. Drain Pending Messages from SQLite WAL
      final pendingMessages = await LocalDatabaseService().getPendingMessages();
      pendingCountNotifier.value = pendingMessages.length;

      for (final msg in pendingMessages) {
        if (socketService.socket == null || !socketService.socket!.connected) {
          debugPrint('[OutboxSyncEngine] Socket lost during message flush. Aborting.');
          _scheduleRetry(socketService);
          break;
        }

        debugPrint('[OutboxSyncEngine] Dispatching pending message: ${msg.id}');
        socketService.sendMessage(
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

        // Small pacing delay to avoid flooding WebSocket buffer
        await Future.delayed(const Duration(milliseconds: 60));
      }

      // 2. Drain Outbox Actions (Reactions, Receipts)
      final pendingActions = await LocalDatabaseService().getPendingOutboxActions();
      for (final row in pendingActions) {
        if (socketService.socket == null || !socketService.socket!.connected) break;

        final actionId = row['id'] as String;
        final actionType = row['actionType'] as String;
        final payloadStr = row['payloadJson'] as String;

        try {
          final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
          if (actionType == 'REACTION') {
            socketService.socket?.emit('add_reaction', payload);
            await LocalDatabaseService().removeOutboxAction(actionId);
          } else if (actionType == 'READ_RECEIPT') {
            socketService.socket?.emit('mark_read', payload);
            await LocalDatabaseService().removeOutboxAction(actionId);
          }
        } catch (e) {
          debugPrint('[OutboxSyncEngine] Error dispatching outbox action $actionId: $e');
        }
      }

      await _refreshPendingCount();
      _currentBackoffMs = 1000;
    } catch (e) {
      debugPrint('[OutboxSyncEngine] Error during flush: $e');
      _scheduleRetry(socketService);
    } finally {
      _isFlushing = false;
    }
  }

  /// Enqueues an offline reaction with fallback to online dispatch
  Future<void> sendReaction({
    required String messageId,
    required String conversationId,
    required String emoji,
    required SocketService socketService,
  }) async {
    final payload = {
      'messageId': messageId,
      'conversationId': conversationId,
      'emoji': emoji,
    };

    if (socketService.socket != null && socketService.socket!.connected) {
      socketService.socket?.emit('add_reaction', payload);
    } else {
      await LocalDatabaseService().enqueueOutboxAction('REACTION', payload);
    }
  }

  /// Enqueues an offline read receipt with fallback to online dispatch
  Future<void> sendReadReceipt({
    required String conversationId,
    required String userId,
    required List<dynamic> messageIds,
    required SocketService socketService,
  }) async {
    final payload = {
      'conversationId': conversationId,
      'userId': userId,
      'messageIds': messageIds,
    };

    if (socketService.socket != null && socketService.socket!.connected) {
      socketService.socket?.emit('mark_read', payload);
    } else {
      await LocalDatabaseService().enqueueOutboxAction('READ_RECEIPT', payload);
    }
  }

  void _scheduleRetry(SocketService socketService) {
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: _currentBackoffMs), () {
      flushOutbox(socketService);
    });
    // Exponential backoff scaling up to 30 seconds
    _currentBackoffMs = (_currentBackoffMs * 2).clamp(1000, 30000);
  }

  void dispose() {
    _retryTimer?.cancel();
    pendingCountNotifier.dispose();
  }
}
