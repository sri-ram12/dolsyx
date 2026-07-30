import 'dart:async';
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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Background FCM handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'This channel is used for important notifications.',
  importance: Importance.max,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Firebase initialization skipped (missing config)
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

  Future<void> _setupForegroundFCM() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        const InitializationSettings initializationSettings =
            InitializationSettings(android: initializationSettingsAndroid);
        await flutterLocalNotificationsPlugin.initialize(
          settings: initializationSettings,
        );

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final RemoteNotification? notification = message.notification;
          final AndroidNotification? android = message.notification?.android;

          if (notification != null && android != null) {
            flutterLocalNotificationsPlugin.show(
              id: notification.hashCode,
              title: notification.title,
              body: notification.body,
              notificationDetails: NotificationDetails(
                android: AndroidNotificationDetails(
                  channel.id,
                  channel.name,
                  channelDescription: channel.description,
                  icon: '@mipmap/ic_launcher',
                  priority: Priority.high,
                  importance: Importance.max,
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      // FCM foreground setup error
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
    
    authProvider.addListener(() {
      if (authProvider.isAuthenticated && authProvider.socketService.socket != null) {
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
    
    final Map<String, dynamic>? initialOffer = data['offer'];

    SoundService().startRingtone();

    if (CallScreen.activeConversationId == conversationId) {
      return;
    }

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
            final fontScale = themeProvider.currentFontSize / 16.0;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(fontScale),
              ),
              child: GlobalAppLockWrapper(
                child: Column(
                  children: [
                    // ── Ongoing Call Banner ──
                    ValueListenableBuilder<bool>(
                      valueListenable: CallScreen.isCallActiveNotifier,
                      builder: (ctx, isActive, _) {
                        if (!isActive) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: () {
                            final state = CallScreen.activeCallState;
                            if (state != null && navigatorKey.currentState != null) {
                              navigatorKey.currentState!.push(
                                MaterialPageRoute(
                                  builder: (_) => CallScreen(
                                    conversationId: CallScreen.activeConversationId ?? '',
                                    remoteUserId: state.widget.remoteUserId,
                                    remoteUserName: state.widget.remoteUserName,
                                    remoteAvatarUrl: state.widget.remoteAvatarUrl,
                                    isAudioOnly: state.widget.isAudioOnly,
                                    isIncoming: false,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Material(
                            child: Container(
                              width: double.infinity,
                              color: Colors.green,
                              padding: EdgeInsets.only(
                                top: MediaQuery.of(ctx).padding.top + 4,
                                bottom: 6,
                                left: 16,
                                right: 16,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.call, color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Tap to return to call',
                                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
                                    ),
                                  ),
                                  _OngoingCallTimer(),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Expanded(child: child!),
                  ],
                ),
              ),
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

/// Tiny widget that ticks every second to show ongoing call duration
class _OngoingCallTimer extends StatefulWidget {
  @override
  State<_OngoingCallTimer> createState() => _OngoingCallTimerState();
}

class _OngoingCallTimerState extends State<_OngoingCallTimer> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = CallScreen.activeCallState;
    final text = state != null ? state.formattedDuration : '';
    return Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
    );
  }
}
