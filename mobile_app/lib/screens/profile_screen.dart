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
  final _usernameFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      if (user['bio'] != null) _bioController.text = user['bio'].toString();
      if (user['username'] != null) _usernameController.text = user['username'].toString();
    }
    _refreshOwnProfile();
  }

  Future<void> _refreshOwnProfile() async {
    try {
      final fresh = await _apiService.getProfile();
      if (fresh != null && mounted) {
        Provider.of<AuthProvider>(context, listen: false).updateUser(fresh);
        if (!_isEditing) {
          _usernameController.text = (fresh['username'] ?? '').toString();
          _bioController.text = (fresh['bio'] ?? '').toString();
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _bioController.dispose();
    _usernameController.dispose();
    _usernameFocusNode.dispose();
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
            if (mounted) {
              Provider.of<AuthProvider>(context, listen: false).updateUser(updatedUser);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated successfully!')));
            }
          } else if (mounted) {
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

  Future<void> _removeAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Remove Profile Photo?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Your profile picture will be removed and replaced with your default avatar.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      final updatedUser = await _apiService.updateProfile(removeAvatar: true);
      if (mounted) {
        if (updatedUser != null) {
          Provider.of<AuthProvider>(context, listen: false).updateUser(updatedUser);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture removed')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove profile picture')));
        }
      }
    } catch (e) {
      print('Remove avatar error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    final updatedUser = await _apiService.updateProfile(
      bio: _bioController.text.trim(),
      username: _usernameController.text.trim(),
    ); 
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isEditing = false;
      });
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
    final hasAvatar = avatarUrl != null && avatarUrl.toString().trim().isNotEmpty;
    final username = user['username'] ?? 'User';
    final email = user['email'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          TextButton.icon(
            onPressed: _isLoading
                ? null
                : () {
                    if (_isEditing) {
                      _updateProfile();
                    } else {
                      setState(() => _isEditing = true);
                      Future.delayed(const Duration(milliseconds: 50), () {
                        if (mounted) _usernameFocusNode.requestFocus();
                      });
                    }
                  },
            icon: Icon(
              _isEditing ? Icons.check_rounded : Icons.edit_rounded,
              color: AppTheme.primaryColor,
              size: 18,
            ),
            label: Text(
              _isEditing ? 'Save' : 'Edit Profile',
              style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
            ),
          ),
          if (hasAvatar)
            IconButton(
              tooltip: 'Remove Profile Photo',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _isLoading ? null : _removeAvatar,
            ),
        ],
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
                          if (hasAvatar) {
                            String fullUrl = avatarUrl.startsWith('http') 
                                ? avatarUrl 
                                : 'https://dolsyx.vercel.app$avatarUrl';
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullScreenImageView(imageUrl: fullUrl),
                              ),
                            );
                          }
                        },
                        child: !hasAvatar
                            ? ColorAvatar(name: username, radius: 60, fontSize: 40)
                            : CircleAvatar(
                                radius: 60,
                                backgroundColor: AppTheme.backgroundColor,
                                backgroundImage: avatarUrl.startsWith('http')
                                    ? NetworkImage(avatarUrl)
                                    : NetworkImage('https://dolsyx.vercel.app$avatarUrl'),
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
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Top Profile Action Row: Edit Profile / Photo + Remove Profile Photo
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          if (!_isEditing) {
                            setState(() => _isEditing = true);
                            Future.delayed(const Duration(milliseconds: 50), () {
                              if (mounted) _usernameFocusNode.requestFocus();
                            });
                          } else {
                            _updateAvatar();
                          }
                        },
                        icon: Icon(_isEditing ? Icons.photo_camera_outlined : Icons.edit_outlined, size: 18),
                        label: Text(_isEditing ? 'Change Photo' : 'Edit Profile'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: hasAvatar ? _removeAvatar : null,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove Photo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          disabledForegroundColor: AppTheme.textSecondary.withOpacity(0.45),
                          side: BorderSide(
                            color: hasAvatar
                                ? Colors.redAccent.withOpacity(0.6)
                                : AppTheme.textSecondary.withOpacity(0.2),
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _usernameController,
                    focusNode: _usernameFocusNode,
                    onTap: () {
                      if (!_isEditing) setState(() => _isEditing = true);
                    },
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
                  const SizedBox(height: 24),
                  TextField(
                    controller: _bioController,
                    maxLines: 3,
                    onTap: () {
                      if (!_isEditing) setState(() => _isEditing = true);
                    },
                    decoration: const InputDecoration(
                      labelText: 'About',
                      hintText: 'Write something about yourself...',
                      prefixIcon: Icon(Icons.info_outline),
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
