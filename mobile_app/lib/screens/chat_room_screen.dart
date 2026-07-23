import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'call_screen.dart';
import '../widgets/message_bubble.dart';

class ChatRoomScreen extends StatefulWidget {
  final String conversationId;
  final String chatName;
  final String? avatarUrl;
  final String? remoteUserId;

  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.chatName,
    this.avatarUrl,
    this.remoteUserId,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.joinConversation(widget.conversationId);
    authProvider.socketService.onMessageReceived(_handleIncomingMessage);
  }

  @override
  void dispose() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.offMessageReceived(_handleIncomingMessage);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleIncomingMessage(dynamic data) {
    if (mounted) {
      try {
        setState(() {
          _messages.add(Message.fromJson(data['message']));
        });
        _scrollToBottom();
      } catch (e) {
        print('Error parsing incoming message: $e');
      }
    }
  }

  Future<void> _fetchMessages() async {
    try {
      final token = await ApiService().getToken();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats/${widget.conversationId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _messages = data.map((json) => Message.fromJson(json)).toList();
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      print('Error fetching messages: $e');
      setState(() => _isLoading = false);
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.socketService.socket?.connected != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Socket disconnected. Cannot send message.')),
      );
      return;
    }

    authProvider.socketService.sendMessage(widget.conversationId, text);
    _messageController.clear();
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source, imageQuality: 70);
      if (!mounted) return;
      if (pickedFile != null) {
        _uploadAndSendMedia(File(pickedFile.path), 'IMAGE');
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickFile() async {
    Navigator.pop(context);
    try {
      final result = await FilePicker.pickFiles();
      if (!mounted) return;
      if (result != null && result.files.single.path != null) {
        _uploadAndSendMedia(File(result.files.single.path!), 'FILE');
      }
    } catch (e) {
      print('Error picking file: $e');
    }
  }

  Future<void> _uploadAndSendMedia(File file, String mediaType) async {
    setState(() => _isLoading = true);
    try {
      final apiService = ApiService();
      final response = await apiService.uploadMedia(file.path);
      
      if (response != null && response['fileUrl'] != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.socketService.sendMessage(
          widget.conversationId, 
          '', 
          mediaUrl: response['fileUrl'], 
          mediaType: mediaType
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed.')));
      }
    } catch (e) {
      print('Upload error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppTheme.primaryColor),
                title: const Text('Camera', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () => _pickImage(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo, color: AppTheme.primaryColor),
                title: const Text('Gallery', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file, color: AppTheme.primaryColor),
                title: const Text('Document', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: _pickFile,
              ),
            ],
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthProvider>(context).user;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.surfaceColor,
              backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.startsWith('http')
                  ? NetworkImage(widget.avatarUrl!)
                  : null,
              child: (widget.avatarUrl == null || !widget.avatarUrl!.startsWith('http'))
                  ? const Icon(Icons.person, size: 20, color: AppTheme.textSecondary)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(widget.chatName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          if (widget.remoteUserId != null) ...[
            IconButton(
              icon: const Icon(Icons.call),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      remoteUserId: widget.remoteUserId!,
                      remoteUserName: widget.chatName,
                      isVideo: false,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.videocam),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      remoteUserId: widget.remoteUserId!,
                      remoteUserName: widget.chatName,
                      isVideo: true,
                    ),
                  ),
                );
              },
            ),
          ]
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMe = currentUser != null && message.senderId == currentUser['id'];
                      return MessageBubble(message: message, isMe: isMe);
                    },
                  ),
          ),
          if (_isLoading && _messages.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(color: AppTheme.primaryColor),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppTheme.surfaceColor,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: AppTheme.primaryColor),
                  onPressed: _showAttachmentOptions,
                ),
                IconButton(
                  icon: const Icon(Icons.camera_alt, color: AppTheme.primaryColor),
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primaryColor,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
