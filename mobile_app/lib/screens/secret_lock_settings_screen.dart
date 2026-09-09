import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class SecretLockSettingsScreen extends StatefulWidget {
  const SecretLockSettingsScreen({super.key});

  @override
  State<SecretLockSettingsScreen> createState() => _SecretLockSettingsScreenState();
}

class _SecretLockSettingsScreenState extends State<SecretLockSettingsScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _hideLockedChats = false;
  bool _isLoading = true;
  String? _currentSavedCode;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentSavedCode = prefs.getString('secret_chat_code') ?? '';
      _codeController.text = _currentSavedCode ?? '';
      _hideLockedChats = prefs.getBool('hide_locked_chats') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final newCode = _codeController.text.trim();
    if (newCode.isEmpty && _hideLockedChats) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a secret code to hide locked chats.')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('secret_chat_code', newCode);
    await prefs.setBool('hide_locked_chats', _hideLockedChats);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Secret code and lock settings updated!')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B141A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00A884))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B141A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Secret code',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A secret code lets you find locked chats in the search bar and open them on linked devices.',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 28),

            // WhatsApp styled Green outlined input field (frame_0149s.jpg)
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Secret code',
                labelStyle: const TextStyle(color: Color(0xFF00A884), fontSize: 14),
                hintText: 'Enter word or emoji (e.g. 🦋)',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00A884), width: 1.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00A884), width: 2.2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            const SizedBox(height: 28),

            // Hide Locked Chats switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFF00A884),
              title: const Text(
                'Hide locked chats',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Locked chats won\'t show in your chat list. To see them, enter your secret code into the search bar.',
                style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.3),
              ),
              value: _hideLockedChats,
              onChanged: (val) {
                setState(() => _hideLockedChats = val);
              },
            ),

            const Spacer(),

            // WhatsApp Big Green "Done" button (frame_0149s.jpg)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A884),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
