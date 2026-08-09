import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TwoFactorAuthScreen extends StatefulWidget {
  const TwoFactorAuthScreen({super.key});

  @override
  State<TwoFactorAuthScreen> createState() => _TwoFactorAuthScreenState();
}

class _TwoFactorAuthScreenState extends State<TwoFactorAuthScreen> {
  bool _is2FAEnabled = false;
  final TextEditingController _pinController = TextEditingController();

  void _toggle2FA() {
    if (!_is2FAEnabled) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Set 6-Digit 2FA Security PIN'),
          content: TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Enter 6-digit PIN'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (_pinController.text.length == 6) {
                  Navigator.pop(ctx);
                  setState(() => _is2FAEnabled = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Two-Step Verification Enabled Successfully!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN must be exactly 6 digits')),
                  );
                }
              },
              child: const Text('Enable'),
            ),
          ],
        ),
      );
    } else {
      setState(() => _is2FAEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Two-Step Verification Disabled')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-Step Verification'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              _is2FAEnabled ? Icons.verified_user : Icons.security,
              size: 80,
              color: _is2FAEnabled ? Colors.green : AppTheme.primaryColor,
            ),
            const SizedBox(height: 20),
            Text(
              _is2FAEnabled ? 'Two-Step Verification is Active' : 'Enable Extra Account Security',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'When logging in on a new device, you will be required to enter your 6-digit security PIN.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _toggle2FA,
              style: ElevatedButton.styleFrom(
                backgroundColor: _is2FAEnabled ? Colors.redAccent : AppTheme.primaryColor,
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(_is2FAEnabled ? 'Disable 2FA' : 'Enable 2FA Security PIN'),
            ),
          ],
        ),
      ),
    );
  }
}
