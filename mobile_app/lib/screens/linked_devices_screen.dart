import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'qr_scanner_screen.dart';

class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLinkedDevices();
  }

  Future<void> _loadLinkedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('linked_devices_list');
      if (saved != null && saved.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(saved);
        _devices = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        // Provide standard default active sessions
        _devices = [
          {
            'id': 'dev_win_1',
            'name': 'Windows (DOLSYX Web)',
            'browser': 'Google Chrome',
            'lastActive': DateTime.now().subtract(const Duration(minutes: 12)).toIso8601String(),
            'location': 'New Delhi, India',
            'isCurrent': false,
            'status': 'Active now',
          },
          {
            'id': 'dev_mac_1',
            'name': 'macOS (DOLSYX Desktop)',
            'browser': 'Safari',
            'lastActive': DateTime.now().subtract(const Duration(days: 2, hours: 4)).toIso8601String(),
            'location': 'Mumbai, India',
            'isCurrent': false,
            'status': 'Active 2 days ago',
          },
        ];
        await prefs.setString('linked_devices_list', jsonEncode(_devices));
      }
    } catch (e) {
      debugPrint('Error loading linked devices: $e');
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLinkedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('linked_devices_list', jsonEncode(_devices));
    } catch (e) {
      debugPrint('Error saving linked devices: $e');
    }
  }

  void _linkNewDevice() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (result != null && mounted) {
      // Simulate successful link
      final rawStr = result.toString().split('//').last.split('?').first;
      final label = rawStr.length > 15 ? rawStr.substring(0, 15) : rawStr;
      final newDevice = {
        'id': 'dev_${DateTime.now().millisecondsSinceEpoch}',
        'name': 'Web Browser ($label)',
        'browser': 'DOLSYX Web Client',
        'lastActive': DateTime.now().toIso8601String(),
        'location': 'Local Network',
        'isCurrent': false,
        'status': 'Active now',
      };
      setState(() {
        _devices.insert(0, newDevice);
      });
      await _saveLinkedDevices();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device linked successfully! You can now chat on computer.'),
          backgroundColor: Color(0xFF00A884),
        ),
      );
    }
  }

  void _showDeviceOptions(Map<String, dynamic> device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.laptop, color: Color(0xFF00A884), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device['name'] ?? 'Linked Device',
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${device['browser'] ?? ''} • ${device['location'] ?? ''}',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white12),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('You will be logged out from this computer session', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() {
                    _devices.removeWhere((d) => d['id'] == device['id']);
                  });
                  await _saveLinkedDevices();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Logged out from ${device['name']}')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked devices', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero illustration & info
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                    color: AppTheme.surfaceColor,
                    child: Column(
                      children: [
                        // Modern device sync graphic
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00A884).withOpacity(0.12),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(Icons.laptop_chromebook_rounded, size: 68, color: Color(0xFF00A884)),
                              Positioned(
                                right: 20,
                                bottom: 24,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.phone_android_rounded, size: 28, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Use DOLSYX on other devices',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan the QR code displayed on your computer to open your DOLSYX account on web or desktop.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 22),
                        // Link a device button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _linkNewDevice,
                            icon: const Icon(Icons.qr_code_scanner, color: Colors.black),
                            label: const Text(
                              'Link a device',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00A884),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Device status header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Device status',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap a device to log out.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                  // Linked devices list
                  if (_devices.isEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'No devices currently linked.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final dev = _devices[index];
                          final isWin = (dev['name'] ?? '').toLowerCase().contains('win');
                          final isMac = (dev['name'] ?? '').toLowerCase().contains('mac');
                          IconData devIcon = Icons.laptop;
                          if (isWin) devIcon = Icons.window;
                          if (isMac) devIcon = Icons.apple;

                          String subtitle = dev['status'] ?? 'Active';
                          if (dev['lastActive'] != null) {
                            try {
                              final dt = DateTime.parse(dev['lastActive']);
                              final now = DateTime.now();
                              if (now.difference(dt).inMinutes < 60) {
                                subtitle = 'Active ${now.difference(dt).inMinutes}m ago';
                              } else {
                                subtitle = 'Last active ${DateFormat('dd MMM, hh:mm a').format(dt)}';
                              }
                            } catch (_) {}
                          }

                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(devIcon, color: Colors.white70, size: 22),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    dev['name'] ?? 'Device',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (dev['status']?.toString().toLowerCase().contains('active now') ?? false)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00A884).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(radius: 3, backgroundColor: Color(0xFF00A884)),
                                        SizedBox(width: 4),
                                        Text('Active', style: TextStyle(color: Color(0xFF00A884), fontSize: 10, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              subtitle,
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
                            onTap: () => _showDeviceOptions(dev),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 32),

                  // End-to-end encryption notice
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline, size: 16, color: Colors.white38),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your personal messages, media, and calls are end-to-end encrypted across all linked devices.',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

extension StringExtension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
