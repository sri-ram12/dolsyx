import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/broadcast_service.dart';
import '../services/api_service.dart';
import '../services/contact_service.dart';
import '../theme/app_theme.dart';

/// Phase 18 – Broadcast Lists Screen.
/// Users can create, view, and manage their broadcast lists.
/// A broadcast sends individual DMs to each recipient simultaneously.
class BroadcastListsScreen extends StatefulWidget {
  const BroadcastListsScreen({super.key});

  @override
  State<BroadcastListsScreen> createState() => _BroadcastListsScreenState();
}

class _BroadcastListsScreenState extends State<BroadcastListsScreen> {
  final BroadcastService _broadcastService = BroadcastService();
  List<Map<String, dynamic>> _broadcasts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBroadcasts();
  }

  Future<void> _loadBroadcasts() async {
    final lists = await _broadcastService.getBroadcastLists();
    if (mounted) {
      setState(() {
        _broadcasts = lists;
        _isLoading = false;
      });
    }
  }

  void _showCreateDialog() async {
    final nameController = TextEditingController();
    List<Map<String, dynamic>> contacts = [];
    List<String> selectedIds = [];

    // Fetch contacts
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
      final rawContacts = await ContactService.getContacts(token);
      contacts = rawContacts.map((c) => Map<String, dynamic>.from(c as Map)).toList();
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setBottomState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('New Broadcast List', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'List name',
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.backgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Select Recipients (${selectedIds.length} selected)', style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: contacts.isEmpty
                      ? Center(child: Text('No contacts found', style: TextStyle(color: AppTheme.textSecondary)))
                      : ListView.builder(
                          itemCount: contacts.length,
                          itemBuilder: (_, i) {
                            final c = contacts[i];
                            final id = (c['contact']?['id'] ?? c['id'] ?? c['_id'])?.toString() ?? '';
                            final name = (c['contact']?['username'] ?? c['username'] ?? 'User').toString();
                            final selected = selectedIds.contains(id);
                            return CheckboxListTile(
                              activeColor: AppTheme.primaryColor,
                              checkColor: Colors.white,
                              value: selected,
                              title: Text(name, style: TextStyle(color: AppTheme.textPrimary)),
                              onChanged: (v) {
                                setBottomState(() {
                                  if (v == true) {
                                    selectedIds.add(id);
                                  } else {
                                    selectedIds.remove(id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: selectedIds.isEmpty || nameController.text.trim().isEmpty
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            setState(() => _isLoading = true);
                            final result = await _broadcastService.createBroadcastList(
                              name: nameController.text.trim(),
                              recipientIds: selectedIds,
                            );
                            if (result != null && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Broadcast list "${nameController.text.trim()}" created!')),
                              );
                              _loadBroadcasts();
                            } else if (mounted) {
                              setState(() => _isLoading = false);
                            }
                          },
                    child: const Text('Create Broadcast List', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  void _openBroadcast(Map<String, dynamic> broadcast) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _BroadcastDetailSheet(
        broadcast: broadcast,
        broadcastService: _broadcastService,
        onSent: () => _loadBroadcasts(),
        onDeleted: () {
          setState(() => _broadcasts.removeWhere((b) => b['id'] == broadcast['id']));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Broadcast Lists', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline, color: AppTheme.textSecondary),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.surfaceColor,
                  title: Text('About Broadcasts', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                  content: Text(
                    'Broadcast lists let you send a message to multiple contacts at once. '
                    'Each recipient receives the message as a private one-to-one chat. '
                    'Replies come back to you individually — recipients cannot see each other.',
                    style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.campaign, color: Colors.white),
        label: const Text('New List', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: _showCreateDialog,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _broadcasts.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _broadcasts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final b = _broadcasts[index];
                    return _BroadcastTile(
                      broadcast: b,
                      onTap: () => _openBroadcast(b),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.campaign_outlined, size: 64, color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 20),
          Text('No broadcast lists yet', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Create a broadcast list to send messages\nto multiple contacts at once.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreateDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Create Broadcast List', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Broadcast List Tile ───────────────────────────────────────────────────────
class _BroadcastTile extends StatelessWidget {
  final Map<String, dynamic> broadcast;
  final VoidCallback onTap;

  const _BroadcastTile({required this.broadcast, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = broadcast['name'] ?? 'Broadcast List';
    final recipientCount = broadcast['recipientCount'] ?? 0;
    final lastMsg = broadcast['lastMessage'];
    final lastContent = lastMsg?['content'] as String? ?? (lastMsg != null ? 'Media' : 'No messages yet');

    return Material(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.campaign, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                      '$recipientCount recipient${recipientCount != 1 ? 's' : ''}',
                      style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastContent,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Broadcast Detail Bottom Sheet ─────────────────────────────────────────────
class _BroadcastDetailSheet extends StatefulWidget {
  final Map<String, dynamic> broadcast;
  final BroadcastService broadcastService;
  final VoidCallback onSent;
  final VoidCallback onDeleted;

  const _BroadcastDetailSheet({
    required this.broadcast,
    required this.broadcastService,
    required this.onSent,
    required this.onDeleted,
  });

  @override
  State<_BroadcastDetailSheet> createState() => _BroadcastDetailSheetState();
}

class _BroadcastDetailSheetState extends State<_BroadcastDetailSheet> {
  final TextEditingController _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);

    final success = await widget.broadcastService.sendBroadcast(
      broadcastId: widget.broadcast['id'],
      content: text,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (success) {
      _messageController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Broadcast sent to ${widget.broadcast['recipientCount']} recipient(s)!'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
      widget.onSent();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send broadcast')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.broadcast['name'] ?? 'Broadcast List';
    final count = widget.broadcast['recipientCount'] ?? 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20, left: 20, right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.campaign, color: AppTheme.primaryColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('$count recipient${count != 1 ? 's' : ''}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppTheme.surfaceColor,
                      title: Text('Delete "$name"?', style: TextStyle(color: AppTheme.textPrimary)),
                      content: Text('This will permanently delete this broadcast list.', style: TextStyle(color: AppTheme.textSecondary)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          child: const Text('Delete', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final ok = await widget.broadcastService.deleteBroadcastList(widget.broadcast['id']);
                    if (ok && mounted) {
                      Navigator.pop(context);
                      widget.onDeleted();
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          Text('Send Message to All Recipients', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _messageController,
            maxLines: 4,
            minLines: 2,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Type your broadcast message...',
              hintStyle: TextStyle(color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.backgroundColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, color: Colors.white),
              label: Text(_sending ? 'Sending...' : 'Send Broadcast', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
