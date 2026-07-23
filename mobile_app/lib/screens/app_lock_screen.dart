import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _isAppLockEnabled = false;
  String _lockTimeout = 'Immediately';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Lock'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Unlock with biometrics', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: const Text('When enabled, you\'ll need to use fingerprint or face recognition to open DOLSYX.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: _isAppLockEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {
              setState(() {
                _isAppLockEnabled = val;
              });
            },
          ),
          if (_isAppLockEnabled) ...[
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Automatically lock', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
            ),
            RadioListTile<String>(
              title: const Text('Immediately', style: TextStyle(color: AppTheme.textPrimary)),
              value: 'Immediately',
              groupValue: _lockTimeout,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) => setState(() => _lockTimeout = val!),
            ),
            RadioListTile<String>(
              title: const Text('After 5 minutes', style: TextStyle(color: AppTheme.textPrimary)),
              value: 'After 5 minutes',
              groupValue: _lockTimeout,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) => setState(() => _lockTimeout = val!),
            ),
            RadioListTile<String>(
              title: const Text('After 10 minutes', style: TextStyle(color: AppTheme.textPrimary)),
              value: 'After 10 minutes',
              groupValue: _lockTimeout,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) => setState(() => _lockTimeout = val!),
            ),
          ]
        ],
      ),
    );
  }
}
