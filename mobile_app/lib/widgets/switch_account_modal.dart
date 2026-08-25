import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/color_avatar.dart';
import '../screens/login_screen.dart';

class SwitchAccountModal extends StatefulWidget {
  const SwitchAccountModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const SwitchAccountModal(),
    );
  }

  @override
  State<SwitchAccountModal> createState() => _SwitchAccountModalState();
}

class _SwitchAccountModalState extends State<SwitchAccountModal> {
  List<Map<String, dynamic>> _savedAccounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final accounts = await authProvider.getSavedAccounts();
    if (mounted) {
      setState(() {
        _savedAccounts = accounts;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = (authProvider.user?['id'] ?? authProvider.user?['_id'])?.toString();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Switch account',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryColor),
                ),
              )
            else if (_savedAccounts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No other saved accounts on this device.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _savedAccounts.length,
                  separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final account = _savedAccounts[index];
                    final userId = (account['id'] ?? account['userData']?['id'])?.toString();
                    final isCurrent = userId == currentUserId;
                    final username = account['username'] ?? 'User';
                    final emailOrPhone = (account['email'] != null && account['email'].toString().isNotEmpty)
                        ? account['email']
                        : (account['phoneNumber'] ?? '');
                    final avatarUrl = account['avatarUrl'];

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: ColorAvatar(
                        name: username,
                        avatarUrl: avatarUrl,
                        radius: 22,
                      ),
                      title: Text(
                        username,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: emailOrPhone.toString().isNotEmpty
                          ? Text(
                              emailOrPhone,
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrent)
                            Icon(Icons.check_circle_rounded, color: AppTheme.primaryColor, size: 24)
                          else ...[
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () async {
                                if (userId != null) {
                                  await authProvider.removeSavedAccount(userId);
                                  _loadAccounts();
                                }
                              },
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios, color: AppTheme.textSecondary, size: 14),
                          ],
                        ],
                      ),
                      onTap: () async {
                        if (!isCurrent) {
                          Navigator.pop(context);
                          final success = await authProvider.switchAccount(account);
                          if (!success && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to switch account')),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white10),
            // Add Account Button
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add, color: AppTheme.primaryColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Add account',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
