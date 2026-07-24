import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'widgets/app_lock_wrapper.dart';
import 'screens/call_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const GlobalAppLockWrapper(child: DolsyxApp()),
    ),
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class DolsyxApp extends StatefulWidget {
  const DolsyxApp({super.key});

  @override
  State<DolsyxApp> createState() => _DolsyxAppState();
}

class _DolsyxAppState extends State<DolsyxApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupGlobalCallListener();
    });
  }

  void _setupGlobalCallListener() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // We add a listener to authProvider so that when a socket is connected,
    // we attach the call_invite listener.
    authProvider.addListener(() {
      if (authProvider.isAuthenticated && authProvider.socketService.socket != null) {
        // Ensure we don't attach multiple listeners
        authProvider.socketService.offCallInvite(_handleCallInvite);
        authProvider.socketService.onCallInvite(_handleCallInvite);
      }
    });
  }

  void _handleCallInvite(dynamic data) {
    if (data == null) return;
    final String conversationId = data['conversationId'];
    final bool isAudioOnly = data['isAudioOnly'] ?? false;
    final String callId = data['callId'] ?? '';
    final String callerId = data['callerId'] ?? '';
    final String callerName = data['callerName'] ?? 'Incoming Call';
    final String? callerAvatarUrl = data['callerAvatarUrl'];

    // Only navigate if we're not already on a call screen
    // For simplicity, we just push it. In a real app we'd check current route.
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            conversationId: conversationId,
            remoteUserId: callerId,
            remoteUserName: callerName,
            remoteAvatarUrl: callerAvatarUrl,
            isAudioOnly: isAudioOnly,
            isIncoming: true,
            callId: callId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'DOLSYX Mobile',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeData,
          home: const LoginScreen(),
        );
      },
    );
  }
}
