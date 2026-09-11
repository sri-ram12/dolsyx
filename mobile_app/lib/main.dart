import 'dart:async';
import 'dart:convert';
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
import 'package:flutter/services.dart';
import 'screens/share_target_screen.dart';
import 'services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';


// Background FCM handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;

  // Handle incoming call notifications in background/killed state
  if (data['type'] == 'CALL' || data['type'] == 'call' || data['callType'] != null) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(callChannel);

    final String callerName = data['callerName'] ?? 'Incoming Call';
    final String callType = data['callType'] ?? 'audio';
    final bool isAudioOnly = callType == 'audio';

    final payloadMap = {
      'conversationId': data['conversationId'] ?? '',
      'callerId': data['callerId'] ?? '',
      'callerName': callerName,
      'callerAvatarUrl': data['callerAvatarUrl'],
      'isAudioOnly': isAudioOnly,
      'callType': callType,
      'initialOffer': null,
    };

    await flutterLocalNotificationsPlugin.show(
      id: 8888,
      title: 'Incoming ${isAudioOnly ? 'Audio' : 'Video'} Call',
      body: '$callerName is calling you...',
      payload: jsonEncode(payloadMap),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          callChannel.id,
          callChannel.name,
          channelDescription: callChannel.description,
          icon: '@mipmap/ic_launcher',
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          priority: Priority.max,
          importance: Importance.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          sound: const RawResourceAndroidNotificationSound('dolsyx_ringtone'),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          playSound: true,
          enableVibration: false,
          ongoing: true,
          autoCancel: false,
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction('decline', 'Decline', cancelNotification: true),
            const AndroidNotificationAction('accept', 'Accept', cancelNotification: true),
          ],
        ),
      ),
    );
  } else {
    // Show notification for incoming text/media message in background/killed state
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    final title = message.notification?.title ?? data['senderName'] ?? data['title'] ?? 'New Message';
    final body = message.notification?.body ?? data['content'] ?? data['body'] ?? 'You have a new message';

    await flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: jsonEncode({
        'conversationId': data['conversationId'] ?? '',
        'senderId': data['senderId'] ?? '',
      }),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: '@mipmap/ic_launcher',
          priority: Priority.high,
          importance: Importance.max,
          sound: const RawResourceAndroidNotificationSound('dolsyx_message'),
          playSound: true,
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'reply_msg',
              'Reply',
              inputs: <AndroidNotificationActionInput>[
                AndroidNotificationActionInput(label: 'Type a message...'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'dolsyx_messages_v2',
  'Message Notifications',
  description: 'Notifications for incoming text and media messages',
  importance: Importance.max,
  playSound: true,
  enableVibration: false,
  sound: RawResourceAndroidNotificationSound('dolsyx_message'),
);

const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
  'call_channel_v3',
  'Incoming Calls',
  description: 'Full-screen incoming call notifications with ringtone',
  importance: Importance.max,
  playSound: true,
  enableVibration: false,
  sound: RawResourceAndroidNotificationSound('dolsyx_ringtone'),
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

class _DolsyxAppState extends State<DolsyxApp> with WidgetsBindingObserver {
  bool _isInit = true;
  String? _currentFcmUserId;
  Map<String, dynamic>? _incomingCallData;
  String? _callEndedBannerText;
  Timer? _callEndedBannerTimer;
  DateTime? _lastCallEndedTime;

  void _showCallEndedBanner(String reason) {
    _callEndedBannerTimer?.cancel();
    if (mounted) {
      setState(() {
        _incomingCallData = null;
        _callEndedBannerText = reason;
      });
      _callEndedBannerTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _callEndedBannerText = null);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep ongoing calls running in background / PiP mode even if app task is detached
  }

  Future<void> _requestEssentialPermissions() async {
    try {
      await [
        Permission.notification,
        Permission.microphone,
        Permission.camera,
        Permission.photos,
        Permission.videos,
        Permission.audio,
        Permission.storage,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.nearbyWifiDevices,
      ].request();
    } catch (e) {
      debugPrint("Permission request error: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callEndedBannerTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _requestEssentialPermissions();
      _setupGlobalCallListener();
      _setupForegroundFCM();
      _handleFCMCallbacks();
      
      // Check if app was opened/launched from a call notification action or click
      try {
        final launchDetails = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
        if (launchDetails?.didNotificationLaunchApp == true && launchDetails?.notificationResponse != null) {
          final response = launchDetails!.notificationResponse!;
          if (response.payload != null && response.payload!.isNotEmpty) {
            final data = jsonDecode(response.payload!);
            final callTypeStr = (data['callType'] ?? '').toString().toLowerCase();
            final isAudioOnly = callTypeStr == 'video'
                ? false
                : (data['isAudioOnly'] == true || callTypeStr == 'audio');
            setState(() {
              _incomingCallData = {
                'conversationId': data['conversationId'] ?? '',
                'callerId': data['callerId'] ?? '',
                'callerName': data['callerName'] ?? 'Incoming Call',
                'callerAvatarUrl': data['callerAvatarUrl'],
                'callType': callTypeStr.isNotEmpty ? callTypeStr : (isAudioOnly ? 'audio' : 'video'),
                'isAudioOnly': isAudioOnly,
                'initialOffer': data['initialOffer'],
              };
            });
            if (response.actionId == 'decline') {
              _declineIncomingCall();
            } else {
              _acceptIncomingCall();
            }
          }
        }
      } catch (_) {}
      _checkInitialShareData();
    });
    _tryAutoLogin();
  }

  static const _shareChannel = MethodChannel('com.dolsyx/share');

  Future<void> _checkInitialShareData() async {
    try {
      final sharedData = await _shareChannel.invokeMethod('getInitialSharedData');
      if (sharedData != null && sharedData is Map) {
        _openShareTarget(Map<String, dynamic>.from(sharedData));
      }
    } catch (_) {}

    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedDataReceived' && call.arguments != null) {
        _openShareTarget(Map<String, dynamic>.from(call.arguments));
      }
    });
  }

  void _openShareTarget(Map<String, dynamic> sharedData) {
    if (!mounted) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ShareTargetScreen(sharedData: sharedData),
      ),
    );
  }

  /// Handle FCM notification taps (app was in background and user tapped the notification)
  void _handleFCMCallbacks() {
    try {
      if (Firebase.apps.isEmpty) return;
      // When user taps a notification and app is brought to foreground
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final data = message.data;
        final type = data['type']?.toString().toUpperCase();
        if (type == 'CALL_ENDED' || type == 'CALL_REJECTED' || type == 'CALL_CANCELLED') {
          _handleCallEndedGlobal(data);
          return;
        }
        if (type == 'CALL' || (data['callType'] != null && type != 'CALL_ENDED')) {
          if (_incomingCallData != null) {
            _acceptIncomingCall();
          } else {
            // Construct incoming call data from push payload
            setState(() {
              _incomingCallData = {
                'conversationId': data['conversationId'] ?? '',
                'callerId': data['callerId'] ?? '',
                'callerName': data['callerName'] ?? 'Incoming Call',
                'callerAvatarUrl': data['callerAvatarUrl'],
                'isAudioOnly': (data['callType'] ?? 'audio') == 'audio',
                'initialOffer': null,
              };
            });
            SoundService().startRingtone();
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _setupForegroundFCM() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(callChannel);

        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        const InitializationSettings initializationSettings =
            InitializationSettings(android: initializationSettingsAndroid);
        await flutterLocalNotificationsPlugin.initialize(
          settings: initializationSettings,
          onDidReceiveNotificationResponse: (details) {
            Map<String, dynamic>? payloadData;
            if (details.payload != null && details.payload!.isNotEmpty) {
              try {
                payloadData = jsonDecode(details.payload!);
                
                // Handle quick reply for message notifications from top notification banner
                if ((details.actionId == 'reply_msg' || (details.input != null && details.input!.trim().isNotEmpty)) && payloadData != null && payloadData['conversationId'] != null) {
                  final replyText = details.input ?? '';
                  final conversationId = payloadData['conversationId'];
                  if (replyText.trim().isNotEmpty && conversationId != null) {
                    ApiService().getToken().then((token) {
                      if (token != null) {
                        http.post(
                          Uri.parse('${ApiService.baseUrl}/chats/$conversationId/messages'),
                          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
                          body: jsonEncode({'content': replyText.trim()}),
                        ).then((res) {
                          debugPrint('[NotificationReply] Sent reply status: ${res.statusCode}');
                        }).catchError((err) {
                          debugPrint('[NotificationReply] Error sending reply: $err');
                        });
                      }
                    });
                  }
                  return;
                }

                // Check if this payload represents an incoming call
                final bool isCallPayload = payloadData != null &&
                    (payloadData.containsKey('callerId') ||
                        payloadData.containsKey('callType') ||
                        payloadData['isAudioOnly'] != null);

                if (isCallPayload) {
                  final callTypeStr = (payloadData['callType'] ?? '').toString().toLowerCase();
                  final isAudioOnly = callTypeStr == 'video'
                      ? false
                      : (payloadData['isAudioOnly'] == true || callTypeStr == 'audio');
                  _incomingCallData = {
                    'conversationId': payloadData['conversationId'] ?? '',
                    'callerId': payloadData['callerId'] ?? '',
                    'callerName': payloadData['callerName'] ?? 'Incoming Call',
                    'callerAvatarUrl': payloadData['callerAvatarUrl'],
                    'callType': callTypeStr.isNotEmpty ? callTypeStr : (isAudioOnly ? 'audio' : 'video'),
                    'isAudioOnly': isAudioOnly,
                    'initialOffer': payloadData['initialOffer'],
                  };
                  final actionId = details.actionId;
                  if (actionId == 'decline') {
                    _declineIncomingCall(payloadData);
                  } else {
                    _acceptIncomingCall(payloadData);
                  }
                }
              } catch (_) {}
            }
          },
        );

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final RemoteNotification? notification = message.notification;
          final AndroidNotification? android = message.notification?.android;
          final data = message.data;

          final type = data['type']?.toString().toUpperCase();
          if (type == 'CALL_ENDED' || type == 'CALL_REJECTED' || type == 'CALL_CANCELLED') {
            _handleCallEndedGlobal(data);
            return;
          }

          // If incoming call arrives via FCM in foreground (fallback if socket delayed)
          if (type == 'CALL' || (data['callType'] != null && type != 'CALL_ENDED')) {
            if (_incomingCallData == null) {
              _handleCallIncoming({
                'conversationId': data['conversationId'] ?? '',
                'callerId': data['callerId'] ?? '',
                'callerName': data['callerName'] ?? 'Incoming Call',
                'callerAvatarUrl': data['callerAvatarUrl'],
                'callType': data['callType'] ?? 'audio',
              });
            }
            return;
          }

          // Skip notifications for messages sent by current user
          if (data['senderId'] != null && data['senderId'] == _currentFcmUserId) return;

          if (notification != null && android != null) {
            // Play in-app notification sound
            SoundService().playNotificationSound();
            flutterLocalNotificationsPlugin.show(
              id: notification.hashCode,
              title: notification.title,
              body: notification.body,
              payload: jsonEncode({
                'conversationId': data['conversationId'],
                'senderId': data['senderId'],
              }),
              notificationDetails: NotificationDetails(
                android: AndroidNotificationDetails(
                  channel.id,
                  channel.name,
                  channelDescription: channel.description,
                  icon: '@mipmap/ic_launcher',
                  priority: Priority.high,
                  importance: Importance.max,
                  enableVibration: true,
                  playSound: true,
                  enableLights: true,
                  actions: <AndroidNotificationAction>[
                    const AndroidNotificationAction(
                      'reply_msg',
                      'Reply',
                      inputs: <AndroidNotificationActionInput>[
                        AndroidNotificationActionInput(
                          label: 'Type your message...',
                        ),
                      ],
                      cancelNotification: true,
                    ),
                  ],
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
      _bindSocketListeners();
    }
  }

  void _bindSocketListeners() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated && authProvider.socketService.socket != null) {
      authProvider.socketService.offCallIncoming(_handleCallIncoming);
      authProvider.socketService.onCallIncoming(_handleCallIncoming);
      authProvider.socketService.offCallEnded(_handleCallEndedGlobal);
      authProvider.socketService.onCallEnded(_handleCallEndedGlobal);
    }
  }

  void _handleCallEndedGlobal(dynamic data) {
    _lastCallEndedTime = DateTime.now();
    try { flutterLocalNotificationsPlugin.cancelAll(); } catch (_) {}
    SoundService().stopRingtone();
    final status = data is Map ? data['status'] : null;
    final reason = status == 'rejected' ? 'Call Declined' : ((data is Map ? data['reason'] : null) ?? 'Call Ended');
    _showCallEndedBanner(reason);
  }

  void _setupGlobalCallListener() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    authProvider.addListener(() {
      _bindSocketListeners();
    });
    _bindSocketListeners();

    // When call ends (from any side), cancel the OS notification and clear banner immediately
    CallScreen.isCallActiveNotifier.addListener(() {
      if (!CallScreen.isCallActiveNotifier.value) {
        _lastCallEndedTime = DateTime.now();
        try { flutterLocalNotificationsPlugin.cancelAll(); } catch (_) {}
        SoundService().stopRingtone();
        if (mounted) {
          setState(() => _incomingCallData = null);
        }
      }
    });

    CallScreen.callEndedNotifier.addListener(() {
      final reason = CallScreen.callEndedNotifier.value;
      if (reason != null && reason.isNotEmpty) {
        _lastCallEndedTime = DateTime.now();
        try { flutterLocalNotificationsPlugin.cancelAll(); } catch (_) {}
        SoundService().stopRingtone();
        _showCallEndedBanner(reason);
      }
    });
  }

  void _handleCallIncoming(dynamic data) {
    if (data == null) return;
    final String conversationId = data['conversationId'] ?? '';
    final String callTypeStr = (data['callType'] ?? 'audio').toString().toLowerCase();
    final bool isAudioOnly = callTypeStr == 'video'
        ? false
        : (data['isAudioOnly'] == true || callTypeStr == 'audio');
    final String callerId = data['callerId'] ?? '';
    final String callerName = data['callerName'] ?? 'Incoming Call';
    final String? callerAvatarUrl = data['callerAvatarUrl'] ?? data['callerAvatar'];
    final Map<String, dynamic>? initialOffer = data['offer'];

    // Don't show another incoming call UI if we're already on a call with this person, or call active, or just ended
    if (CallScreen.activeConversationId == conversationId ||
        CallScreen.isCallActiveNotifier.value ||
        (_lastCallEndedTime != null && DateTime.now().difference(_lastCallEndedTime!).inSeconds < 4)) {
      return;
    }

    // Always store banner data (so it's available when user returns to app)
    if (mounted) {
      setState(() {
        _incomingCallData = {
          'conversationId': conversationId,
          'callerId': callerId,
          'callerName': callerName,
          'callerAvatarUrl': callerAvatarUrl,
          'callType': callTypeStr.isNotEmpty ? callTypeStr : (isAudioOnly ? 'audio' : 'video'),
          'isAudioOnly': isAudioOnly,
          'initialOffer': initialOffer,
        };
      });
    }

    // Play ringtone via SoundService (foreground audio)
    SoundService().startRingtone();

    // ALWAYS fire the OS notification with ringtone so it works in ALL states:
    // foreground (heads-up banner), background (heads-up + sound), killed (full-screen alert + sound)
    try {
      flutterLocalNotificationsPlugin.show(
        id: 8888,
        title: 'Incoming ${isAudioOnly ? 'Audio' : 'Video'} Call',
        body: '$callerName is calling you...',
        payload: jsonEncode({
          'conversationId': conversationId,
          'callerId': callerId,
          'callerName': callerName,
          'callerAvatarUrl': callerAvatarUrl,
          'isAudioOnly': isAudioOnly,
          'initialOffer': initialOffer,
        }),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            callChannel.id,
            callChannel.name,
            channelDescription: callChannel.description,
            icon: '@mipmap/ic_launcher',
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            priority: Priority.max,
            importance: Importance.max,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.call,
            sound: const RawResourceAndroidNotificationSound('dolsyx_ringtone'),
            audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
            playSound: true,
            enableVibration: false,
            ongoing: true,
            autoCancel: false,
            actions: <AndroidNotificationAction>[
              const AndroidNotificationAction('decline', 'Decline', cancelNotification: true),
              const AndroidNotificationAction('accept', 'Accept', cancelNotification: true),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  void _acceptIncomingCall([Map<String, dynamic>? callData]) {
    final data = callData ?? _incomingCallData;
    if (data == null) return;
    setState(() => _incomingCallData = null);
    SoundService().stopRingtone();
    try { flutterLocalNotificationsPlugin.cancelAll(); } catch (_) {}

    if (CallScreen.isCallActiveNotifier.value &&
        CallScreen.activeConversationId == data['conversationId']) {
      return;
    }

    void navigateToCall() {
      final callerNameStr = (data['callerName'] ?? 'User').toString();
      final callerIdStr = (data['callerId'] ?? '').toString();
      final convIdStr = (data['conversationId'] ?? '').toString();
      final String callTypeStr = (data['callType'] ?? '').toString().toLowerCase();
      final bool isAudioOnly = callTypeStr == 'video'
          ? false
          : (data['isAudioOnly'] == true || callTypeStr == 'audio');

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'CallScreen'),
            builder: (_) => CallScreen(
              conversationId: convIdStr,
              remoteUserId: callerIdStr,
              remoteUserName: callerNameStr,
              remoteAvatarUrl: data['callerAvatarUrl']?.toString(),
              isAudioOnly: isAudioOnly,
              isIncoming: true,
              initialOffer: data['initialOffer'],
            ),
          ),
        );
      } else {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!.push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'CallScreen'),
                builder: (_) => CallScreen(
                  conversationId: convIdStr,
                  remoteUserId: callerIdStr,
                  remoteUserName: callerNameStr,
                  remoteAvatarUrl: data['callerAvatarUrl']?.toString(),
                  isAudioOnly: isAudioOnly,
                  isIncoming: true,
                  initialOffer: data['initialOffer'],
                ),
              ),
            );
          }
        });
      }
    }

    navigateToCall();
  }

  void _declineIncomingCall([Map<String, dynamic>? callData]) {
    final data = callData ?? _incomingCallData;
    SoundService().stopRingtone();
    try { flutterLocalNotificationsPlugin.cancelAll(); } catch (_) {}
    if (data != null) {
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.socketService.socket != null && authProvider.socketService.isConnected) {
          authProvider.socketService.socket!.emit('call_reject', {
            'callerId': data['callerId'],
            'conversationId': data['conversationId'],
            'callType': (data['isAudioOnly'] == true) ? 'audio' : 'video',
          });
        }
      } catch (_) {}
    }
    setState(() => _incomingCallData = null);
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
                    // ── Modern Floating Call Ended Banner ──
                    if (_callEndedBannerText != null)
                      Material(
                        color: Colors.transparent,
                        child: Container(
                          margin: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top + 10,
                            left: 14,
                            right: 14,
                            bottom: 10,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, 8)),
                            ],
                            border: Border.all(color: const Color(0xFFEA0038).withValues(alpha: 0.8), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEA0038).withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.call_end_rounded, color: Color(0xFFEA0038), size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Call Ended',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _callEndedBannerText!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.none,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── Modern Floating Incoming Call Alert Popup ──
                    ValueListenableBuilder<bool>(
                      valueListenable: CallScreen.isCallActiveNotifier,
                      builder: (context, isCallActive, _) {
                        if (_incomingCallData == null || isCallActive || _callEndedBannerText != null) return const SizedBox.shrink();
                        return Material(
                          color: Colors.transparent,
                          child: GestureDetector(
                            onTap: _acceptIncomingCall,
                            child: Container(
                              margin: EdgeInsets.only(
                                top: MediaQuery.of(context).padding.top + 10,
                                left: 14,
                                right: 14,
                                bottom: 10,
                              ),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, 8)),
                              ],
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppTheme.primaryColor, width: 2),
                                  ),
                                  child: CircleAvatar(
                                    radius: 26,
                                    backgroundColor: AppTheme.surfaceColor,
                                    backgroundImage: _incomingCallData!['callerAvatarUrl'] != null && _incomingCallData!['callerAvatarUrl'].toString().isNotEmpty
                                        ? NetworkImage(_incomingCallData!['callerAvatarUrl'].toString().startsWith('http') ? _incomingCallData!['callerAvatarUrl'] : '${ApiService.baseUrl.replaceAll('/api', '')}${_incomingCallData!['callerAvatarUrl']}')
                                        : null,
                                    child: _incomingCallData!['callerAvatarUrl'] == null ? const Icon(Icons.person, color: Colors.white, size: 30) : null,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _incomingCallData!['callerName'],
                                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            _incomingCallData!['isAudioOnly'] ? Icons.phone_in_talk : Icons.videocam,
                                            color: Colors.greenAccent,
                                            size: 15,
                                          ),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              _incomingCallData!['isAudioOnly'] ? 'Incoming Audio Call...' : 'Incoming Video Call...',
                                              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _declineIncomingCall,
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)]),
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: Colors.redAccent, blurRadius: 10)],
                                        ),
                                        child: const Icon(Icons.call_end, color: Colors.white, size: 24),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    GestureDetector(
                                      onTap: _acceptIncomingCall,
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(colors: [Color(0xFF11998E), Color(0xFF38EF7D)]),
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: Colors.greenAccent, blurRadius: 10)],
                                        ),
                                        child: const Icon(Icons.call, color: Colors.white, size: 24),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                    // ── Ongoing Call Banner ──
                    ValueListenableBuilder<bool>(
                      valueListenable: CallScreen.isCallActiveNotifier,
                      builder: (ctx, isActive, _) {
                        if (!isActive) return const SizedBox.shrink();
                        return Material(
                          color: const Color(0xFF0F5132),
                          child: InkWell(
                            onTap: () {
                              if (navigatorKey.currentState == null) return;
                              
                              // Pop routes until we reach 'CallScreen'.
                              // After minimize, the stack is:
                              //   root → CallScreen → ChatListScreen
                              // popUntil pops ChatListScreen and stops at CallScreen.
                              bool found = false;
                              navigatorKey.currentState!.popUntil((route) {
                                if (route.settings.name == 'CallScreen') {
                                  found = true;
                                  return true; // stop here
                                }
                                return route.isFirst; // fallback: pop to root
                              });

                              // If not found, reset the notifier (call likely ended)
                              if (!found) {
                                if (CallScreen.activeCallState == null) {
                                  CallScreen.isCallActiveNotifier.value = false;
                                }
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFF075E54), Color(0xFF00A884)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                              padding: EdgeInsets.only(
                                top: MediaQuery.of(ctx).padding.top + 6,
                                bottom: 8,
                                left: 14,
                                right: 14,
                              ),
                              child: Row(
                                children: [
                                  // ── Left: Speaker & Mic Controls ──
                                  ValueListenableBuilder<bool>(
                                    valueListenable: CallScreen.isSpeakerOnNotifier,
                                    builder: (context, isSpeakerOn, _) {
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          CallScreen.toggleSpeaker();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: isSpeakerOn ? Colors.white : Colors.black.withValues(alpha: 0.25),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                                            color: isSpeakerOn ? const Color(0xFF075E54) : Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: CallScreen.isMutedNotifier,
                                    builder: (context, isMuted, _) {
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          CallScreen.toggleMute();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: isMuted ? const Color(0xFFEA0038) : Colors.black.withValues(alpha: 0.25),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 10),

                                  // ── Center: Tap to return to call + Duration ──
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Tap to return to call',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  decoration: TextDecoration.none,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              _OngoingCallTimer(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // ── Right: End Call Button ──
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      CallScreen.endActiveCall();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFEA0038),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 4,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.call_end_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
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
      text.isNotEmpty ? text : '00:00',
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.none,
      ),
    );
  }
}
