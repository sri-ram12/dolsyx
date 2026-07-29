import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/chat_list_screen.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/wallpaper_provider.dart';
import 'widgets/app_lock_wrapper.dart';
import 'screens/call_screen.dart';
import 'services/sound_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Background FCM handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Try to initialize Firebase (will fail if google-services.json is missing)
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print("Firebase initialization skipped (missing config): $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => WallpaperProvider()),
      ],
      child: const DolsyxApp(),
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
  bool _isInit = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupGlobalCallListener();
      _setupForegroundFCM();
    });
    _tryAutoLogin();
  }

  void _setupForegroundFCM() {
    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print("Foreground message received: \${message.notification?.title}");
          // In a real app, we could show a local notification here using flutter_local_notifications
        });
      }
    } catch (e) {
      print("FCM foreground setup error: $e");
    }
  }

  Future<void> _tryAutoLogin() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.tryAutoLogin();
    if (mounted) {
      setState(() {
        _isInit = false;
      });
    }
  }

  void _setupGlobalCallListener() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // We add a listener to authProvider so that when a socket is connected,
    // we attach the call_invite listener.
    authProvider.addListener(() {
      if (authProvider.isAuthenticated && authProvider.socketService.socket != null) {
        // Ensure we don't attach multiple listeners
        authProvider.socketService.offCallIncoming(_handleCallIncoming);
        authProvider.socketService.onCallIncoming(_handleCallIncoming);
      }
    });
  }

  void _handleCallIncoming(dynamic data) {
    if (data == null) return;
    final String conversationId = data['conversationId'] ?? '';
    final String callTypeStr = data['callType'] ?? 'audio';
    final bool isAudioOnly = callTypeStr == 'audio';
    final String callerId = data['callerId'] ?? '';
    final String callerName = data['callerName'] ?? 'Incoming Call';
    final String? callerAvatarUrl = data['callerAvatarUrl'] ?? data['callerAvatar'];
    
    // WebRTC offer from caller
    final Map<String, dynamic>? initialOffer = data['offer'];

    // Start caller ringtone loop
    SoundService().startRingtone();

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
            initialOffer: initialOffer,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeProvider, AuthProvider>(
      builder: (context, themeProvider, authProvider, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'DOLSYX Mobile',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeData,
          builder: (context, child) {
            final fontScale = themeProvider.currentFontSize / 16.0; // 16px = Medium (1.0x)
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(fontScale),
              ),
              child: GlobalAppLockWrapper(child: child!),
            );
          },
          home: _isInit 
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : (authProvider.isAuthenticated ? const ChatListScreen() : const LoginScreen()),
        );
      },
    );
  }
}
