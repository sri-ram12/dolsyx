import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
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
  String _pin = '';
  final TextEditingController _pinController = TextEditingController();

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
      _pin = prefs.getString('app_lock_pin') ?? '';
      _pinController.text = _pin;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', _isAppLockEnabled);
    await prefs.setString('app_lock_timeout', _lockTimeout);
    await prefs.setString('app_lock_pin', _pin);
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
            onChanged: (val) async {
              final localAuth = LocalAuthentication();
              final isSupported = await localAuth.isDeviceSupported();
              if (!isSupported) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please set up a screen lock (PIN, Pattern, or Fingerprint) in your device settings first.')),
                );
                return;
              }
              
              final authenticated = await localAuth.authenticate(
                localizedReason: val ? 'Please authenticate to enable App Lock' : 'Please authenticate to disable App Lock',
              );

              if (authenticated) {
                setState(() {
                  _isAppLockEnabled = val;
                });
                _saveSettings();
              }
            },
          ),
          if (_isAppLockEnabled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: '4-Digit PIN (Fallback)',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.textSecondary)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryColor)),
                ),
                onChanged: (val) {
                  setState(() => _pin = val);
                  _saveSettings();
                },
              ),
            ),
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
