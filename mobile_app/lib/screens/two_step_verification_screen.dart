import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'chat_list_screen.dart';

enum TwoStepMode {
  loginChallenge,
  setup,
  settings,
}

class TwoStepVerificationScreen extends StatefulWidget {
  final TwoStepMode mode;
  final String? email;
  final bool hasPendingReset;

  const TwoStepVerificationScreen({
    super.key,
    required this.mode,
    this.email,
    this.hasPendingReset = false,
  });

  @override
  State<TwoStepVerificationScreen> createState() => _TwoStepVerificationScreenState();
}

class _TwoStepVerificationScreenState extends State<TwoStepVerificationScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  int? _attemptsRemaining;
  int? _lockoutRemainingMinutes;

  // Setup mode step (0: Enter PIN, 1: Confirm PIN)
  int _setupStep = 0;
  String _firstEnteredPin = '';

  // Settings mode status
  bool _isTwoStepEnabled = false;
  bool _hasPendingCooldown = false;
  Map<String, dynamic>? _cooldownData;

  @override
  void initState() {
    super.initState();
    if (widget.mode == TwoStepMode.settings) {
      _loadSettingsStatus();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    // Zero out sensitive PIN buffers from heap memory before object destruction
    _pinController.clear();
    _confirmPinController.clear();
    _firstEnteredPin = '';
    _pinController.dispose();
    _confirmPinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsStatus() async {
    setState(() => _isLoading = true);
    final status = await _apiService.getTwoStepStatus();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isTwoStepEnabled = status['enabled'] == true;
        _hasPendingCooldown = status['hasPendingReset'] == true;
        _cooldownData = status['cooldown'] as Map<String, dynamic>?;
      });
    }
  }

  Future<void> _handleLoginVerify() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _errorMessage = 'Please enter all 6 digits.');
      return;
    }

    final email = widget.email ?? Provider.of<AuthProvider>(context, listen: false).pendingTwoStepEmail;
    if (email == null || email.isEmpty) {
      setState(() => _errorMessage = 'Missing email context. Please log in again.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final result = await authProvider.completeTwoStepLogin(email: email, pin: pin);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const ChatListScreen()),
        (route) => false,
      );
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Incorrect PIN.';
        _attemptsRemaining = result['attemptsRemaining'];
        _lockoutRemainingMinutes = result['lockoutRemainingMinutes'];
        _pinController.clear();
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _handleSetupNext() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _errorMessage = 'Please enter a 6-digit PIN.');
      return;
    }

    if (_setupStep == 0) {
      setState(() {
        _firstEnteredPin = pin;
        _setupStep = 1;
        _errorMessage = null;
        _pinController.clear();
      });
      _focusNode.requestFocus();
    } else {
      if (pin != _firstEnteredPin) {
        setState(() {
          _errorMessage = 'PINs do not match. Please try again.';
          _pinController.clear();
        });
        _focusNode.requestFocus();
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await _apiService.enableTwoStep(pin);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Two-Step Verification enabled successfully!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        Navigator.pop(context, true);
      } else {
        setState(() => _errorMessage = result['message']);
      }
    }
  }

  void _showForgotPinDialog() async {
    final email = widget.email ?? Provider.of<AuthProvider>(context, listen: false).pendingTwoStepEmail;
    if (email == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: Color(0xFFE53935), size: 28),
            const SizedBox(width: 10),
            Text(
              'Forgot PIN Protection',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To protect your account from friends or unauthorized individuals who have access to your email address, PIN reset requires a mandatory 7-day security cooldown.',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFB74D)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFE65100), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'During this 7-day cooldown, your account cannot be hijacked.',
                      style: TextStyle(color: Color(0xFFE65100), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
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
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final resp = await _apiService.requestForgotPin(email);
              if (!mounted) return;
              setState(() => _isLoading = false);

              showDialog(
                context: context,
                builder: (alertCtx) => AlertDialog(
                  backgroundColor: AppTheme.surfaceColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text(
                    resp['resetCompleted'] == true ? 'Reset Ready' : '7-Day Cooldown Active',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                  ),
                  content: Text(
                    resp['message'] ?? 'Status updated.',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.4),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(alertCtx),
                      child: Text('OK', style: TextStyle(color: AppTheme.primaryColor)),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Check / Request Cooldown', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showDisableDialog() async {
    final pinDialogController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Disable Two-Step Verification', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter your current 6-digit PIN to turn off Two-Step Verification.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinDialogController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Current 6-digit PIN',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            onPressed: () async {
              final pin = pinDialogController.text.trim();
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final res = await _apiService.disableTwoStep(pin);
              if (!mounted) return;
              setState(() => _isLoading = false);
              if (res['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Two-Step Verification disabled')),
                );
                _loadSettingsStatus();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(res['message'] ?? 'Failed to disable')),
                );
              }
            },
            child: const Text('Disable', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildPinBoxes() {
    final currentText = _pinController.text;
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: Container(
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            final isFilled = index < currentText.length;
            final isCurrent = index == currentText.length && _focusNode.hasFocus;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                color: isFilled
                    ? AppTheme.primaryColor.withOpacity(0.08)
                    : AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCurrent
                      ? AppTheme.primaryColor
                      : isFilled
                          ? AppTheme.primaryColor.withOpacity(0.5)
                          : Colors.grey.withOpacity(0.3),
                  width: isCurrent ? 2.0 : 1.2,
                ),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              alignment: Alignment.center,
              child: isFilled
                  ? const Text(
                      '•',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    )
                  : isCurrent
                      ? Container(
                          width: 2,
                          height: 22,
                          color: AppTheme.primaryColor,
                        )
                      : const SizedBox.shrink(),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == TwoStepMode.settings) {
      return _buildSettingsView();
    }
    return _buildPinInputView();
  }

  Widget _buildSettingsView() {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Two-Step Verification'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _isTwoStepEnabled
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFECEFF1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isTwoStepEnabled ? Icons.verified_user : Icons.lock_outline,
                        size: 44,
                        color: _isTwoStepEnabled
                            ? const Color(0xFF2E7D32)
                            : AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      _isTwoStepEnabled
                          ? 'Two-Step Verification is Active'
                          : 'Extra Account Defense',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _isTwoStepEnabled
                          ? 'Your account is fortified. Even if someone has access to your email, they cannot log into your Dolsyx account without your 6-digit secret PIN.'
                          : 'For maximum security, set a 6-digit PIN that is required whenever you log into Dolsyx. This completely blocks friends or unauthorized users with email access from hijacking your chats.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_hasPendingCooldown && _cooldownData != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFB300)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.timer, color: Color(0xFFF57F17)),
                              SizedBox(width: 8),
                              Text(
                                'Pending PIN Reset (7-Day Cooldown)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFF57F17),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'A PIN reset cooldown was requested. ${_cooldownData!['remainingDays']} days remaining.',
                            style: const TextStyle(color: Color(0xFF5D4037), fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              setState(() => _isLoading = true);
                              final res = await _apiService.cancelForgotPin();
                              if (!mounted) return;
                              setState(() => _isLoading = false);
                              if (res['success'] == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Pending reset cancelled successfully.')),
                                );
                                _loadSettingsStatus();
                              }
                            },
                            icon: const Icon(Icons.cancel, size: 18, color: Colors.white),
                            label: const Text('Cancel Reset Request', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_isTwoStepEnabled) ...[
                    Card(
                      elevation: 0,
                      color: AppTheme.surfaceColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.pin, color: Color(0xFF1976D2)),
                            title: const Text('Change PIN'),
                            subtitle: const Text('Update your 6-digit security PIN'),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () async {
                              final changed = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TwoStepVerificationScreen(
                                    mode: TwoStepMode.setup,
                                  ),
                                ),
                              );
                              if (changed == true) _loadSettingsStatus();
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.power_settings_new, color: Color(0xFFD32F2F)),
                            title: const Text('Turn Off', style: TextStyle(color: Color(0xFFD32F2F))),
                            subtitle: const Text('Disable two-step PIN protection'),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: _showDisableDialog,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final enabled = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const TwoStepVerificationScreen(
                                mode: TwoStepMode.setup,
                              ),
                            ),
                          );
                          if (enabled == true) _loadSettingsStatus();
                        },
                        icon: const Icon(Icons.lock, color: Colors.white),
                        label: const Text(
                          'Enable Two-Step Verification',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPinInputView() {
    final isLogin = widget.mode == TwoStepMode.loginChallenge;
    final title = isLogin
        ? 'Two-Step Verification'
        : _setupStep == 0
            ? 'Create a 6-Digit PIN'
            : 'Confirm Your PIN';

    final subtitle = isLogin
        ? 'Enter your 6-digit Dolsyx PIN to access your account securely.'
        : _setupStep == 0
            ? 'Enter a 6-digit PIN which you will be asked for when registering your account.'
            : 'Re-enter your 6-digit PIN to confirm it.';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
        leading: isLogin
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock, size: 36, color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 20),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),
              // Off-screen text field to capture native keyboard events
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0.0,
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: TextField(
                        controller: _pinController,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onChanged: (val) {
                          setState(() {});
                          if (val.length == 6) {
                            if (isLogin) {
                              _handleLoginVerify();
                            } else {
                              _handleSetupNext();
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  _buildPinBoxes(),
                ],
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFD32F2F), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFC62828), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_lockoutRemainingMinutes != null && _lockoutRemainingMinutes! > 0) ...[
                Text(
                  'Account locked for $_lockoutRemainingMinutes minutes.',
                  style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
              ],
              if (isLogin) ...[
                TextButton(
                  onPressed: _showForgotPinDialog,
                  child: Text(
                    'Forgot PIN?',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (isLogin) {
                            _handleLoginVerify();
                          } else {
                            _handleSetupNext();
                          }
                        },
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          isLogin
                              ? 'Verify PIN'
                              : _setupStep == 0
                                  ? 'Next'
                                  : 'Done',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
