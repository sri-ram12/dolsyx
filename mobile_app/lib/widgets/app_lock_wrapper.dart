import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class GlobalAppLockWrapper extends StatefulWidget {
  final Widget child;

  static bool isMediaPickerActive = false;

  const GlobalAppLockWrapper({super.key, required this.child});

  @override
  State<GlobalAppLockWrapper> createState() => _GlobalAppLockWrapperState();
}

class _GlobalAppLockWrapperState extends State<GlobalAppLockWrapper> with WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isLocked = false;
  bool _isAuthenticating = false;
  DateTime? _pausedTime;
  String _pin = '';        // entered digits
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
    super.dispose();
  }

  Future<void> _checkLockOnStartup() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('app_lock_enabled') ?? false;
    if (isEnabled && mounted) {
      setState(() => _isLocked = true);
      _authenticate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (GlobalAppLockWrapper.isMediaPickerActive) return;
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
          if (mounted) setState(() => _isLocked = true);
          _authenticate();
        }
      }
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    try {
      _isAuthenticating = true;
      final canAuthenticate = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canAuthenticate) return;
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access DOLSYX',
      );
      if (authenticated && mounted) {
        setState(() {
          _isLocked = false;
          _pin = '';
          _errorText = '';
        });
        _pausedTime = null;
      }
    } catch (_) {
      // user can still use PIN
    } finally {
      _isAuthenticating = false;
    }
  }

  void _onDigitTap(String digit) {
    if (_pin.length >= 4) return;
    final newPin = _pin + digit;
    setState(() {
      _pin = newPin;
      _errorText = '';
    });
    if (newPin.length == 4) {
      _verifyPin(newPin);
    }
  }

  void _onDeleteTap() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = '';
    });
  }

  Future<void> _verifyPin(String enteredPin) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('app_lock_pin') ?? '';
    if (savedPin.isNotEmpty && savedPin == enteredPin) {
      if (mounted) {
        setState(() {
          _isLocked = false;
          _pin = '';
          _errorText = '';
        });
      }
      _pausedTime = null;
    } else {
      if (mounted) {
        setState(() {
          _pin = '';
          _errorText = 'Incorrect PIN. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isLocked)
          Positioned.fill(
            child: Material(
              color: AppTheme.backgroundColor,
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your 4-digit PIN',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 36),

                    // PIN dots indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length ? AppTheme.primaryColor : AppTheme.surfaceColor,
                          border: Border.all(color: AppTheme.primaryColor, width: 2),
                        ),
                      )),
                    ),

                    if (_errorText.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(_errorText, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                    const SizedBox(height: 36),

                    // Custom numpad
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        children: [
                          for (final row in [['1','2','3'], ['4','5','6'], ['7','8','9'], ['','0','del']])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: row.map((label) {
                                  if (label.isEmpty) return const SizedBox(width: 72, height: 72);
                                  return GestureDetector(
                                    onTap: () => label == 'del' ? _onDeleteTap() : _onDigitTap(label),
                                    child: Container(
                                      width: 72, height: 72,
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: label == 'del'
                                          ? Icon(Icons.backspace_outlined, color: AppTheme.textPrimary, size: 24)
                                          : Text(label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w500)),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _authenticate,
                      icon: Icon(Icons.fingerprint, color: AppTheme.primaryColor),
                      label: Text('Use Fingerprint', style: TextStyle(color: AppTheme.primaryColor)),
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
      ],
    );
  }
}
