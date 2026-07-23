import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAppLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
      _lockTimeout = prefs.getString('app_lock_timeout') ?? 'Immediately';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', _isAppLockEnabled);
    await prefs.setString('app_lock_timeout', _lockTimeout);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('App Lock'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: Text('Unlock with biometrics', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('When enabled, you\'ll need to use fingerprint or face recognition to open DOLSYX.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: _isAppLockEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {
              setState(() {
                _isAppLockEnabled = val;
              });
              _saveSettings();
            },
          ),
          if (_isAppLockEnabled) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Automatically lock', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
            ),
            RadioListTile<String>(
              title: Text('Immediately', style: TextStyle(color: AppTheme.textPrimary)),
              value: 'Immediately',
              groupValue: _lockTimeout,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) {
                setState(() => _lockTimeout = val!);
                _saveSettings();
              },
            ),
            RadioListTile<String>(
              title: Text('After 5 minutes', style: TextStyle(color: AppTheme.textPrimary)),
              value: 'After 5 minutes',
              groupValue: _lockTimeout,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) {
                setState(() => _lockTimeout = val!);
                _saveSettings();
              },
            ),
            RadioListTile<String>(
              title: Text('After 10 minutes', style: TextStyle(color: AppTheme.textPrimary)),
              value: 'After 10 minutes',
              groupValue: _lockTimeout,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) {
                setState(() => _lockTimeout = val!);
                _saveSettings();
              },
            ),
          ]
        ],
      ),
    );
  }
}
