import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class HelpSettingsScreen extends StatelessWidget {
  const HelpSettingsScreen({super.key});

  static const String privacyUrl = 'https://dolsyx-app.onrender.com/privacy';
  static const String termsUrl = 'https://dolsyx-app.onrender.com/terms';

  Future<void> _launch(BuildContext context, String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open $urlString')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.help_center_outlined, color: AppTheme.textSecondary),
            title: Text('Help Center', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text('Get help, view guides and FAQs', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () => _launch(context, privacyUrl),
          ),
          ListTile(
            leading: Icon(Icons.support_agent_rounded, color: AppTheme.textSecondary),
            title: Text('Contact Us', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text('Questions? Need technical help?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () => _launch(context, 'mailto:support@dolsyx.com?subject=DOLSYX%20Support%20Request'),
          ),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: AppTheme.textSecondary),
            title: Text('Terms & Privacy Policy', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text('Read our data protection & privacy guidelines', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () => _launch(context, privacyUrl),
          ),
          ListTile(
            leading: Icon(Icons.article_outlined, color: AppTheme.textSecondary),
            title: Text('Terms of Service', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text('User agreement & acceptable use policy', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () => _launch(context, termsUrl),
          ),
          const Divider(color: Colors.grey, height: 24),
          ListTile(
            leading: Icon(Icons.info_outline, color: AppTheme.textSecondary),
            title: Text('App Info', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text('DOLSYX v1.0.0 (Build 1)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'DOLSYX',
                applicationVersion: '1.0.0 (Build 1)',
                applicationIcon: Image.asset('assets/icon/app_icon.png', width: 48, height: 48, errorBuilder: (_, __, ___) => const Icon(Icons.chat_bubble, size: 48, color: Color(0xFF32CD32))),
                children: const [
                  SizedBox(height: 8),
                  Text('DOLSYX is a secure, end-to-end encrypted messaging, voice, and video communication platform.'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
