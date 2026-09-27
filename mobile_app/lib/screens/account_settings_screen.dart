import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'two_factor_auth_screen.dart';
import 'two_step_verification_screen.dart';
import 'change_password_screen.dart';
import 'app_lock_screen.dart';
import 'signup_screen.dart';
import 'login_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _isDeleting = false;

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text('Delete Account?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Deleting your account will:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            SizedBox(height: 8),
            Text('• Delete your account info and profile photo', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
            Text('• Erase your End-to-End Encryption keys', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
            Text('• Delete all message histories and media refs', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
            Text('• Remove you from all DOLSYX groups', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
            SizedBox(height: 12),
            Text(
              'This action is PERMANENT and cannot be reversed.',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _performAccountDeletion();
            },
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _performAccountDeletion() async {
    setState(() => _isDeleting = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final success = await authProvider.deleteAccountAndWipeLocalData();
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your DOLSYX account and data have been permanently deleted.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SignupScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete account. Please check your connection.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.logout_rounded, color: Colors.orangeAccent, size: 28),
            SizedBox(width: 10),
            Text('Log out of DOLSYX?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out? You will need to sign in again to receive messages.',
          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: _isDeleting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.redAccent),
                  SizedBox(height: 16),
                  Text('Deleting account and wiping data...', style: TextStyle(color: Colors.white)),
                ],
              ),
            )
          : ListView(
              children: [
                const SizedBox(height: 8),
                _buildTile(
                  icon: Icons.shield_outlined,
                  title: 'Security Notifications',
                  subtitle: 'Show security notifications when encryption keys change',
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: AppTheme.surfaceColor,
                        title: const Text('End-to-End Encryption', style: TextStyle(color: Colors.white)),
                        content: const Text(
                          'Your chats and calls are secured with End-to-End Encryption. Only you and the person you are communicating with can read or listen to them.',
                          style: TextStyle(color: Color(0xFFCBD5E1)),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
                        ],
                      ),
                    );
                  },
                ),
                _buildTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Two-Step Verification',
                  subtitle: 'For extra security, require a PIN when registering your account',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TwoStepVerificationScreen(mode: TwoStepMode.settings)));
                  },
                ),
                _buildTile(
                  icon: Icons.lock_reset_rounded,
                  title: 'Password',
                  subtitle: 'Change or set your account password for strict email login safety',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
                  },
                ),
                _buildTile(
                  icon: Icons.fingerprint,
                  title: 'Passkeys & App Lock',
                  subtitle: 'Unlock DOLSYX with fingerprint, face ID, or device PIN',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AppLockScreen()));
                  },
                ),
                const Divider(color: Colors.grey, height: 24),
                _buildTile(
                  icon: Icons.logout_rounded,
                  iconColor: Colors.orangeAccent,
                  title: 'Log out',
                  subtitle: 'Sign out of your account on this device',
                  textColor: Colors.orangeAccent,
                  onTap: _confirmLogout,
                ),
                _buildTile(
                  icon: Icons.delete_forever_rounded,
                  iconColor: Colors.redAccent,
                  title: 'Delete my account',
                  subtitle: 'Permanently erase all messages, contacts, and personal data',
                  textColor: Colors.redAccent,
                  onTap: _confirmDeleteAccount,
                ),
              ],
            ),
    );
  }


  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppTheme.textSecondary),
      title: Text(title, style: TextStyle(color: textColor ?? AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      onTap: onTap,
    );
  }
}
