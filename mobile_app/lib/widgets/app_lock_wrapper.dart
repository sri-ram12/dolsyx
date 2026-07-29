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
  final TextEditingController _pinController = TextEditingController();
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockOnStartup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
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
      if (_isLocked) return;

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
        _isAuthenticating = false;
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access DOLSYX',
      );

      if (authenticated) {
        if (mounted) {
          setState(() {
            _isLocked = false;
            _errorText = '';
            _pinController.clear();
          });
        }
        _pausedTime = null;
      }
    } catch (_) {
      // Authentication error — user can still use PIN
    } finally {
      _isAuthenticating = false;
    }
  }

  Future<void> _verifyPin(String val) async {
    if (val.length == 4) {
      // Capture FocusScope before async gap to avoid BuildContext error
      final focusScope = FocusScope.of(context);
      
      final prefs = await SharedPreferences.getInstance();
      final savedPin = prefs.getString('app_lock_pin');
      
      // Force keyboard to dismiss immediately
      focusScope.unfocus();
      
      if (savedPin != null && savedPin.isNotEmpty && savedPin == val) {
        if (mounted) {
          setState(() {
            _isLocked = false;
            _errorText = '';
            _pinController.clear();
          });
        }
        _pausedTime = null;
      } else {
        if (mounted) {
          setState(() {
            _errorText = 'Incorrect PIN. Try again.';
            _pinController.clear();
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (_isLocked)
            Positioned.fill(
              child: Scaffold(
                backgroundColor: AppTheme.backgroundColor,
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Lock Icon
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.lock_rounded, size: 64, color: AppTheme.primaryColor),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'DOLSYX is Locked',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter PIN or use fingerprint to unlock',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 40),

                          // PIN Entry — always visible
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _errorText.isNotEmpty ? Colors.red : AppTheme.primaryColor.withValues(alpha: 0.3),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                            child: TextField(
                              controller: _pinController,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              obscureText: true,
                              autofocus: true,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                letterSpacing: 20,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                hintText: '• • • •',
                                hintStyle: TextStyle(
                                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                                  letterSpacing: 12,
                                  fontSize: 20,
                                ),
                                counterText: '',
                                border: InputBorder.none,
                              ),
                              onChanged: _verifyPin,
                            ),
                          ),

                          if (_errorText.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              _errorText,
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ],

                          const SizedBox(height: 32),

                          // Fingerprint button — always shown so user can tap to trigger biometrics
                          OutlinedButton.icon(
                            onPressed: _authenticate,
                            icon: Icon(Icons.fingerprint, color: AppTheme.primaryColor),
                            label: Text(
                              'Use Fingerprint',
                              style: TextStyle(color: AppTheme.primaryColor),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppTheme.primaryColor),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
