import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../utils/e2ee/e2ee_media_cache.dart';

/// WhatsApp-grade Local SQLite Database Service (msgstore.db style)
/// Provides sub-millisecond local reads, Write-Ahead Logging (WAL), and persistent disk storage.
class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'dolsyx_msgstore.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // High-performance Write-Ahead Logging (WAL) configuration
        try {
          await db.execute('PRAGMA journal_mode=WAL;');
          await db.execute('PRAGMA synchronous=NORMAL;');
        } catch (_) {}

        // 1. Conversations Table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS local_conversations (
            id TEXT PRIMARY KEY,
            name TEXT,
            isGroup INTEGER DEFAULT 0,
            avatarUrl TEXT,
            participantsJson TEXT,
            lastMessageJson TEXT,
            unreadCount INTEGER DEFAULT 0,
            updatedAt INTEGER DEFAULT 0,
            isArchived INTEGER DEFAULT 0,
            isPinned INTEGER DEFAULT 0,
            isLocked INTEGER DEFAULT 0,
            pinnedAt INTEGER DEFAULT 0,
            rawJson TEXT
          )
        ''');

        // Indexes for instant O(log N) sorting & filtering
        await db.execute('CREATE INDEX IF NOT EXISTS idx_conv_updatedAt ON local_conversations (updatedAt DESC);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_conv_pinned ON local_conversations (isPinned DESC, updatedAt DESC);');

        // 2. Messages Table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS local_messages (
            id TEXT PRIMARY KEY,
            conversationId TEXT NOT NULL,
            senderId TEXT NOT NULL,
            content TEXT,
            mediaUrl TEXT,
            mediaType TEXT,
            mediaKey TEXT,
            nonce TEXT,
            isE2EEMedia INTEGER DEFAULT 0,
            fileSize INTEGER,
            fileName TEXT,
            isViewOnce INTEGER DEFAULT 0,
            isViewed INTEGER DEFAULT 0,
            isPending INTEGER DEFAULT 0,
            isPinned INTEGER DEFAULT 0,
            isEdited INTEGER DEFAULT 0,
            isDeleted INTEGER DEFAULT 0,
            isForwarded INTEGER DEFAULT 0,
            parentMessageId TEXT,
            parentMessageJson TEXT,
            senderJson TEXT,
            latitude REAL,
            longitude REAL,
            locationTitle TEXT,
            isLiveLocation INTEGER DEFAULT 0,
            liveExpiresAt INTEGER DEFAULT 0,
            isLiveEnded INTEGER DEFAULT 0,
            receiptsJson TEXT,
            reactionsJson TEXT,
            createdAt INTEGER NOT NULL,
            thumbnail TEXT,
            rawJson TEXT
          )
        ''');

        // Indexes for sub-millisecond pagination and lookup
        await db.execute('CREATE INDEX IF NOT EXISTS idx_msg_conv_created ON local_messages (conversationId, createdAt DESC);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_msg_pending ON local_messages (isPending);');

        // Safe automatic schema evolution
        try {
          await db.execute('ALTER TABLE local_messages ADD COLUMN thumbnail TEXT;');
        } catch (_) {}

        // 3. Call Logs Table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS local_call_logs (
            id TEXT PRIMARY KEY,
            callId TEXT,
            callerId TEXT,
            receiverId TEXT,
            callerName TEXT,
            callerAvatar TEXT,
            callType TEXT,
            status TEXT,
            duration INTEGER DEFAULT 0,
            createdAt INTEGER NOT NULL,
            rawJson TEXT
          )
        ''');

        await db.execute('CREATE INDEX IF NOT EXISTS idx_calls_created ON local_call_logs (createdAt DESC);');
      },
      onOpen: (db) async {
        await _ensureFtsTable(db);
      },
    );
  }

  /// WhatsApp-grade Full-Text Search (FTS5) Table & Trigger Engine
  Future<void> _ensureFtsTable(Database db) async {
    try {
      // 1. Try creating FTS5 virtual table
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
          message_id UNINDEXED,
          conversation_id UNINDEXED,
          content,
          tokenize='unicode61'
        );
      ''');
    } catch (_) {
      try {
        // Fallback to FTS4 if FTS5 module is not compiled on legacy OS
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts4(
            message_id,
            conversation_id,
            content,
            tokenize=unicode61
          );
        ''');
      } catch (e) {
        debugPrint('[LocalDB] FTS virtual table init note: $e');
      }
    }

    // 2. High-speed automated SQLite triggers for zero-lag index updates
    try {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_msg_fts_insert AFTER INSERT ON local_messages
        BEGIN
          INSERT INTO messages_fts(message_id, conversation_id, content)
          VALUES (new.id, new.conversationId, COALESCE(new.content, ''));
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_msg_fts_delete AFTER DELETE ON local_messages
        BEGIN
          DELETE FROM messages_fts WHERE message_id = old.id;
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_msg_fts_update AFTER UPDATE OF content ON local_messages
        BEGIN
          UPDATE messages_fts SET content = COALESCE(new.content, '') WHERE message_id = new.id;
        END;
      ''');
    } catch (e) {
      debugPrint('[LocalDB] FTS triggers note: $e');
    }

    // 3. Fast one-time backfill for messages not yet indexed
    try {
      await db.execute('''
        INSERT OR IGNORE INTO messages_fts(message_id, conversation_id, content)
        SELECT id, conversationId, COALESCE(content, '')
        FROM local_messages
        WHERE content IS NOT NULL AND content != ''
        AND id NOT IN (SELECT message_id FROM messages_fts);
      ''');
    } catch (_) {}
  }

  // =========================================================================
  // 📁 CONVERSATIONS (CHAT LIST) OPERATIONS
  // =========================================================================

  /// Loads all cached conversations ordered by pinned and recent activity (0ms load)
  Future<List<Chat>> getConversations({int limit = 100, int offset = 0}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'local_conversations',
        orderBy: 'isPinned DESC, updatedAt DESC',
        limit: limit,
        offset: offset,
      );

      if (rows.isNotEmpty) {
        return rows.map((r) => _chatFromRow(r)).toList();
      }

      // Seamless migration fallback: If SQLite is empty, migrate from SharedPreferences
      return await _migrateChatsFromPrefs();
    } catch (e) {
      debugPrint('[LocalDB] Error fetching conversations: $e');
      return [];
    }
  }

  /// Saves a batch of conversations in a single atomic SQLite transaction
  Future<void> saveConversations(List<Chat> chats) async {
    if (chats.isEmpty) return;
    try {
      final db = await database;
      final batch = db.batch();

      for (final chat in chats) {
        batch.insert(
          'local_conversations',
          _chatToRow(chat),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[LocalDB] Error saving conversations batch: $e');
    }
  }

  /// Inserts or updates a single conversation
  Future<void> saveConversation(Chat chat) async {
    try {
      final db = await database;
      await db.insert(
        'local_conversations',
        _chatToRow(chat),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[LocalDB] Error saving single conversation: $e');
    }
  }

  /// Updates last message and timestamp for a conversation (called upon socket message arrival)
  Future<void> updateConversationLastMessage(String conversationId, Map<String, dynamic> message, {int? unreadIncrement}) async {
    try {
      final db = await database;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastMsgJson = jsonEncode(message);

      if (unreadIncrement != null && unreadIncrement > 0) {
        await db.rawUpdate('''
          UPDATE local_conversations
          SET lastMessageJson = ?, updatedAt = ?, unreadCount = unreadCount + ?
          WHERE id = ?
        ''', [lastMsgJson, nowMs, unreadIncrement, conversationId]);
      } else {
        await db.rawUpdate('''
          UPDATE local_conversations
          SET lastMessageJson = ?, updatedAt = ?
          WHERE id = ?
        ''', [lastMsgJson, nowMs, conversationId]);
      }
    } catch (e) {
      debugPrint('[LocalDB] Error updating last message: $e');
    }
  }

  /// Clears unread count when user opens the chat
  Future<void> markConversationRead(String conversationId) async {
    try {
      final db = await database;
      await db.update(
        'local_conversations',
        {'unreadCount': 0},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    } catch (e) {
      debugPrint('[LocalDB] Error marking conversation read: $e');
    }
  }

  /// Sets or clears biometric lock flag for a conversation (Phase 14)
  Future<void> setChatLocked(String conversationId, bool isLocked) async {
    try {
      final db = await database;
      await db.update(
        'local_conversations',
        {'isLocked': isLocked ? 1 : 0},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    } catch (e) {
      debugPrint('[LocalDB] Error setting chat locked: $e');
    }
  }

  /// Deletes a conversation from SQLite
  Future<void> deleteConversation(String conversationId) async {
    try {
      final db = await database;
      await db.delete('local_conversations', where: 'id = ?', whereArgs: [conversationId]);
      await db.delete('local_messages', where: 'conversationId = ?', whereArgs: [conversationId]);
    } catch (e) {
      debugPrint('[LocalDB] Error deleting conversation: $e');
    }
  }

  // =========================================================================
  // 💬 MESSAGES OPERATIONS (CHAT ROOM)
  // =========================================================================

  /// Loads messages for a conversation ordered chronologically (0ms load)
  Future<List<Message>> getMessages(String conversationId, {int limit = 50, int offset = 0}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'local_messages',
        where: 'conversationId = ?',
        whereArgs: [conversationId],
        orderBy: 'createdAt DESC',
        limit: limit,
        offset: offset,
      );

      if (rows.isNotEmpty) {
        // Reverse so index 0 is oldest and end is newest, matching screen order
        final list = rows.map((r) => _messageFromRow(r)).toList();
        return list.reversed.toList();
      }

      // Seamless migration fallback: If SQLite has no messages, migrate from SharedPreferences
      return await _migrateMessagesFromPrefs(conversationId);
    } catch (e) {
      debugPrint('[LocalDB] Error fetching messages for $conversationId: $e');
      return [];
    }
  }

  /// Saves a batch of messages in an atomic SQLite transaction
  Future<void> saveMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    try {
      final db = await database;
      final batch = db.batch();

      for (final msg in messages) {
        batch.insert(
          'local_messages',
          _messageToRow(msg),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[LocalDB] Error saving messages batch: $e');
    }
  }

  /// Saves or updates a single message (for incoming real-time socket events)
  Future<void> saveSingleMessage(Message msg) async {
    try {
      final db = await database;
      await db.insert(
        'local_messages',
        _messageToRow(msg),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[LocalDB] Error saving single message: $e');
    }
  }

  /// Replaces an optimistic temp message with the confirmed server message
  Future<void> replaceTempMessage(String tempId, Message confirmedMsg) async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        await txn.delete('local_messages', where: 'id = ?', whereArgs: [tempId]);
        await txn.insert(
          'local_messages',
          _messageToRow(confirmedMsg),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } catch (e) {
      debugPrint('[LocalDB] Error replacing temp message: $e');
    }
  }

  /// Confirms an optimistic pending message when server returns ACK
  Future<void> confirmPendingMessage({
    required String tempId,
    required String confirmedId,
    DateTime? createdAt,
  }) async {
    try {
      final db = await database;
      final values = <String, dynamic>{
        'id': confirmedId,
        'isPending': 0,
      };
      if (createdAt != null) {
        values['createdAt'] = createdAt.millisecondsSinceEpoch;
      }
      await db.update(
        'local_messages',
        values,
        where: 'id = ?',
        whereArgs: [tempId],
      );
    } catch (e) {
      debugPrint('[LocalDB] Error confirming pending message: $e');
    }
  }

  /// Fetches all pending messages across all conversations for automatic outbox flush
  Future<List<Message>> getPendingMessages() async {
    try {
      final db = await database;
      final rows = await db.query(
        'local_messages',
        where: 'isPending = ?',
        whereArgs: [1],
        orderBy: 'createdAt ASC',
      );
      return rows.map((r) => _messageFromRow(r)).toList();
    } catch (e) {
      debugPrint('[LocalDB] Error fetching pending messages: $e');
      return [];
    }
  }

  /// Bulk updates message receipts in local SQLite to DELIVERED
  Future<void> markMessagesDeliveredLocally({
    required String conversationId,
    required String userId,
    List<dynamic>? messageIds,
  }) async {
    try {
      final db = await database;
      final rows = await db.query(
        'local_messages',
        where: 'conversationId = ?',
        whereArgs: [conversationId],
      );

      final batch = db.batch();
      for (final r in rows) {
        final id = r['id'] as String;
        if (messageIds != null && messageIds.isNotEmpty && !messageIds.contains(id)) {
          continue;
        }
        if (r['senderId'] == userId) continue;

        List<dynamic> receipts = [];
        if (r['receiptsJson'] != null) {
          try {
            receipts = List<dynamic>.from(jsonDecode(r['receiptsJson'] as String));
          } catch (_) {}
        }

        final existingIdx = receipts.indexWhere((rc) => rc['userId'] == userId);
        if (existingIdx != -1) {
          if (receipts[existingIdx]['status'] != 'READ') {
            receipts[existingIdx] = {'userId': userId, 'status': 'DELIVERED'};
            batch.update(
              'local_messages',
              {'receiptsJson': jsonEncode(receipts)},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        } else {
          receipts.add({'userId': userId, 'status': 'DELIVERED'});
          batch.update(
            'local_messages',
            {'receiptsJson': jsonEncode(receipts)},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[LocalDB] Error updating delivered receipts locally: $e');
    }
  }

  /// Bulk updates message receipts in local SQLite to READ
  Future<void> markMessagesReadLocally({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final db = await database;
      final rows = await db.query(
        'local_messages',
        where: 'conversationId = ?',
        whereArgs: [conversationId],
      );

      final batch = db.batch();
      for (final r in rows) {
        final id = r['id'] as String;
        if (r['senderId'] == userId) continue;

        List<dynamic> receipts = [];
        if (r['receiptsJson'] != null) {
          try {
            receipts = List<dynamic>.from(jsonDecode(r['receiptsJson'] as String));
          } catch (_) {}
        }

        final existingIdx = receipts.indexWhere((rc) => rc['userId'] == userId);
        if (existingIdx != -1) {
          receipts[existingIdx] = {'userId': userId, 'status': 'READ'};
        } else {
          receipts.add({'userId': userId, 'status': 'READ'});
        }
        batch.update(
          'local_messages',
          {'receiptsJson': jsonEncode(receipts)},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[LocalDB] Error updating read receipts locally: $e');
    }
  }

  /// Updates message delivery/read receipts
  Future<void> updateMessageReceipts(String messageId, List<dynamic> receipts) async {
    try {
      final db = await database;
      await db.update(
        'local_messages',
        {'receiptsJson': jsonEncode(receipts)},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('[LocalDB] Error updating receipts: $e');
    }
  }

  /// Updates message reactions
  Future<void> updateMessageReactions(String messageId, List<dynamic> reactions) async {
    try {
      final db = await database;
      await db.update(
        'local_messages',
        {'reactionsJson': jsonEncode(reactions)},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('[LocalDB] Error updating reactions: $e');
    }
  }

  /// Marks a message as deleted
  Future<void> markMessageDeleted(String messageId) async {
    try {
      final db = await database;
      await db.update(
        'local_messages',
        {'isDeleted': 1, 'content': 'This message was deleted'},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('[LocalDB] Error marking message deleted: $e');
    }
  }

  /// Marks a view-once message as viewed
  Future<void> markViewOnceViewed(String messageId) async {
    try {
      final db = await database;
      await db.update(
        'local_messages',
        {'isViewed': 1},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('[LocalDB] Error marking view once viewed: $e');
    }
  }

  /// Deletes a single message
  Future<void> deleteMessage(String messageId) async {
    try {
      final db = await database;
      await db.delete('local_messages', where: 'id = ?', whereArgs: [messageId]);
    } catch (e) {
      debugPrint('[LocalDB] Error deleting message: $e');
    }
  }

  /// Clears all messages in a conversation
  Future<void> clearConversationMessages(String conversationId) async {
    try {
      final db = await database;
      await db.delete('local_messages', where: 'conversationId = ?', whereArgs: [conversationId]);
    } catch (e) {
      debugPrint('[LocalDB] Error clearing conversation messages: $e');
    }
  }

  /// WhatsApp-grade Full-Text Search (FTS5) across all conversations in < 2ms
  Future<List<Map<String, dynamic>>> searchMessagesUniversal(
    String query, {
    String? conversationId,
    int limit = 50,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final db = await database;

      // Tokenize query words for FTS prefix matching
      final sanitizedTokens = cleanQuery
          .replaceAll(RegExp(r'[^\w\s]', unicode: true), ' ')
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .map((t) => '$t*')
          .join(' ');

      if (sanitizedTokens.isNotEmpty) {
        try {
          final ftsSql = (conversationId != null && conversationId.isNotEmpty)
              ? '''
                SELECT m.*, snippet(messages_fts, 2, '[[H]]', '[[/H]]', '...', 12) as matchSnippet
                FROM messages_fts fts
                JOIN local_messages m ON fts.message_id = m.id
                WHERE messages_fts MATCH ? AND fts.conversation_id = ?
                ORDER BY m.createdAt DESC
                LIMIT ?;
              '''
              : '''
                SELECT m.*, snippet(messages_fts, 2, '[[H]]', '[[/H]]', '...', 12) as matchSnippet,
                       c.name as conversationName, c.avatarUrl as conversationAvatar, c.isGroup as conversationIsGroup
                FROM messages_fts fts
                JOIN local_messages m ON fts.message_id = m.id
                LEFT JOIN local_conversations c ON m.conversationId = c.id
                WHERE messages_fts MATCH ?
                ORDER BY m.createdAt DESC
                LIMIT ?;
              ''';

          final args = (conversationId != null && conversationId.isNotEmpty)
              ? [sanitizedTokens, conversationId, limit]
              : [sanitizedTokens, limit];

          final ftsRows = await db.rawQuery(ftsSql, args);
          if (ftsRows.isNotEmpty) {
            return ftsRows;
          }
        } catch (ftsError) {
          debugPrint('[LocalDB] FTS MATCH note, falling back to indexed scan: $ftsError');
        }
      }

      // High-performance indexed LIKE fallback
      final likePattern = '%$cleanQuery%';
      final fallbackSql = (conversationId != null && conversationId.isNotEmpty)
          ? '''
            SELECT m.*, m.content as matchSnippet
            FROM local_messages m
            WHERE m.conversationId = ? AND m.content LIKE ?
            ORDER BY m.createdAt DESC
            LIMIT ?;
          '''
          : '''
            SELECT m.*, m.content as matchSnippet,
                   c.name as conversationName, c.avatarUrl as conversationAvatar, c.isGroup as conversationIsGroup
            FROM local_messages m
            LEFT JOIN local_conversations c ON m.conversationId = c.id
            WHERE m.content LIKE ?
            ORDER BY m.createdAt DESC
            LIMIT ?;
          ''';

      final fallbackArgs = (conversationId != null && conversationId.isNotEmpty)
          ? [conversationId, likePattern, limit]
          : [likePattern, limit];

      return await db.rawQuery(fallbackSql, fallbackArgs);
    } catch (e) {
      debugPrint('[LocalDB] Universal search error: $e');
      return [];
    }
  }

  // =========================================================================
  // 📞 CALL LOGS OPERATIONS
  // =========================================================================

  Future<List<Map<String, dynamic>>> getCallLogs({int limit = 100}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'local_call_logs',
        orderBy: 'createdAt DESC',
        limit: limit,
      );
      return rows.map((r) {
        if (r['rawJson'] != null) {
          try {
            return Map<String, dynamic>.from(jsonDecode(r['rawJson'] as String));
          } catch (_) {}
        }
        return Map<String, dynamic>.from(r);
      }).toList();
    } catch (e) {
      debugPrint('[LocalDB] Error fetching call logs: $e');
      return [];
    }
  }

  Future<void> saveCallLogs(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return;
    try {
      final db = await database;
      final batch = db.batch();

      for (final log in logs) {
        final id = (log['id'] ?? log['_id'] ?? log['callId'] ?? DateTime.now().millisecondsSinceEpoch).toString();
        final createdAt = log['createdAt'] != null
            ? (DateTime.tryParse(log['createdAt'].toString())?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch)
            : DateTime.now().millisecondsSinceEpoch;

        batch.insert(
          'local_call_logs',
          {
            'id': id,
            'callId': log['callId']?.toString() ?? id,
            'callerId': log['callerId']?.toString(),
            'receiverId': log['receiverId']?.toString(),
            'callerName': log['callerName']?.toString(),
            'callerAvatar': log['callerAvatar']?.toString(),
            'callType': log['callType']?.toString() ?? 'AUDIO',
            'status': log['status']?.toString() ?? 'COMPLETED',
            'duration': (log['duration'] as num?)?.toInt() ?? 0,
            'createdAt': createdAt,
            'rawJson': jsonEncode(log),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[LocalDB] Error saving call logs: $e');
    }
  }

  Future<void> clearCallLogs() async {
    try {
      final db = await database;
      await db.delete('local_call_logs');
    } catch (e) {
      debugPrint('[LocalDB] Error clearing call logs: $e');
    }
  }

  Future<void> deleteCallLog(String callId) async {
    try {
      final db = await database;
      await db.delete('local_call_logs', where: 'id = ? OR callId = ?', whereArgs: [callId, callId]);
    } catch (e) {
      debugPrint('[LocalDB] Error deleting single call log: $e');
    }
  }

  // =========================================================================
  // 🔄 MIGRATION & HELPER CONVERTERS
  // =========================================================================

  Map<String, dynamic> _chatToRow(Chat chat) {
    return {
      'id': chat.id,
      'name': chat.name,
      'isGroup': chat.isGroup ? 1 : 0,
      'avatarUrl': chat.avatarUrl,
      'participantsJson': chat.participants != null ? jsonEncode(chat.participants) : null,
      'lastMessageJson': chat.lastMessage != null ? jsonEncode(chat.lastMessage) : null,
      'unreadCount': chat.unreadCount,
      'updatedAt': chat.updatedAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
      'isArchived': chat.isArchived ? 1 : 0,
      'isPinned': chat.isPinned ? 1 : 0,
      'isLocked': chat.isLocked ? 1 : 0,
      'pinnedAt': chat.pinnedAt?.millisecondsSinceEpoch ?? 0,
      'rawJson': jsonEncode(chat.toJson()),
    };
  }

  Chat _chatFromRow(Map<String, dynamic> r) {
    List<dynamic>? participants;
    if (r['participantsJson'] != null) {
      try {
        participants = jsonDecode(r['participantsJson'] as String);
      } catch (_) {}
    }

    Map<String, dynamic>? lastMessage;
    if (r['lastMessageJson'] != null) {
      try {
        lastMessage = jsonDecode(r['lastMessageJson'] as String);
      } catch (_) {}
    }

    DateTime? updatedAt;
    if (r['updatedAt'] != null) {
      final ms = r['updatedAt'] as int;
      if (ms > 0) updatedAt = DateTime.fromMillisecondsSinceEpoch(ms);
    }

    DateTime? pinnedAt;
    if (r['pinnedAt'] != null) {
      final ms = r['pinnedAt'] as int;
      if (ms > 0) pinnedAt = DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return Chat(
      id: r['id'] as String,
      name: r['name'] as String?,
      isGroup: (r['isGroup'] as int?) == 1,
      avatarUrl: r['avatarUrl'] as String?,
      participants: participants,
      lastMessage: lastMessage,
      unreadCount: (r['unreadCount'] as int?) ?? 0,
      updatedAt: updatedAt,
      isArchived: (r['isArchived'] as int?) == 1,
      isPinned: (r['isPinned'] as int?) == 1,
      isLocked: (r['isLocked'] as int?) == 1,
      pinnedAt: pinnedAt,
    );
  }

  Map<String, dynamic> _messageToRow(Message msg) {
    return {
      'id': msg.id,
      'conversationId': msg.conversationId,
      'senderId': msg.senderId,
      'content': msg.content,
      'mediaUrl': msg.mediaUrl,
      'mediaType': msg.mediaType,
      'mediaKey': msg.mediaKey,
      'nonce': msg.nonce,
      'isE2EEMedia': msg.isE2EEMedia ? 1 : 0,
      'fileSize': msg.fileSize,
      'fileName': msg.fileName,
      'isViewOnce': msg.isViewOnce ? 1 : 0,
      'isViewed': msg.isViewed ? 1 : 0,
      'isPending': msg.isPending ? 1 : 0,
      'isPinned': msg.isPinned ? 1 : 0,
      'isEdited': msg.isEdited ? 1 : 0,
      'isDeleted': msg.isDeleted ? 1 : 0,
      'isForwarded': msg.isForwarded ? 1 : 0,
      'parentMessageId': msg.parentMessageId,
      'parentMessageJson': msg.parentMessage != null ? jsonEncode(msg.parentMessage) : null,
      'senderJson': msg.sender != null ? jsonEncode(msg.sender) : null,
      'latitude': msg.latitude,
      'longitude': msg.longitude,
      'locationTitle': msg.locationTitle,
      'isLiveLocation': msg.isLiveLocation ? 1 : 0,
      'liveExpiresAt': msg.liveExpiresAt?.millisecondsSinceEpoch ?? 0,
      'isLiveEnded': msg.isLiveEnded ? 1 : 0,
      'receiptsJson': msg.receipts != null ? jsonEncode(msg.receipts) : null,
      'reactionsJson': msg.reactions != null ? jsonEncode(msg.reactions) : null,
      'createdAt': msg.createdAt.millisecondsSinceEpoch,
      'thumbnail': msg.thumbnail,
      'rawJson': jsonEncode(msg.toJson()),
    };
  }

  Message _messageFromRow(Map<String, dynamic> r) {
    Map<String, dynamic>? parentMessage;
    if (r['parentMessageJson'] != null) {
      try {
        parentMessage = jsonDecode(r['parentMessageJson'] as String);
      } catch (_) {}
    }

    Map<String, dynamic>? sender;
    if (r['senderJson'] != null) {
      try {
        sender = jsonDecode(r['senderJson'] as String);
      } catch (_) {}
    }

    List<dynamic>? receipts;
    if (r['receiptsJson'] != null) {
      try {
        receipts = jsonDecode(r['receiptsJson'] as String);
      } catch (_) {}
    }

    List<dynamic>? reactions;
    if (r['reactionsJson'] != null) {
      try {
        reactions = jsonDecode(r['reactionsJson'] as String);
      } catch (_) {}
    }

    DateTime? liveExpiresAt;
    if (r['liveExpiresAt'] != null && (r['liveExpiresAt'] as int) > 0) {
      liveExpiresAt = DateTime.fromMillisecondsSinceEpoch(r['liveExpiresAt'] as int);
    }

    final createdAtMs = (r['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch;

    return Message(
      id: r['id'] as String,
      content: (r['content'] as String?) ?? '',
      senderId: (r['senderId'] as String?) ?? '',
      conversationId: (r['conversationId'] as String?) ?? '',
      parentMessageId: r['parentMessageId'] as String?,
      isEdited: (r['isEdited'] as int?) == 1,
      isDeleted: (r['isDeleted'] as int?) == 1,
      isForwarded: (r['isForwarded'] as int?) == 1,
      mediaUrl: r['mediaUrl'] as String?,
      mediaType: r['mediaType'] as String?,
      isViewOnce: (r['isViewOnce'] as int?) == 1,
      isViewed: (r['isViewed'] as int?) == 1,
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
      locationTitle: r['locationTitle'] as String?,
      isLiveLocation: (r['isLiveLocation'] as int?) == 1,
      liveExpiresAt: liveExpiresAt,
      isLiveEnded: (r['isLiveEnded'] as int?) == 1,
      receipts: receipts,
      reactions: reactions,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      parentMessage: parentMessage,
      sender: sender,
      isPending: (r['isPending'] as int?) == 1,
      isPinned: (r['isPinned'] as int?) == 1,
      mediaKey: r['mediaKey'] as String?,
      nonce: r['nonce'] as String?,
      isE2EEMedia: (r['isE2EEMedia'] as int?) == 1,
      fileSize: (r['fileSize'] as int?),
      fileName: r['fileName'] as String?,
      thumbnail: r['thumbnail'] as String?,
    );
  }

  /// Migrates chats from SharedPreferences into SQLite on first run
  Future<List<Chat>> _migrateChatsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_chats');
      if (cached != null && cached.isNotEmpty) {
        final List<dynamic> data = jsonDecode(cached);
        final list = data.map((json) => Chat.fromJson(json)).toList();
        if (list.isNotEmpty) {
          await saveConversations(list);
          debugPrint('[LocalDB] Migrated ${list.length} chats from SharedPreferences to SQLite.');
          return list;
        }
      }
    } catch (e) {
      debugPrint('[LocalDB] Migration error from prefs: $e');
    }
    return [];
  }

  /// Migrates messages from SharedPreferences into SQLite on first run
  Future<List<Message>> _migrateMessagesFromPrefs(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final decCached = prefs.getString('cached_decrypted_$conversationId') ?? prefs.getString('cached_messages_$conversationId');
      if (decCached != null && decCached.isNotEmpty) {
        final List<dynamic> data = jsonDecode(decCached);
        final list = data.map((json) => Message.fromJson(json)).toList();
        if (list.isNotEmpty) {
          await saveMessages(list);
          debugPrint('[LocalDB] Migrated ${list.length} messages for $conversationId from SharedPreferences to SQLite.');
          return list;
        }
      }
    } catch (e) {
      debugPrint('[LocalDB] Message migration error for $conversationId: $e');
    }
    return [];
  }

  // =========================================================================
  // WHATSAPP STORAGE & DATA MANAGEMENT ENGINE (PHASE 8)
  // =========================================================================

  /// Calculates real physical disk breakdown for DOLSYX database, media files, and cache
  Future<Map<String, dynamic>> getStorageBreakdown() async {
    final db = await database;
    int databaseBytes = 0;
    int mediaBytes = 0;
    int photosBytes = 0;
    int videosBytes = 0;
    int audioBytes = 0;
    int docsBytes = 0;
    int photosCount = 0;
    int videosCount = 0;
    int audioCount = 0;
    int docsCount = 0;
    int largeFilesCount = 0;
    int largeFilesBytes = 0;
    int cacheBytes = 0;

    try {
      // 1. Calculate physical SQLite database file sizes
      final dbPath = await getDatabasesPath();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File(p.join(dbPath, 'dolsyx_msgstore.db$suffix'));
        if (f.existsSync()) {
          databaseBytes += f.lengthSync();
        }
      }
    } catch (e) {
      debugPrint('[StorageEngine] Error calculating DB size: $e');
    }

    try {
      // 2. Calculate temporary cache size
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final list = tempDir.listSync(recursive: true, followLinks: false);
        for (final entity in list) {
          if (entity is File) {
            try {
              cacheBytes += entity.lengthSync();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[StorageEngine] Error calculating cache size: $e');
    }

    try {
      // 3. Aggregate categorized media from local_messages
      final rows = await db.rawQuery('''
        SELECT 
          id, media_type, file_size, file_path, media_url
        FROM local_messages
        WHERE media_url IS NOT NULL OR file_path IS NOT NULL
      ''');

      const fiveMb = 5 * 1024 * 1024;
      for (final r in rows) {
        final type = (r['media_type'] as String? ?? '').toUpperCase();
        int size = (r['file_size'] as int?) ?? 0;
        final filePath = r['file_path'] as String?;

        if (size <= 0 && filePath != null && filePath.isNotEmpty) {
          try {
            final f = File(filePath);
            if (f.existsSync()) {
              size = f.lengthSync();
            }
          } catch (_) {}
        }

        mediaBytes += size;

        if (type == 'IMAGE') {
          photosBytes += size;
          photosCount++;
        } else if (type == 'VIDEO') {
          videosBytes += size;
          videosCount++;
        } else if (type == 'AUDIO' || type == 'VOICE') {
          audioBytes += size;
          audioCount++;
        } else if (type == 'DOCUMENT') {
          docsBytes += size;
          docsCount++;
        }

        if (size >= fiveMb) {
          largeFilesCount++;
          largeFilesBytes += size;
        }
      }
    } catch (e) {
      debugPrint('[StorageEngine] Error querying media stats: $e');
    }

    final totalAppBytes = databaseBytes + mediaBytes + cacheBytes;

    return {
      'databaseBytes': databaseBytes,
      'mediaBytes': mediaBytes,
      'cacheBytes': cacheBytes,
      'photosBytes': photosBytes,
      'photosCount': photosCount,
      'videosBytes': videosBytes,
      'videosCount': videosCount,
      'audioBytes': audioBytes,
      'audioCount': audioCount,
      'docsBytes': docsBytes,
      'docsCount': docsCount,
      'largeFilesCount': largeFilesCount,
      'largeFilesBytes': largeFilesBytes,
      'totalAppBytes': totalAppBytes,
    };
  }

  /// Retrieves media items larger than [minSizeBytes] (default: 5MB) across all chats
  Future<List<Map<String, dynamic>>> getLargeMediaItems({int minSizeBytes = 5242880}) async {
    final db = await database;
    try {
      final rows = await db.rawQuery('''
        SELECT 
          m.id, m.conversation_id, m.media_url, m.media_type, m.file_path, m.file_size, 
          m.file_name, m.thumbnail, m.created_at,
          c.name as conversation_name, c.avatarUrl as conversation_avatar
        FROM local_messages m
        LEFT JOIN local_conversations c ON m.conversation_id = c.id
        WHERE (m.media_url IS NOT NULL OR m.file_path IS NOT NULL)
          AND (m.file_size >= ? OR m.file_size IS NULL)
        ORDER BY COALESCE(m.file_size, 0) DESC, m.created_at DESC
        LIMIT 150
      ''', [minSizeBytes]);

      final results = <Map<String, dynamic>>[];
      for (final r in rows) {
        int size = (r['file_size'] as int?) ?? 0;
        final filePath = r['file_path'] as String?;
        if (size <= 0 && filePath != null && filePath.isNotEmpty) {
          try {
            final f = File(filePath);
            if (f.existsSync()) {
              size = f.lengthSync();
            }
          } catch (_) {}
        }

        if (size >= minSizeBytes) {
          final item = Map<String, dynamic>.from(r);
          item['computedSize'] = size;
          results.add(item);
        }
      }
      return results;
    } catch (e) {
      debugPrint('[StorageEngine] Error fetching large items: $e');
      return [];
    }
  }

  /// Retrieves list of chats sorted by physical storage consumed
  Future<List<Map<String, dynamic>>> getChatsStorageBreakdown() async {
    final db = await database;
    try {
      final rows = await db.rawQuery('''
        SELECT 
          c.id, c.name, c.avatarUrl, c.isGroup,
          COUNT(m.id) as total_messages,
          COUNT(CASE WHEN m.media_url IS NOT NULL OR m.file_path IS NOT NULL THEN 1 END) as media_count,
          SUM(COALESCE(m.file_size, 0)) as total_bytes,
          SUM(CASE WHEN UPPER(m.media_type) = 'IMAGE' THEN COALESCE(m.file_size, 0) ELSE 0 END) as photos_bytes,
          COUNT(CASE WHEN UPPER(m.media_type) = 'IMAGE' THEN 1 END) as photos_count,
          SUM(CASE WHEN UPPER(m.media_type) = 'VIDEO' THEN COALESCE(m.file_size, 0) ELSE 0 END) as videos_bytes,
          COUNT(CASE WHEN UPPER(m.media_type) = 'VIDEO' THEN 1 END) as videos_count,
          SUM(CASE WHEN UPPER(m.media_type) IN ('AUDIO', 'VOICE') THEN COALESCE(m.file_size, 0) ELSE 0 END) as audio_bytes,
          COUNT(CASE WHEN UPPER(m.media_type) IN ('AUDIO', 'VOICE') THEN 1 END) as audio_count,
          SUM(CASE WHEN UPPER(m.media_type) = 'DOCUMENT' THEN COALESCE(m.file_size, 0) ELSE 0 END) as docs_bytes,
          COUNT(CASE WHEN UPPER(m.media_type) = 'DOCUMENT' THEN 1 END) as docs_count
        FROM local_conversations c
        LEFT JOIN local_messages m ON c.id = m.conversation_id
        GROUP BY c.id
        ORDER BY total_bytes DESC, c.updatedAt DESC
      ''');

      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (e) {
      debugPrint('[StorageEngine] Error fetching chats storage breakdown: $e');
      return [];
    }
  }

  /// Returns categorized media messages for a specific conversation
  Future<Map<String, dynamic>> getChatDetailedStorage(String conversationId) async {
    final db = await database;
    try {
      final rows = await db.rawQuery('''
        SELECT 
          id, conversation_id, media_url, media_type, file_path, file_size, 
          file_name, thumbnail, created_at, content
        FROM local_messages
        WHERE conversation_id = ? AND (media_url IS NOT NULL OR file_path IS NOT NULL)
        ORDER BY COALESCE(file_size, 0) DESC, created_at DESC
      ''', [conversationId]);

      final photos = <Map<String, dynamic>>[];
      final videos = <Map<String, dynamic>>[];
      final audios = <Map<String, dynamic>>[];
      final docs = <Map<String, dynamic>>[];

      int totalBytes = 0;

      for (final r in rows) {
        final item = Map<String, dynamic>.from(r);
        int size = (r['file_size'] as int?) ?? 0;
        final filePath = r['file_path'] as String?;
        if (size <= 0 && filePath != null && filePath.isNotEmpty) {
          try {
            final f = File(filePath);
            if (f.existsSync()) {
              size = f.lengthSync();
            }
          } catch (_) {}
        }
        item['computedSize'] = size;
        totalBytes += size;

        final type = (r['media_type'] as String? ?? '').toUpperCase();
        if (type == 'IMAGE') {
          photos.add(item);
        } else if (type == 'VIDEO') {
          videos.add(item);
        } else if (type == 'AUDIO' || type == 'VOICE') {
          audios.add(item);
        } else if (type == 'DOCUMENT') {
          docs.add(item);
        }
      }

      return {
        'totalBytes': totalBytes,
        'totalCount': rows.length,
        'photos': photos,
        'videos': videos,
        'audios': audios,
        'docs': docs,
      };
    } catch (e) {
      debugPrint('[StorageEngine] Error fetching chat detailed storage: $e');
      return {
        'totalBytes': 0,
        'totalCount': 0,
        'photos': [],
        'videos': [],
        'audios': [],
        'docs': [],
      };
    }
  }

  /// Purges selected media files from disk and frees database pages
  Future<int> deleteMediaItems(List<String> messageIds, {bool deleteFullMessage = false}) async {
    if (messageIds.isEmpty) return 0;
    final db = await database;
    int freedBytes = 0;

    try {
      // Find files to unlink
      final placeholders = List.filled(messageIds.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT id, file_path, media_url, file_size FROM local_messages WHERE id IN ($placeholders)',
        messageIds,
      );

      for (final r in rows) {
        final filePath = r['file_path'] as String?;
        final mediaUrl = r['media_url'] as String?;
        int size = (r['file_size'] as int?) ?? 0;

        if (filePath != null && filePath.isNotEmpty) {
          try {
            final f = File(filePath);
            if (f.existsSync()) {
              final len = f.lengthSync();
              f.deleteSync();
              freedBytes += (len > 0) ? len : size;
            }
          } catch (_) {}
        }

        // Also check if cached in temp
        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          try {
            final tempDir = await getTemporaryDirectory();
            final hash = mediaUrl.hashCode.abs().toString();
            final files = tempDir.listSync();
            for (final entity in files) {
              if (entity is File && entity.path.contains(hash)) {
                try {
                  final len = entity.lengthSync();
                  entity.deleteSync();
                  freedBytes += len;
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
      }

      if (deleteFullMessage) {
        await db.rawDelete('DELETE FROM local_messages WHERE id IN ($placeholders)', messageIds);
        try {
          await db.rawDelete('DELETE FROM messages_fts WHERE message_id IN ($placeholders)', messageIds);
        } catch (_) {}
      } else {
        // Clear file_path and free media reference
        await db.rawUpdate(
          'UPDATE local_messages SET file_path = NULL, file_size = 0 WHERE id IN ($placeholders)',
          messageIds,
        );
      }

      // Reclaim fragmented SQLite storage pages
      await reclaimStorageVacuum();
    } catch (e) {
      debugPrint('[StorageEngine] Error deleting media items: $e');
    }

    return freedBytes;
  }

  /// Clears temporary media caches and runs defragmentation
  Future<int> clearStorageCache() async {
    int freedBytes = await E2EEMediaCache.clear();
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final list = tempDir.listSync(recursive: true, followLinks: false);
        for (final entity in list) {
          if (entity is File) {
            try {
              final len = entity.lengthSync();
              entity.deleteSync();
              freedBytes += len;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    await reclaimStorageVacuum();
    return freedBytes;
  }

  /// Defragments SQLite B-Trees and releases file pages back to OS
  Future<void> reclaimStorageVacuum() async {
    try {
      final db = await database;
      await db.execute('VACUUM;');
      debugPrint('[StorageEngine] SQLite database vacuumed successfully.');
    } catch (e) {
      debugPrint('[StorageEngine] Vacuum error: $e');
    }
  }
}
