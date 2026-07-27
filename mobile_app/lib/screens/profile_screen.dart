import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'blocked_users_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/color_avatar.dart';
import '../widgets/full_screen_image_view.dart';
import 'my_qr_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      if (user['bio'] != null) _bioController.text = user['bio'];
      if (user['username'] != null) _usernameController.text = user['username'];
    }
  }

  @override
  void dispose() {
    _bioController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _updateAvatar() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      
      if (pickedFile != null) {
        setState(() => _isLoading = true);
        final uploadResponse = await _apiService.uploadMedia(pickedFile.path);
        
        if (uploadResponse != null && uploadResponse['fileUrl'] != null) {
          final updatedUser = await _apiService.updateProfile(
            avatarUrl: uploadResponse['fileUrl']
          );
          if (updatedUser != null) {
            if (mounted) Provider.of<AuthProvider>(context, listen: false).updateUser(updatedUser);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated successfully!')));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update avatar')));
          }
        }
      }
    } catch (e) {
      print('Avatar update error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    final updatedUser = await _apiService.updateProfile(
      bio: _bioController.text, 
      username: _usernameController.text,
    ); 
    if (mounted) {
      setState(() => _isLoading = false);
      if (updatedUser != null) {
        Provider.of<AuthProvider>(context, listen: false).updateUser(updatedUser);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update profile')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user ?? {};
    final avatarUrl = user['avatarUrl'];
    final username = user['username'] ?? 'User';
    final email = user['email'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (avatarUrl != null) {
                            String fullUrl = avatarUrl.startsWith('http') 
                                ? avatarUrl 
                                : 'https://dolsyx-app.onrender.com$avatarUrl';
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullScreenImageView(imageUrl: fullUrl),
                              ),
                            );
                          }
                        },
                        child: avatarUrl == null 
                            ? ColorAvatar(name: username, radius: 60, fontSize: 40)
                            : CircleAvatar(
                                radius: 60,
                                backgroundColor: AppTheme.backgroundColor,
                                backgroundImage: avatarUrl.startsWith('http')
                                    ? NetworkImage(avatarUrl)
                                    : NetworkImage('https://dolsyx-app.onrender.com$avatarUrl'),
                              ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _updateAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    email,
                    style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _bioController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'Write something about yourself...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _updateProfile,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Save Profile'),
                  ),
                  const SizedBox(height: 48),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, child) {
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    tileColor: AppTheme.surfaceColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: Icon(Icons.qr_code, color: AppTheme.primaryColor),
                    title: Text('My QR Code', style: TextStyle(color: AppTheme.textPrimary)),
                    trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyQrScreen()));
                    },
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    tileColor: AppTheme.surfaceColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.block, color: Colors.redAccent),
                    title: Text('Blocked Users', style: TextStyle(color: AppTheme.textPrimary)),
                    trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedUsersScreen()));
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
