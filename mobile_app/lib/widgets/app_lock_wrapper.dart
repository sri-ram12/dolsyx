import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class GlobalAppLockWrapper extends StatefulWidget {
  final Widget child;

  const GlobalAppLockWrapper({super.key, required this.child});

  @override
  State<GlobalAppLockWrapper> createState() => _GlobalAppLockWrapperState();
}

class _GlobalAppLockWrapperState extends State<GlobalAppLockWrapper> with WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isLocked = false;
  bool _isAuthenticating = false;
  DateTime? _pausedTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockOnStartup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLockOnStartup() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('app_lock_enabled') ?? false;
    if (isEnabled) {
      if (mounted) {
        setState(() {
          _isLocked = true;
        });
      }
      _authenticate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_isLocked) return; // Prevent re-triggering authentication if already locked

      if (_pausedTime != null) {
        final prefs = await SharedPreferences.getInstance();
        final isEnabled = prefs.getBool('app_lock_enabled') ?? false;
        if (!isEnabled) return;

        final timeoutString = prefs.getString('app_lock_timeout') ?? 'Immediately';
        int timeoutMinutes = 0;
        if (timeoutString == 'After 5 minutes') timeoutMinutes = 5;
        if (timeoutString == 'After 10 minutes') timeoutMinutes = 10;

        final difference = DateTime.now().difference(_pausedTime!);
        if (difference.inMinutes >= timeoutMinutes) {
          if (mounted) {
            setState(() {
              _isLocked = true;
            });
          }
          _authenticate();
        }
      }
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    
    try {
      _isAuthenticating = true;
      final bool canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (!canAuthenticate) {
        // Fallback if device doesn't support biometrics
        if (mounted) {
          setState(() {
            _isLocked = false;
          });
        }
        _isAuthenticating = false;
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access DOLSYX',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        if (mounted) {
          setState(() {
            _isLocked = false;
          });
        }
        _pausedTime = null; // Clear the paused time so it doesn't immediately relock
      }
    } catch (e) {
      print('Authentication error: $e');
    } finally {
      _isAuthenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 80, color: AppTheme.primaryColor),
                const SizedBox(height: 20),
                Text('DOLSYX is locked', style: TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _authenticate,
                  child: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
