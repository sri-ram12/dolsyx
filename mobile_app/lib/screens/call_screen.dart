import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../theme/app_theme.dart';
import '../theme/chat_theme_model.dart';
import '../widgets/color_avatar.dart';
import '../services/sound_service.dart';
import '../services/contact_service.dart';
import 'chat_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/e2ee/crypto_service.dart';
import '../main.dart';

class CallScreen extends StatefulWidget {
  final String conversationId;
  final String remoteUserId;
  final String remoteUserName;
  final String? remoteAvatarUrl;
  final bool isAudioOnly;
  final bool isIncoming;
  final Map<String, dynamic>? initialOffer;

  const CallScreen({
    super.key,
    required this.conversationId,
    required this.remoteUserId,
    required this.remoteUserName,
    this.remoteAvatarUrl,
    required this.isAudioOnly,
    required this.isIncoming,
    this.initialOffer,
  });

  static String? activeConversationId;
  static ValueNotifier<bool> isCallActiveNotifier = ValueNotifier<bool>(false);
  static ValueNotifier<String?> callEndedNotifier = ValueNotifier<String?>(null);
  static ValueNotifier<bool> isMutedNotifier = ValueNotifier<bool>(false);
  static ValueNotifier<bool> isSpeakerOnNotifier = ValueNotifier<bool>(false);
  static dynamic activeCallState;

  static void toggleMute() {
    if (activeCallState != null) {
      activeCallState.toggleMuteDirect();
    }
  }

  static void toggleSpeaker() {
    if (activeCallState != null) {
      activeCallState.toggleSpeakerDirect();
    }
  }

  static void endActiveCall() {
    if (activeCallState != null) {
      activeCallState.endCallFromBanner();
    } else {
      isCallActiveNotifier.value = false;
    }
  }

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  // Mesh: multiple peer connections for group calls
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, List<RTCIceCandidate>> _iceCandidateQueues = {};
  final Map<String, Map<String, dynamic>> _participants = {};

  // Persistent remote stream per peer — tracks are ADDED to this, never replaced
  final Map<String, MediaStream> _remoteStreams = {};

  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _hardwareFailed = false;
  bool _callActive = false;
  bool _isSpeakerOn = false;
  bool _isDisposed = false;
  String _status = 'Connecting...';

  // Stored socket reference — avoids calling Provider.of(context) in native callbacks
  dynamic _socket;

  // Call Timer
  Timer? _callTimer;
  Timer? _timeoutTimer;
  int _callDuration = 0;

  String get formattedDuration => _formatDuration(_callDuration);
  void endCallFromBanner() => _endCall();
  void toggleMuteDirect() => _toggleMute();
  void toggleSpeakerDirect() {
    if (_audioOutputMode == 'speaker') {
      _selectAudioOutputMode('earpiece');
    } else {
      _selectAudioOutputMode('speaker');
    }
  }

  // 1-on-1 PiP dragging & Double-Tap Video Swap
  double _localVideoRight = 16;
  double _localVideoBottom = 100;
  bool _isSwappedVideo = false;
  String? _focusedParticipantId;

  // Drag-to-answer swipe up offset for incoming calls
  double _swipeUpOffset = 0.0;

  // Touch screen to show/hide controls (WhatsApp-style auto-hide)
  bool _areControlsVisible = true;
  Timer? _controlsHideTimer;

  void _toggleControlsVisibility() {
    setState(() {
      _areControlsVisible = !_areControlsVisible;
    });
    if (_areControlsVisible) {
      _startControlsAutoHideTimer();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  void _startControlsAutoHideTimer() {
    _controlsHideTimer?.cancel();
    if (!_callActive) return; // Keep visible while ringing/incoming
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _areControlsVisible && _callActive) {
        setState(() {
          _areControlsVisible = false;
        });
      }
    });
  }

  void _minimizeCall() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'ChatListScreen'),
        builder: (_) => const ChatListScreen(),
      ),
    );
  }

  void _showMoreCallOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2428),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            if (!widget.isAudioOnly)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _isScreenSharing ? const Color(0xFFEA0038).withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: _isScreenSharing ? Border.all(color: const Color(0xFFEA0038), width: 1.2) : null,
                ),
                child: ListTile(
                  leading: Icon(
                    _isScreenSharing ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                    color: _isScreenSharing ? const Color(0xFFEA0038) : Colors.white,
                  ),
                  title: Text(
                    _isScreenSharing ? 'Stop Screen Sharing' : 'Share Screen',
                    style: TextStyle(
                      color: _isScreenSharing ? const Color(0xFFEA0038) : Colors.white,
                      fontWeight: _isScreenSharing ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  trailing: _isScreenSharing
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEA0038),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('STOP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleScreenShare();
                  },
                ),
              ),
            if (!widget.isAudioOnly)
              ListTile(
                leading: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white),
                title: const Text('Switch Camera', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _switchCamera();
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_add_rounded, color: Colors.white),
              title: const Text('Add Participant', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddParticipantModal();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickReplyModal() {
    final replies = [
      "Can't talk now. What's up?",
      "I'll call you right back.",
      "I'm on my way.",
      "Call me later.",
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2428),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Reply with message', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            ...replies.map((reply) => ListTile(
              title: Text(reply, style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _rejectCall();
                final auth = Provider.of<AuthProvider>(context, listen: false);
                auth.socketService.sendMessage(widget.conversationId, reply);
              },
            )),
          ],
        ),
      ),
    );
  }

  // Screen Sharing
  bool _isScreenSharing = false;
  MediaStream? _screenStream;

  static const _channel = MethodChannel('com.dolsyx/screen_share');
  static const _pipChannel = MethodChannel('com.dolsyx/pip');

  // Named socket handlers so we can selectively remove only OUR listeners in dispose()
  late final Function(dynamic) _onCallAnswered;
  late final Function(dynamic) _onCallRejected;
  late final Function(dynamic) _onCallEnded;
  late final Function(dynamic) _onIceCandidate;
  late final Function(dynamic) _onUserAddedToCall;
  late final Function(dynamic) _onCallIncoming;
  late final Function(dynamic) _onScreenShareRequest;
  late final Function(dynamic) _onRequestCallOffer;
  late final Function(dynamic) _onCallOffer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // If a call is already active on a DIFFERENT conversation, this instance is a
    // stale shell pushed accidentally — pop it so we don't fire a duplicate call_offer.
    if (CallScreen.isCallActiveNotifier.value &&
        CallScreen.activeConversationId != null &&
        CallScreen.activeConversationId != widget.conversationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }

    CallScreen.activeConversationId = widget.conversationId;
    CallScreen.activeCallState = this;
    final initialName = (widget.remoteUserName.isNotEmpty) ? widget.remoteUserName : 'User';
    _participants[widget.remoteUserId] = {
      'username': initialName,
      'avatarUrl': widget.remoteAvatarUrl,
    };

    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        if (mounted) setState(() {});
      }
    });

    CallScreen.isMutedNotifier.value = _isMuted;
    CallScreen.isSpeakerOnNotifier.value = _isSpeakerOn;

    _initRenderers();
    _checkAudioDevicesAndRoute();
    try {
      navigator.mediaDevices.ondevicechange = (_) {
        if (mounted) _checkAudioDevicesAndRoute();
      };
    } catch (_) {}
    _audioRouteCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _callActive) {
        _checkAudioDevicesAndRoute();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _callActive && mounted) {
      try {
        _pipChannel.invokeMethod('enterPip');
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed && _callActive && mounted) {
      setState(() {});
    }
  }

  Future<void> _initRenderers() async {
    try {
      await _localRenderer.initialize();
    } catch (e) {
      debugPrint('[WebRTC] _localRenderer initialize error: $e');
    }
    _setupSocketListeners();

    if (widget.isIncoming) {
      // 🟢 Wait for user interaction: do NOT automatically lift call!
      setState(() {
        _status = 'Incoming call...';
      });
      SoundService().startRingtone();
      _timeoutTimer = Timer(const Duration(seconds: 60), () {
        if (!_callActive && mounted) {
          _rejectCall();
        }
      });
    } else {
      _timeoutTimer = Timer(const Duration(minutes: 2, seconds: 30), () {
        if (!_callActive && mounted) {
          _handleCallNotConnected();
        }
      });
      _startCall();
    }
  }

  void _handleCallNotConnected() {
    SoundService().stopRingtone();
    if (mounted) {
      setState(() {
        _status = 'Call Not Connected';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call Not Connected - User did not answer')),
      );
    }
    _endCallLocally('Call Not Connected');
  }

  void _setupSocketListeners() {
    _socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    final socket = _socket;
    if (socket == null) return;

    socket.on('call_busy', (data) {
      if (!mounted) return;
      SoundService().stopRingtone();
      SoundService().playBusyTone();
      _timeoutTimer?.cancel();
      setState(() => _status = 'User is Busy');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User is currently busy on another call')),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _endCallLocally('User is busy');
      });
    });

    _onCallAnswered = (data) async {
      if (!mounted || data == null) return;
      SoundService().stopRingtone();
      _timeoutTimer?.cancel();
      if (mounted) {
        setState(() {
          _status = 'Connected';
          _callActive = true;
          CallScreen.isCallActiveNotifier.value = true;
          try {
            _pipChannel.invokeMethod('setCallActive', {'active': true});
          } catch (_) {}
        });
      }
      final answererId = data['answererId'] ?? widget.remoteUserId;
      if (data['answer'] != null) {
        final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
        try {
          await _peerConnections[answererId]?.setRemoteDescription(answer);
        } catch (e) {
          debugPrint('[WebRTC] setRemoteDescription error: $e');
        }
        if (!mounted) return;
        await _flushIceCandidates(answererId);
      }
      if (!mounted) return;
      if (_callTimer == null || !_callTimer!.isActive) _startTimer();
    };
    socket.on('call_answered', _onCallAnswered);

    _onCallRejected = (data) {
      if (!mounted) return;
      _endCallLocally('Call rejected');
    };
    socket.on('call_rejected', _onCallRejected);

    _onCallEnded = (data) {
      if (!mounted) return;
      if (data?['status'] == 'answered_elsewhere') {
        _endCallLocally('Answered elsewhere');
        return;
      }
      final endedBy = data?['endedBy'];
      if (endedBy != null) {
        _removeParticipant(endedBy);
        if (_participants.isEmpty) _endCallLocally('Call ended');
      } else {
        _endCallLocally('Call ended');
      }
    };
    socket.on('call_ended', _onCallEnded);

    _onIceCandidate = (data) async {
      if (!mounted) return;
      final fromUserId = data['fromUserId'];
      if (data['candidate'] != null) {
        final candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex'],
        );
        final pc = _peerConnections[fromUserId];
        if (pc == null || await pc.getRemoteDescription() == null) {
          _iceCandidateQueues.putIfAbsent(fromUserId, () => []).add(candidate);
        } else {
          await pc.addCandidate(candidate);
        }
      }
    };
    socket.on('ice_candidate', _onIceCandidate);

    // Dynamic offer request handler: if receiver answered without initial offer, receiver asks caller for SDP offer
    _onRequestCallOffer = (data) async {
      if (_isDisposed || !mounted || data == null) return;
      final requesterId = data['requesterId'] as String? ?? widget.remoteUserId;
      try {
        // Recreate connection if already existing to prevent SDP state errors (kHaveLocalOffer)
        if (_peerConnections.containsKey(requesterId)) {
          final oldPc = _peerConnections.remove(requesterId);
          await oldPc?.close();
          await oldPc?.dispose();
        }
        final pc = await _createPeerConnection(requesterId);
        final offerConstraints = <String, dynamic>{
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': widget.isAudioOnly ? 0 : 1,
        };
        final offer = await pc.createOffer(offerConstraints);
        await pc.setLocalDescription(offer);
        _socket?.emit('call_offer', {
          'targetUserId': requesterId,
          'offer': {'sdp': offer.sdp, 'type': offer.type},
          'callType': widget.isAudioOnly ? 'audio' : 'video',
          'conversationId': widget.conversationId,
        });
      } catch (e) {
        debugPrint('[WebRTC] _onRequestCallOffer error: $e');
      }
    };
    socket.on('request_call_offer', _onRequestCallOffer);

    // Incoming offer handler (for dynamic offer handshake)
    _onCallOffer = (data) async {
      if (_isDisposed || !mounted || data == null) return;
      final callerId = data['callerId'] ?? widget.remoteUserId;
      final offerData = data['offer'];
      if (offerData == null) return;
      try {
        RTCPeerConnection pc;
        if (_peerConnections.containsKey(callerId)) {
          pc = _peerConnections[callerId]!;
        } else {
          pc = await _createPeerConnection(callerId);
        }
        final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
        await pc.setRemoteDescription(offer);
        await _flushIceCandidates(callerId);
        final answerConstraints = <String, dynamic>{
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': widget.isAudioOnly ? 0 : 1,
        };
        final answer = await pc.createAnswer(answerConstraints);
        await pc.setLocalDescription(answer);
        _socket?.emit('call_answer', {
          'callerId': callerId,
          'answer': {'sdp': answer.sdp, 'type': answer.type},
        });
        if (mounted && !_isDisposed) {
          setState(() {
            _callActive = true;
            _status = 'Connected';
            CallScreen.isCallActiveNotifier.value = true;
          });
          _startTimer();
        }
      } catch (e) {
        debugPrint('[WebRTC] _onCallOffer error: $e');
      }
    };
    socket.on('call_offer', _onCallOffer);

    // Group call: someone added a new user — we initiate to them
    _onUserAddedToCall = (data) async {
      if (!mounted || data == null) return;
      try {
        if (data['conversationId'] != widget.conversationId) return;
        final newUserId = data['newUserId'] as String?;
        final newUserName = data['newUserName'] as String? ?? 'User';
        if (newUserId == null) return;
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        setState(() {
          _participants[newUserId] = {'username': newUserName, 'avatarUrl': null};
        });
        final pc = await _createPeerConnection(newUserId);
        final offerConstraints = <String, dynamic>{
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': widget.isAudioOnly ? 0 : 1,
        };
        final offer = await pc.createOffer(offerConstraints);
        await pc.setLocalDescription(offer);
        final user = authProvider.user;
        authProvider.socketService.socket?.emit('call_offer', {
          'targetUserId': newUserId,
          'offer': {'sdp': offer.sdp, 'type': offer.type},
          'callType': widget.isAudioOnly ? 'audio' : 'video',
          'conversationId': widget.conversationId,
          'callerName': user?['username'] ?? 'User',
          'callerAvatar': user?['avatarUrl'],
        });
      } catch (e) {
        debugPrint('[WebRTC] user_added_to_call error: $e');
      }
    };
    socket.on('user_added_to_call', _onUserAddedToCall);

    // Group call: a new participant calls us (auto-answer)
    _onCallIncoming = (data) async {
      if (!mounted || data == null) return;
      try {
        if (data['conversationId'] != widget.conversationId) return;
        final callerId = data['callerId'] as String?;
        final callerName = data['callerName'] as String? ?? 'User';
        final callerAvatarUrl = data['callerAvatarUrl'];
        final offerData = data['offer'];
        if (callerId == null || offerData == null) return;
        setState(() {
          _participants[callerId] = {'username': callerName, 'avatarUrl': callerAvatarUrl};
        });
        final pc = await _createPeerConnection(callerId);
        final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
        await pc.setRemoteDescription(offer);
        await _flushIceCandidates(callerId);
        final answerConstraints = <String, dynamic>{
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': widget.isAudioOnly ? 0 : 1,
        };
        final answer = await pc.createAnswer(answerConstraints);
        await pc.setLocalDescription(answer);
        if (!mounted) return;
        Provider.of<AuthProvider>(context, listen: false).socketService.socket?.emit('call_answer', {
          'callerId': callerId,
          'answer': {'sdp': answer.sdp, 'type': answer.type},
        });
      } catch (e) {
        debugPrint('[WebRTC] call_incoming error: $e');
      }
    };
    socket.on('call_incoming', _onCallIncoming);

    // Screen Share Request event
    _onScreenShareRequest = (data) {
      if (!mounted) return;
      final senderName = data['senderName'] ?? 'User';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: Text('$senderName wants to share screen', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          content: Text('Do you accept incoming screen share?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                socket.emit('screen_share_decline', {
                  'targetUserId': data['senderId'],
                  'conversationId': widget.conversationId,
                });
              },
              child: const Text('Decline', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                socket.emit('screen_share_accept', {
                  'targetUserId': data['senderId'],
                  'conversationId': widget.conversationId,
                });
              },
              child: const Text('Accept', style: TextStyle(color: Colors.green)),
            ),
          ],
        ),
      );
    };
    socket.on('screen_share_request', _onScreenShareRequest);
  }

  void _removeParticipant(String userId) {
    if (_isDisposed) return;
    try {
      _peerConnections[userId]?.close();
      _peerConnections[userId]?.dispose();
      _peerConnections.remove(userId);
      _remoteRenderers[userId]?.srcObject = null;
      _remoteRenderers[userId]?.dispose();
      _remoteRenderers.remove(userId);
      _remoteStreams[userId]?.getTracks().forEach((t) => t.stop());
      _remoteStreams[userId]?.dispose();
      _remoteStreams.remove(userId);
      _iceCandidateQueues.remove(userId);
      if (mounted && !_isDisposed) setState(() => _participants.remove(userId));
    } catch (e) {
      debugPrint('[CallScreen] _removeParticipant error (ignored): $e');
    }
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDuration++);
    });
  }

  Future<void> _flushIceCandidates(String userId) async {
    final queue = _iceCandidateQueues[userId];
    if (queue != null) {
      for (final candidate in queue) {
        await _peerConnections[userId]?.addCandidate(candidate);
      }
      _iceCandidateQueues[userId]?.clear();
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String targetUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final forceRelay = prefs.getBool('force_turn_relay') ?? false;

    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
        {'urls': 'stun:stun4.l.google.com:19302'},
        {'urls': 'stun:stun.services.mozilla.com:3478'},
        {'urls': 'stun:global.stun.twilio.com:3478'},
        {
          'urls': 'turn:openrelay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turn:openrelay.metered.ca:443',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turns:openrelay.metered.ca:443?transport=tcp',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turns:openrelay.metered.ca:5349',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turn:relay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turn:relay.metered.ca:443',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turns:relay.metered.ca:443?transport=tcp',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'iceTransportPolicy': forceRelay ? 'relay' : 'all',
    };
    final pc = await createPeerConnection(configuration);
    _peerConnections[targetUserId] = pc;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    if (mounted) setState(() => _remoteRenderers[targetUserId] = renderer);

    pc.onIceCandidate = (candidate) {
      if (_isDisposed) return;
      // Use stored _socket reference — NEVER use Provider.of(context) inside a native callback
      _socket?.emit('ice_candidate', {
        'targetUserId': targetUserId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      });
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected && mounted) {
        // Ensure audio is routed to ear speaker or bluetooth automatically
        _checkAudioDevicesAndRoute();
        // Make sure all local audio tracks are enabled and unmuted
        _localStream?.getAudioTracks().forEach((t) { t.enabled = !_isMuted; });
        // Force a UI rebuild so remote video appears immediately
        if (mounted) setState(() {});
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed && mounted) {
        // Try ICE restart on failure
        pc.restartIce();
      }
    };

    // onTrack fires once per audio track and once per video track (Unified Plan)
    pc.onTrack = (event) {
      if (_isDisposed || !mounted) return;
      event.track.enabled = true;

      // Prefer the stream provided by the event
      MediaStream? incomingStream = event.streams.isNotEmpty ? event.streams[0] : null;

      if (incomingStream != null) {
        // Use the event stream directly — it already contains all tracks
        incomingStream.getAudioTracks().forEach((t) { t.enabled = true; });
        incomingStream.getVideoTracks().forEach((t) { t.enabled = true; });
        _remoteStreams[targetUserId] = incomingStream;
        if (mounted && !_isDisposed) {
          setState(() {
            _remoteRenderers[targetUserId]?.srcObject = incomingStream;
          });
        }
        _checkAudioDevicesAndRoute();
      } else {
        // Fallback: build a persistent stream manually and add each arriving track
        final existing = _remoteStreams[targetUserId];
        if (existing != null) {
          try { existing.addTrack(event.track); } catch (_) {}
          event.track.enabled = true;
          if (mounted && !_isDisposed) setState(() { _remoteRenderers[targetUserId]?.srcObject = existing; });
        } else {
          createLocalMediaStream('remote_$targetUserId').then((stream) {
            if (_isDisposed) return;
            try { stream.addTrack(event.track); } catch (_) {}
            event.track.enabled = true;
            _remoteStreams[targetUserId] = stream;
            if (mounted && !_isDisposed) {
              setState(() { _remoteRenderers[targetUserId]?.srcObject = stream; });
            }
          });
        }
        _checkAudioDevicesAndRoute();
      }
    };

    // onAddStream: Plan B fallback — route into the same persistent stream
    pc.onAddStream = (stream) async {
      if (_isDisposed || !mounted) return;
      if (!_remoteStreams.containsKey(targetUserId)) {
        _remoteStreams[targetUserId] = stream;
      } else {
        for (final t in stream.getTracks()) {
          if (_isDisposed) return;
          try { await _remoteStreams[targetUserId]!.addTrack(t); } catch (_) {}
          t.enabled = true;
        }
      }
      stream.getTracks().forEach((t) { t.enabled = true; });
      if (mounted && !_isDisposed) {
        setState(() {
          _remoteRenderers[targetUserId]?.srcObject = _remoteStreams[targetUserId];
        });
      }
      _checkAudioDevicesAndRoute();
    };

    if (_localStream == null) {
      await _initWebRTC();
    }

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    _flushIceCandidates(targetUserId);
    return pc;
  }

  Future<bool> _initWebRTC() async {
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        debugPrint('[WebRTC] Microphone permission denied');
        return false;
      }

      bool canCaptureVideo = !widget.isAudioOnly;
      if (canCaptureVideo) {
        final camStatus = await Permission.camera.request();
        if (!camStatus.isGranted) {
          debugPrint('[WebRTC] Camera permission denied — falling back to audio-only');
          canCaptureVideo = false;
          _isVideoOff = true;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final lowDataMode = prefs.getBool('low_bandwidth_call_mode') ?? false;

      final dynamic videoConstraints = !canCaptureVideo
          ? false
          : (lowDataMode
              ? {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}, 'frameRate': {'ideal': 24}}
              : {
                  'facingMode': 'user',
                  'width': {'ideal': 1280},
                  'height': {'ideal': 720},
                  'frameRate': {'ideal': 30},
                });

      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'googEchoCancellation': true,
            'googAutoGainControl': true,
            'googNoiseSuppression': true,
            'sampleRate': 48000,
            'channelCount': 1,
          },
          'video': videoConstraints,
        });
      } catch (e) {
        debugPrint('[WebRTC] Primary getUserMedia failed: $e, falling back to simple constraints');
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': canCaptureVideo ? {'facingMode': 'user'} : false,
          });
        } catch (err) {
          debugPrint('[WebRTC] Fallback getUserMedia failed: $err');
          // If video still failed, try audio only so call does not abort
          if (canCaptureVideo) {
            _localStream = await navigator.mediaDevices.getUserMedia({
              'audio': true,
              'video': false,
            });
            _isVideoOff = true;
          }
        }
      }

      // Verify we actually got audio tracks — empty stream means hardware isn't ready
      if (_localStream == null || _localStream!.getAudioTracks().isEmpty) {
        debugPrint('[WebRTC] getUserMedia returned no audio tracks');
        return false;
      }

      _localRenderer.srcObject = _localStream;
      if (widget.isAudioOnly || !canCaptureVideo) _isVideoOff = true;

      // Check connected devices and route automatically (Bluetooth -> Earpiece)
      await _checkAudioDevicesAndRoute();
      _localStream?.getAudioTracks().forEach((track) {
        track.enabled = true;
      });
      return true;
    } catch (e) {
      debugPrint('[WebRTC] getUserMedia error: $e');
      return false;
    }
  }

  String _optimizeSdpForHdCall(String? sdp, {bool isAudioOnly = false}) {
    if (sdp == null || sdp.isEmpty) return sdp ?? '';
    var modified = sdp;
    // 1. Opus high-fidelity HD voice: 64kbps bitrate, Forward Error Correction, CBR for low latency
    if (modified.contains('opus/48000')) {
      modified = modified.replaceAllMapped(
        RegExp(r'(a=fmtp:\d+ [^\r\n]*)'),
        (match) {
          final line = match.group(0)!;
          if (line.contains('opus') || line.contains('minptime') || line.contains('useinbandfec') || modified.contains('a=rtpmap:111 opus/48000')) {
            if (!line.contains('useinbandfec=1')) {
              return '$line;useinbandfec=1;maxaveragebitrate=64000;cbr=1;stereo=0;sprop-maxcapturerate=48000';
            }
          }
          return line;
        },
      );
    }
    // 2. Set video bandwidth for HD calling (2.5 Mbps = 2500 kbps)
    if (!isAudioOnly && modified.contains('m=video')) {
      modified = modified.replaceAll('m=video', 'm=video\r\nb=AS:2500\r\nb=TIAS:2500000');
    }
    return modified;
  }

  Future<void> _startCall() async {
    if (_callActive) return;
    setState(() => _status = 'Calling...');
    _timeoutTimer = Timer(const Duration(minutes: 2), () {
      if (!_callActive && mounted) _endCallLocally('No answer');
    });
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['id'];
    if (userId == null) return;
    if (authProvider.socketService.socket == null || !authProvider.socketService.isConnected) {
      await authProvider.socketService.connect(userId);
    }

    final success = await _initWebRTC();
    if (!mounted) return;
    if (!success) {
      setState(() { _hardwareFailed = true; _status = 'Microphone not available'; });
      return;
    }
    try {
      final pc = await _createPeerConnection(widget.remoteUserId);
      final offerConstraints = <String, dynamic>{
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': widget.isAudioOnly ? 0 : 1,
      };
      final offer = await pc.createOffer(offerConstraints);
      await pc.setLocalDescription(offer);
      authProvider.socketService.socket?.emit('call_offer', {
        'targetUserId': widget.remoteUserId,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'callType': widget.isAudioOnly ? 'audio' : 'video',
        'conversationId': widget.conversationId,
        'callerName': authProvider.user?['username'] ?? 'User',
        'callerAvatar': authProvider.user?['avatarUrl'],
      });
    } catch (e) {
      debugPrint('[WebRTC] _startCall error: $e');
      if (mounted) setState(() => _status = 'Failed to start call');
    }
  }

  Future<void> _acceptCall() async {
    SoundService().stopRingtone();
    setState(() => _status = 'Connecting...');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['id'];
    if (userId != null && (authProvider.socketService.socket == null || !authProvider.socketService.isConnected)) {
      await authProvider.socketService.connect(userId);
    }
    if (authProvider.socketService.socket == null) return;

    final success = await _initWebRTC();
    if (!mounted) return;
    if (!success) {
      setState(() { _hardwareFailed = true; _status = 'Hardware not supported'; });
      authProvider.socketService.socket?.emit('call_reject', {
        'callerId': widget.remoteUserId,
        'conversationId': widget.conversationId,
        'callType': widget.isAudioOnly ? 'audio' : 'video',
      });
      return;
    }

    _timeoutTimer?.cancel();
    setState(() {
      _callActive = true;
      _status = 'Connected';
      CallScreen.isCallActiveNotifier.value = true;
    });

    if (widget.initialOffer != null) {
      try {
        final pc = await _createPeerConnection(widget.remoteUserId);
        final offer = RTCSessionDescription(widget.initialOffer!['sdp'], widget.initialOffer!['type']);
        await pc.setRemoteDescription(offer);
        await _flushIceCandidates(widget.remoteUserId);
        final answerConstraints = <String, dynamic>{
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': widget.isAudioOnly ? 0 : 1,
        };
        final answer = await pc.createAnswer(answerConstraints);
        await pc.setLocalDescription(answer);
        authProvider.socketService.socket?.emit('call_answer', {
          'callerId': widget.remoteUserId,
          'answer': {'sdp': answer.sdp, 'type': answer.type},
        });
        _startTimer();
      } catch (e) {
        debugPrint('[WebRTC] _acceptCall error: $e');
      }
    } else {
      // initialOffer was null (e.g. launched from FCM push notification) -> request SDP offer from caller
      try {
        await _createPeerConnection(widget.remoteUserId);
        authProvider.socketService.socket?.emit('request_call_offer', {
          'callerId': widget.remoteUserId,
          'conversationId': widget.conversationId,
        });
      } catch (e) {
        debugPrint('[WebRTC] _acceptCall offer request error: $e');
      }
    }
  }

  void _rejectCall() {
    SoundService().stopRingtone();
    _timeoutTimer?.cancel();
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    socket?.emit('call_reject', {
      'callerId': widget.remoteUserId,
      'conversationId': widget.conversationId,
      'callType': widget.isAudioOnly ? 'audio' : 'video',
    });
    _endCallLocally('Call declined');
  }

  Future<void> _endCall() async {
    if (_isDisposed) return;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?['id'];
      final socket = _socket ?? authProvider.socketService.socket;

      final targetPeers = <String>{
        widget.remoteUserId,
        ..._peerConnections.keys,
        ..._participants.keys,
      }.where((id) => id.isNotEmpty && id != userId).toSet();

      for (final peerId in targetPeers) {
        final payloadData = jsonEncode({
          'peerId': peerId,
          'conversationId': widget.conversationId,
          'callType': widget.isAudioOnly ? 'audio' : 'video',
          'status': _callActive ? 'connected' : 'missed',
          'duration': _callDuration,
          'callerId': widget.isIncoming ? widget.remoteUserId : userId,
        });
        final encryptedPayload = await CryptoService().encryptLocalString(payloadData);
        socket?.emit('call_end', {
          'peerId': peerId,
          'conversationId': widget.conversationId,
          'encryptedData': encryptedPayload,
          'callType': widget.isAudioOnly ? 'audio' : 'video',
          'status': _callActive ? 'connected' : 'missed',
          'duration': _callDuration,
          'callerId': widget.isIncoming ? widget.remoteUserId : userId,
        });
      }
    } catch (e) {
      debugPrint('[_endCall] error emitting call_end: $e');
    }
    _endCallLocally('Call ended');
  }

  // End call with a single specific participant (group call)
  Future<void> _endCallWith(String peerId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['id'];
    final payloadData = jsonEncode({
      'peerId': peerId,
      'conversationId': widget.conversationId,
      'callType': widget.isAudioOnly ? 'audio' : 'video',
      'status': 'connected',
      'duration': _callDuration,
      'callerId': widget.isIncoming ? widget.remoteUserId : userId,
    });
    final encryptedPayload = await CryptoService().encryptLocalString(payloadData);
    authProvider.socketService.socket?.emit('call_end', {
      'peerId': peerId,
      'conversationId': widget.conversationId,
      'encryptedData': encryptedPayload,
      'callType': widget.isAudioOnly ? 'audio' : 'video',
      'status': 'connected',
      'duration': _callDuration,
      'callerId': widget.isIncoming ? widget.remoteUserId : userId,
    });
    _removeParticipant(peerId);
  }

  void _endCallLocally(String reason) {
    CallScreen.activeConversationId = null;
    CallScreen.activeCallState = null;
    CallScreen.isCallActiveNotifier.value = false;
    CallScreen.callEndedNotifier.value = reason;
    CallScreen.isMutedNotifier.value = false;
    CallScreen.isSpeakerOnNotifier.value = false;
    SoundService().stopRingtone();
    try { flutterLocalNotificationsPlugin.cancelAll(); } catch (_) {}
    _callTimer?.cancel();
    _timeoutTimer?.cancel();
    _callActive = false;
    try {
      _pipChannel.invokeMethod('setCallActive', {'active': false});
    } catch (_) {}
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream = null;
    // Dispose all remote renderers
    for (final r in _remoteRenderers.values) {
      r.srcObject = null;
      r.dispose();
    }
    _remoteRenderers.clear();
    // Dispose all persistent remote streams
    for (final s in _remoteStreams.values) {
      s.getTracks().forEach((t) => t.stop());
      s.dispose();
    }
    _remoteStreams.clear();
    // Close and dispose all peer connections
    for (final pc in _peerConnections.values) {
      pc.close();
      pc.dispose();
    }
    _peerConnections.clear();
    _iceCandidateQueues.clear();
    if (!mounted) return;
    setState(() => _status = reason);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _toggleMute() {
    final tracks = _localStream?.getAudioTracks();
    if (tracks != null && tracks.isNotEmpty) {
      final track = tracks[0];
      track.enabled = !track.enabled;
      setState(() => _isMuted = !track.enabled);
      CallScreen.isMutedNotifier.value = _isMuted;
    }
  }

  void _toggleVideo() {
    if (widget.isAudioOnly || _localStream == null) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isNotEmpty) {
      final track = tracks[0];
      track.enabled = !track.enabled;
      setState(() => _isVideoOff = !track.enabled);
    }
  }

  void _switchCamera() async {
    if (widget.isAudioOnly || _localStream == null) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isNotEmpty) {
      await Helper.switchCamera(tracks[0]);
      if (mounted) setState(() {});
    }
  }

  String _audioOutputMode = 'earpiece';
  bool _hasBluetoothConnected = false;
  String? _userSelectedRoute;
  String? _connectedBtDeviceName;
  Timer? _audioRouteCheckTimer;

  Future<void> _checkAudioDevicesAndRoute() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final btDevices = devices.where((d) {
        final label = d.label.toLowerCase();
        final id = d.deviceId.toLowerCase();
        final group = d.groupId?.toLowerCase() ?? '';
        return label.contains('bluetooth') ||
            label.contains('headset') ||
            label.contains('earbuds') ||
            label.contains('airpods') ||
            label.contains('bt') ||
            label.contains('wireless') ||
            label.contains('buds') ||
            label.contains('pod') ||
            label.contains('handsfree') ||
            id.contains('bluetooth') ||
            id.contains('sco') ||
            id.contains('headset') ||
            group.contains('bluetooth');
      }).toList();

      if (btDevices.isNotEmpty) {
        _hasBluetoothConnected = true;
        final bt = btDevices.first;
        _connectedBtDeviceName = bt.label.isNotEmpty ? bt.label : 'Bluetooth Headset';
        if (_userSelectedRoute == null || _userSelectedRoute == 'bluetooth') {
          _audioOutputMode = 'bluetooth';
          _isSpeakerOn = false;
          await Helper.setSpeakerphoneOn(false);
          if (bt.deviceId.isNotEmpty) {
            await Helper.selectAudioOutput(bt.deviceId);
          }
        }
      } else {
        _hasBluetoothConnected = false;
        _connectedBtDeviceName = null;
        if (_audioOutputMode == 'bluetooth') {
          _audioOutputMode = (_userSelectedRoute != null && _userSelectedRoute != 'bluetooth')
              ? _userSelectedRoute!
              : 'earpiece';
        }
        _isSpeakerOn = (_audioOutputMode == 'speaker');
        await Helper.setSpeakerphoneOn(_isSpeakerOn);
      }
      CallScreen.isSpeakerOnNotifier.value = _isSpeakerOn;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[AudioRoute] Device check error: $e');
    }
  }

  void _selectAudioOutputMode(String mode) async {
    _userSelectedRoute = mode;
    setState(() {
      _audioOutputMode = mode;
      _isSpeakerOn = (mode == 'speaker');
    });
    CallScreen.isSpeakerOnNotifier.value = _isSpeakerOn;
    try {
      if (mode == 'speaker') {
        _isSpeakerOn = true;
        await Helper.setSpeakerphoneOn(true);
      } else if (mode == 'earpiece') {
        _isSpeakerOn = false;
        await Helper.setSpeakerphoneOn(false);
      } else if (mode == 'bluetooth') {
        _isSpeakerOn = false;
        await Helper.setSpeakerphoneOn(false);
        try {
          final devices = await navigator.mediaDevices.enumerateDevices();
          final btDevices = devices.where((d) {
            final label = d.label.toLowerCase();
            final id = d.deviceId.toLowerCase();
            return label.contains('bluetooth') ||
                label.contains('headset') ||
                label.contains('earbuds') ||
                label.contains('airpods') ||
                label.contains('bt') ||
                label.contains('wireless') ||
                id.contains('bluetooth') ||
                id.contains('sco') ||
                id.contains('headset');
          }).toList();
          if (btDevices.isNotEmpty && btDevices.first.deviceId.isNotEmpty) {
            await Helper.selectAudioOutput(btDevices.first.deviceId);
          }
        } catch (e) {
          debugPrint('[AudioRoute] Bluetooth selection error: $e');
        }
      }
    } catch (e) {
      debugPrint('[AudioRoute] Routing error: $e');
    }
  }

  void _toggleSpeaker() {
    _showAudioOutputSelector();
  }

  void _showAudioOutputSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Audio Output Route',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _audioOutputMode == 'bluetooth'
                          ? const Color(0xFF00A884).withValues(alpha: 0.2)
                          : (_audioOutputMode == 'speaker'
                              ? Colors.purpleAccent.withValues(alpha: 0.2)
                              : Colors.blueAccent.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _audioOutputMode.toUpperCase(),
                      style: TextStyle(
                        color: _audioOutputMode == 'bluetooth'
                            ? const Color(0xFF00A884)
                            : (_audioOutputMode == 'speaker' ? Colors.purpleAccent : Colors.blueAccent),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_hasBluetoothConnected) ...[
                _buildAudioOptionTile(
                  title: _connectedBtDeviceName ?? 'Bluetooth Device / Headset',
                  subtitle: 'Audio active on Bluetooth',
                  icon: Icons.bluetooth_audio_rounded,
                  color: const Color(0xFF00A884),
                  isSelected: _audioOutputMode == 'bluetooth',
                  onTap: () {
                    _selectAudioOutputMode('bluetooth');
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 10),
              ],
              _buildAudioOptionTile(
                title: 'Ear Speaker (Phone Earpiece)',
                subtitle: 'Default private in-ear call audio',
                icon: Icons.phone_in_talk_rounded,
                color: Colors.blueAccent,
                isSelected: _audioOutputMode == 'earpiece',
                onTap: () {
                  _selectAudioOutputMode('earpiece');
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 10),
              _buildAudioOptionTile(
                title: 'Loudspeaker (Speakerphone)',
                subtitle: 'Hands-free loud call speaker',
                icon: Icons.volume_up_rounded,
                color: Colors.purpleAccent,
                isSelected: _audioOutputMode == 'speaker',
                onTap: () {
                  _selectAudioOutputMode('speaker');
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAudioOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.15) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle_rounded, color: color, size: 24)
            : null,
        onTap: onTap,
      ),
    );
  }

  Future<void> _toggleScreenShare() async {
    if (widget.isAudioOnly || _hardwareFailed) return;

    if (_isScreenSharing) {
      _screenStream?.getTracks().forEach((track) => track.stop());
      _screenStream?.dispose();
      _screenStream = null;
      try {
        if (Platform.isAndroid) await _channel.invokeMethod('stopScreenShareService');
      } catch (_) {}

      if (_localStream != null) {
        final videoTracks = _localStream!.getVideoTracks();
        final micAudioTracks = _localStream!.getAudioTracks();
        if (videoTracks.isNotEmpty) {
          final videoTrack = videoTracks.first;
          for (final pc in _peerConnections.values) {
            final senders = await pc.getSenders();
            for (final sender in senders) {
              if (sender.track?.kind == 'video') await sender.replaceTrack(videoTrack);
            }
            // Restore mic audio
            if (micAudioTracks.isNotEmpty) {
              final micTrack = micAudioTracks.first;
              micTrack.enabled = true;
              for (final sender in await pc.getSenders()) {
                if (sender.track?.kind == 'audio') await sender.replaceTrack(micTrack);
              }
            }
          }
        }
        _localRenderer.srcObject = _localStream;
      }
      setState(() => _isScreenSharing = false);
    } else {
      try {
        if (Platform.isAndroid) await _channel.invokeMethod('startScreenShareService');
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          _screenStream = await navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': true});
        } catch (_) {
          _screenStream = await navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': false});
        }
        if (_screenStream != null) {
          final videoTracks = _screenStream!.getVideoTracks();
          final audioTracks = _screenStream!.getAudioTracks();
          if (videoTracks.isNotEmpty) {
            final screenVideoTrack = videoTracks.first;
            screenVideoTrack.enabled = true;
            for (final pc in _peerConnections.values) {
              final senders = await pc.getSenders();
              for (final sender in senders) {
                if (sender.track?.kind == 'video') await sender.replaceTrack(screenVideoTrack);
              }
              // Inject screen audio or ensure mic audio track is active & routed to speaker
              if (audioTracks.isNotEmpty) {
                final screenAudioTrack = audioTracks.first;
                screenAudioTrack.enabled = true;
                for (final sender in await pc.getSenders()) {
                  if (sender.track?.kind == 'audio') await sender.replaceTrack(screenAudioTrack);
                }
              } else if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
                final micTrack = _localStream!.getAudioTracks().first;
                micTrack.enabled = true;
                for (final sender in await pc.getSenders()) {
                  if (sender.track?.kind == 'audio') await sender.replaceTrack(micTrack);
                }
              }
            }
            _checkAudioDevicesAndRoute();
            // Keep local renderer on local camera stream or null to avoid infinite recursive screen mirror
            _localRenderer.srcObject = _localStream;
            setState(() => _isScreenSharing = true);
            screenVideoTrack.onEnded = () {
              if (mounted && _isScreenSharing) _toggleScreenShare();
            };
          }
        }
      } catch (e) {
        try { if (Platform.isAndroid) await _channel.invokeMethod('stopScreenShareService'); } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Screen sharing failed.')));
      }
    }
  }

  void _showAddParticipantModal() async {
    if (_participants.length >= 11) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group calls limited to 12 participants.')));
      return;
    }
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    final contacts = await ContactService.getContacts(token);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final available = contacts.where((c) {
          final id = (c['contact']['id'] ?? c['contact']['_id'])?.toString();
          return id != null && !_participants.containsKey(id) && id != widget.remoteUserId;
        }).toList();
        return Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text('Add to Call (Up to 12 Members)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold))),
            Expanded(
              child: available.isEmpty
                ? Center(child: Text('No contacts available to add', style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.builder(
                  itemCount: available.length,
                  itemBuilder: (ctx, i) {
                    final c = available[i];
                    final name = (c['savedName'] ?? c['contact']['username'] ?? 'User').toString();
                    return ListTile(
                      leading: ColorAvatar(name: name, radius: 20, fontSize: 16),
                      title: Text(name, style: TextStyle(color: AppTheme.textPrimary)),
                      onTap: () { Navigator.pop(ctx); _addParticipant(c); },
                    );
                  },
                ),
            ),
          ],
        );
      },
    );
  }

  void _addParticipant(dynamic contact) async {
    final newUserId = (contact['contact']['id'] ?? contact['contact']['_id'])?.toString();
    if (newUserId == null || newUserId.isEmpty) return;
    final newUserName = (contact['savedName'] ?? contact['contact']['username'] ?? 'User').toString();
    final newUserAvatar = contact['contact']['avatarUrl'];
    setState(() => _participants[newUserId] = {'username': newUserName, 'avatarUrl': newUserAvatar});
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final myUser = authProvider.user;
    final myUserName = myUser?['username'] ?? 'User';
    final socket = authProvider.socketService.socket;

    try {
      // Create offer from me to new user
      final pc = await _createPeerConnection(newUserId);
      final offerConstraints = <String, dynamic>{
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': widget.isAudioOnly ? 0 : 1,
      };
      final offer = await pc.createOffer(offerConstraints);
      final optimizedSdp = _optimizeSdpForHdCall(offer.sdp, isAudioOnly: widget.isAudioOnly);
      final optimizedOffer = RTCSessionDescription(optimizedSdp, offer.type);
      await pc.setLocalDescription(optimizedOffer);
      socket?.emit('call_offer', {
        'targetUserId': newUserId,
        'offer': {'sdp': optimizedOffer.sdp, 'type': optimizedOffer.type},
        'callType': widget.isAudioOnly ? 'audio' : 'video',
        'conversationId': widget.conversationId,
        'callerName': myUserName,
        'callerAvatar': myUser?['avatarUrl'],
      });

      // Notify all existing participants to mesh connect to new user
      for (final existingPeerId in _participants.keys) {
        if (existingPeerId != newUserId) {
          socket?.emit('user_added_to_call', {
            'targetUserId': existingPeerId,
            'newUserId': newUserId,
            'newUserName': newUserName,
            'conversationId': widget.conversationId,
            'callType': widget.isAudioOnly ? 'audio' : 'video',
          });
        }
      }
    } catch (e) {
      debugPrint('[WebRTC] _addParticipant error: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true; // Set FIRST so all native callbacks bail out immediately
    WidgetsBinding.instance.removeObserver(this);
    CallScreen.activeConversationId = null;
    CallScreen.activeCallState = null;
    SoundService().stopRingtone();
    _callTimer?.cancel();
    _timeoutTimer?.cancel();
    _audioRouteCheckTimer?.cancel();
    // Use stored _socket reference to remove listeners — NEVER call Provider.of(context) in dispose()
    _socket?.off('call_answered', _onCallAnswered);
    _socket?.off('call_rejected', _onCallRejected);
    _socket?.off('call_ended', _onCallEnded);
    _socket?.off('ice_candidate', _onIceCandidate);
    _socket?.off('user_added_to_call', _onUserAddedToCall);
    _socket?.off('call_incoming', _onCallIncoming);
    _socket?.off('screen_share_request', _onScreenShareRequest);
    _socket?.off('request_call_offer', _onRequestCallOffer);
    _socket?.off('call_offer', _onCallOffer);
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    for (final pc in _peerConnections.values) { pc.close(); pc.dispose(); }
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) { r.dispose(); }
    for (final s in _remoteStreams.values) { s.dispose(); }
    super.dispose();
  }

  String _formatDuration(int s) => '${(s ~/ 3600 > 0 ? '${(s ~/ 3600).toString().padLeft(2, '0')}:' : '')}${(s % 3600 ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  bool get _isGroupCall => _participants.length > 1;

  // 1-on-1 video: Fullscreen remote/local + Draggable PiP with switch camera button
  // Double-tap anywhere or tap PiP switches/swaps videos between main screen and PiP
  Widget _buildOneToOneVideoView() {
    final remoteRenderer = _remoteRenderers[widget.remoteUserId];
    final bool hasRemoteVideo = remoteRenderer != null &&
        remoteRenderer.srcObject != null &&
        remoteRenderer.srcObject!.getVideoTracks().isNotEmpty &&
        remoteRenderer.srcObject!.getVideoTracks().any((t) => t.enabled);
    final bool hasLocalVideo = !_isVideoOff &&
        _localRenderer.srcObject != null &&
        _localRenderer.srcObject!.getVideoTracks().isNotEmpty;
    
    // If not swapped: Main is Remote, PiP is Local
    // If swapped: Main is Local, PiP is Remote
    RTCVideoRenderer? mainRenderer;
    RTCVideoRenderer? pipRenderer;
    bool mainMirror = false;
    bool pipMirror = false;

    if (_isScreenSharing) {
      mainRenderer = _localRenderer;
      pipRenderer = hasRemoteVideo ? remoteRenderer : null;
      mainMirror = false;
      pipMirror = false;
    } else if (!_isSwappedVideo) {
      mainRenderer = hasRemoteVideo ? remoteRenderer : (hasLocalVideo ? _localRenderer : null);
      pipRenderer = (hasRemoteVideo && hasLocalVideo) ? _localRenderer : null;
      mainMirror = (mainRenderer == _localRenderer) && !_isScreenSharing;
      pipMirror = !_isScreenSharing;
    } else {
      mainRenderer = hasLocalVideo ? _localRenderer : (hasRemoteVideo ? remoteRenderer : null);
      pipRenderer = (hasLocalVideo && hasRemoteVideo) ? remoteRenderer : null;
      mainMirror = (mainRenderer == _localRenderer) && !_isScreenSharing;
      pipMirror = false;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControlsVisibility,
      onDoubleTap: () {
        setState(() {
          _isSwappedVideo = !_isSwappedVideo;
        });
      },
      child: Stack(
        children: [
          // Fullscreen main video
          Positioned.fill(
            child: (mainRenderer != null && mainRenderer.srcObject != null)
                ? RTCVideoView(
                    mainRenderer,
                    objectFit: _isScreenSharing ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: mainMirror,
                  )
                : Container(
                    color: const Color(0xFF0B141B),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ColorAvatar(name: widget.remoteUserName, radius: 64, fontSize: 36),
                          const SizedBox(height: 16),
                          Text(
                            _status == 'Connected' ? 'Connecting video...' : _status,
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Draggable PiP (WhatsApp-style rounded with flip camera button and tap-to-swap)
          if (pipRenderer != null && !_isVideoOff)
            Positioned(
              right: _localVideoRight,
              bottom: _localVideoBottom,
              width: 125,
              height: 180,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isSwappedVideo = !_isSwappedVideo;
                  });
                },
                onDoubleTap: () {
                  setState(() {
                    _isSwappedVideo = !_isSwappedVideo;
                  });
                },
                onPanUpdate: (d) {
                  setState(() {
                    _localVideoRight = (_localVideoRight - d.delta.dx).clamp(8.0, 260.0);
                    _localVideoBottom = (_localVideoBottom - d.delta.dy).clamp(80.0, 560.0);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RTCVideoView(
                          pipRenderer,
                          mirror: pipMirror,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),

                        // Switch / Swap videos indicator button (Top-Left)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isSwappedVideo = !_isSwappedVideo;
                              });
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.swap_horizontal_circle_outlined, color: Colors.white, size: 18),
                            ),
                          ),
                        ),

                        // Flip Camera Button inside PiP (Top-Right)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _switchCamera,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Group call: Responsive dynamic grid
  Widget _buildGroupVideoGrid() {
    final List<Widget> views = [];

    _participants.forEach((id, data) {
      final renderer = _remoteRenderers[id];
      final usernameStr = (data['username'] ?? 'User').toString();
      views.add(Stack(
        fit: StackFit.expand,
        children: [
          renderer != null
            ? RTCVideoView(
                renderer,
                objectFit: _isScreenSharing ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Container(
                color: const Color(0xFF111B21),
                child: Center(
                  child: ColorAvatar(
                    name: usernameStr,
                    radius: views.length > 4 ? 26 : 36,
                    fontSize: views.length > 4 ? 16 : 22,
                  ),
                ),
              ),
          Positioned(
            bottom: 6, left: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    usernameStr,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showEndCallWithDialog(id, usernameStr),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ));
    });

    // Add local view
    if (!widget.isAudioOnly && !_isVideoOff) {
      views.add(Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            _localRenderer,
            mirror: !_isScreenSharing,
            objectFit: _isScreenSharing ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Positioned(
            bottom: 6, left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
              child: const Text('You', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ));
    }

    if (views.isEmpty) return const SizedBox.shrink();
    Widget gridContent;
    if (views.length == 1) {
      gridContent = views.first;
    } else if (views.length == 2) {
      gridContent = Column(children: [Expanded(child: views[0]), const SizedBox(height: 2), Expanded(child: views[1])]);
    } else if (views.length == 3) {
      gridContent = Column(
        children: [
          Expanded(child: Row(children: [Expanded(child: views[0]), const SizedBox(width: 2), Expanded(child: views[1])])),
          const SizedBox(height: 2),
          Expanded(child: views[2]),
        ],
      );
    } else if (views.length == 4) {
      gridContent = Column(
        children: [
          Expanded(child: Row(children: [Expanded(child: views[0]), const SizedBox(width: 2), Expanded(child: views[1])])),
          const SizedBox(height: 2),
          Expanded(child: Row(children: [Expanded(child: views[2]), const SizedBox(width: 2), Expanded(child: views[3])])),
        ],
      );
    } else {
      final int crossAxisCount = views.length <= 6 ? 2 : 3;
      gridContent = GridView.builder(
        physics: views.length <= 6 ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: crossAxisCount == 2 ? 0.75 : 0.65,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: views.length,
        itemBuilder: (ctx, i) => views[i],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControlsVisibility,
      child: gridContent,
    );
  }

  void _showEndCallWithDialog(String userId, String userName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('End call with $userName?', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _endCallWith(userId); },
            child: const Text('End Call', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Color _fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  // Permanent Plain Dark Solid Background (No theme-driven changes or dots)
  Widget _buildThemeBackground(ChatThemeModel chatTheme, WallpaperConfig wallpaperConfig) {
    return Container(
      color: const Color(0xFF0B141B),
    );
  }

  // WhatsApp-Style Incoming Call Screen
  Widget _buildIncomingCallScreen(ChatThemeModel chatTheme, WallpaperConfig wallpaperConfig) {
    return Stack(
      children: [
        // 1. Permanent Plain Dark Background
        Positioned.fill(
          child: _buildThemeBackground(chatTheme, wallpaperConfig),
        ),

        // 2. Caller Info Section (Top Half)
        Positioned(
          top: 60,
          left: 20,
          right: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Clean Avatar on Plain Background
              if (widget.remoteAvatarUrl != null && widget.remoteAvatarUrl!.trim().isNotEmpty)
                CircleAvatar(
                  radius: 54,
                  backgroundImage: widget.remoteAvatarUrl!.startsWith('http')
                      ? NetworkImage(widget.remoteAvatarUrl!)
                      : NetworkImage('https://dolsyx-app.onrender.com${widget.remoteAvatarUrl!}'),
                )
              else
                ColorAvatar(name: widget.remoteUserName, radius: 54, fontSize: 42),

              const SizedBox(height: 20),

              // Caller Name
              Text(
                widget.remoteUserName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 6),

              // Call Type Subtitle
              Text(
                widget.isAudioOnly ? 'DOLSYX voice call' : 'DOLSYX video call',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),

              const SizedBox(height: 10),

              // Single-line End-to-End Encrypted Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, color: Color(0xFFFFD700), size: 12),
                    const SizedBox(width: 5),
                    Text(
                      'End-to-end encrypted',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3. Center Pulsating Upward Chevrons (Swipe Up Indicator with live drag feedback)
        Positioned(
          bottom: 144 + _swipeUpOffset * 0.45,
          left: 0,
          right: 0,
          child: Column(
            children: [
              Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white.withValues(alpha: 0.25 + (_swipeUpOffset / 200).clamp(0.0, 0.75)), size: 28),
              Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white.withValues(alpha: 0.5 + (_swipeUpOffset / 200).clamp(0.0, 0.5)), size: 28),
              Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white.withValues(alpha: 0.8), size: 28),
              const SizedBox(height: 4),
              Text(
                _swipeUpOffset > 50 ? 'Release to answer' : 'Swipe up or tap to answer',
                style: TextStyle(
                  color: _swipeUpOffset > 50 ? const Color(0xFF25D366) : Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: _swipeUpOffset > 50 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),

        // 4. Bottom Action Buttons (Decline, Draggable Accept, Quick Reply)
        Positioned(
          bottom: 44,
          left: 32,
          right: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Decline Button (Red)
              GestureDetector(
                onTap: _rejectCall,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEA0038),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                ),
              ),

              // Draggable Prominent Accept Button (WhatsApp Green - Swipe Up to Lift Call)
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null) {
                    setState(() {
                      _swipeUpOffset = (_swipeUpOffset - details.primaryDelta!).clamp(0.0, 140.0);
                    });
                  }
                },
                onVerticalDragEnd: (details) {
                  if (_swipeUpOffset > 55.0) {
                    _acceptCall();
                  } else {
                    setState(() => _swipeUpOffset = 0.0);
                  }
                },
                onTap: _acceptCall,
                child: Transform.translate(
                  offset: Offset(0, -_swipeUpOffset),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF25D366).withValues(alpha: 0.4 + (_swipeUpOffset / 200).clamp(0.0, 0.4)),
                          blurRadius: 20 + _swipeUpOffset * 0.2,
                          spreadRadius: 4 + _swipeUpOffset * 0.1,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.isAudioOnly ? Icons.call_rounded : Icons.videocam_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),

              // Quick Message Reply Button (Dark Charcoal)
              GestureDetector(
                onTap: _showQuickReplyModal,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2428).withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Audio Call UI with WhatsApp Center Avatar (Theme-Aware Matching Screenshot 2)
  Widget _buildAudioCallScreen(ChatThemeModel chatTheme, WallpaperConfig wallpaperConfig) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControlsVisibility,
      child: Stack(
        children: [
          // 1. Dynamic Theme/Wallpaper Background
          Positioned.fill(
            child: _buildThemeBackground(chatTheme, wallpaperConfig),
          ),

          // 2. Center Large Avatar with Theme Glowing Aura
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isGroupCall) ...[
                  if (widget.remoteAvatarUrl != null && widget.remoteAvatarUrl!.trim().isNotEmpty)
                    CircleAvatar(
                      radius: 72,
                      backgroundImage: widget.remoteAvatarUrl!.startsWith('http')
                          ? NetworkImage(widget.remoteAvatarUrl!)
                          : NetworkImage('https://dolsyx-app.onrender.com${widget.remoteAvatarUrl!}'),
                    )
                  else
                    ColorAvatar(name: widget.remoteUserName, radius: 72, fontSize: 52),
                ] else ...[
                  Wrap(
                    spacing: 20, runSpacing: 16, alignment: WrapAlignment.center,
                    children: _participants.values.map((p) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ColorAvatar(name: p['username'] ?? '?', radius: 44, fontSize: 26),
                        const SizedBox(height: 6),
                        Text(p['username'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    )).toList(),
                  ),
                ],
                if (!_callActive) ...[
                  const SizedBox(height: 24),
                  Text(
                    _status,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 16),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final wallpaperProvider = Provider.of<WallpaperProvider>(context);
    final chatTheme = themeProvider.currentTheme;
    final wallpaperConfig = wallpaperProvider.getWallpaperForChat(widget.conversationId);

    return PopScope(
      canPop: !_callActive,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141B),
        body: SafeArea(
          child: Stack(
            children: [
              // === 1. MAIN CALL CONTENT (Permanent Plain Dark Background) ===
              if (widget.isIncoming && !_callActive)
                _buildIncomingCallScreen(chatTheme, wallpaperConfig)
              else if (!widget.isAudioOnly && _callActive)
                Positioned.fill(
                  child: _isGroupCall ? _buildGroupVideoGrid() : _buildOneToOneVideoView(),
                )
              else
                Positioned.fill(
                  child: _buildAudioCallScreen(chatTheme, wallpaperConfig),
                ),

              // === 2. TOP BANNER / HEADER (Matching Screenshots 1 & 2) ===
              if (_callActive || (!widget.isIncoming && !_callActive))
                Positioned(
                  top: 10,
                  left: 16,
                  right: 16,
                  child: AnimatedOpacity(
                    opacity: _areControlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_areControlsVisible,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 🔒 Single-line End-to-End Encrypted Banner (Top Center)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_rounded, color: Color(0xFFFFD700), size: 11),
                                const SizedBox(width: 4),
                                Text(
                                  'End-to-end encrypted',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Top-Left: Minimize Button (Semi-transparent circle)
                              GestureDetector(
                                onTap: _minimizeCall,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_fullscreen_rounded, color: Colors.white, size: 20),
                                ),
                              ),

                              // Top-Center: Caller Name & Call Duration / Status
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _isGroupCall ? 'Group Call (${_participants.length + 1})' : widget.remoteUserName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _callActive ? _formatDuration(_callDuration) : _status,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),

                              // Top-Right: Add Participant Button (Semi-transparent circle)
                              GestureDetector(
                                onTap: _showAddParticipantModal,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // === 2.5 FLOATING "STOP SCREEN SHARE" PILL ===
              if (_isScreenSharing && _callActive)
                Positioned(
                  top: 76,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEA0038), Color(0xFFC0002A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEA0038).withValues(alpha: 0.5),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.screen_share_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Sharing your screen',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: _toggleScreenShare,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.stop_rounded, color: Color(0xFFEA0038), size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Stop Sharing',
                                    style: TextStyle(
                                      color: Color(0xFFEA0038),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // === 3. FLOATING BOTTOM CONTROL CAPSULE (Matching Screenshots 1 & 2) ===
              if (_callActive || (!widget.isIncoming && !_callActive))
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: AnimatedOpacity(
                    opacity: _areControlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_areControlsVisible,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2428).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(36),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // 1. More Options (•••)
                            _buildCapsuleButton(
                              icon: Icons.more_horiz_rounded,
                              bgColor: Colors.white.withValues(alpha: 0.12),
                              iconColor: Colors.white,
                              onTap: _showMoreCallOptions,
                            ),

                            // 2. Video Camera / Screen Share Toggle
                            if (_isScreenSharing)
                              _buildCapsuleButton(
                                icon: Icons.stop_screen_share_rounded,
                                bgColor: const Color(0xFFEA0038),
                                iconColor: Colors.white,
                                onTap: _toggleScreenShare,
                              )
                            else if (!widget.isAudioOnly)
                              _buildCapsuleButton(
                                icon: _isVideoOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                                bgColor: _isVideoOff ? Colors.white : Colors.white.withValues(alpha: 0.12),
                                iconColor: _isVideoOff ? Colors.black : Colors.white,
                                onTap: _toggleVideo,
                              )
                            else
                              _buildCapsuleButton(
                                icon: Icons.videocam_rounded,
                                bgColor: Colors.white.withValues(alpha: 0.12),
                                iconColor: Colors.white70,
                                onTap: _toggleVideo,
                              ),

                            // 3. Audio Route Toggle (Bluetooth / Loudspeaker / Ear Speaker)
                            _buildCapsuleButton(
                              icon: _audioOutputMode == 'bluetooth'
                                  ? Icons.bluetooth_audio_rounded
                                  : (_audioOutputMode == 'speaker' ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded),
                              bgColor: _audioOutputMode == 'bluetooth'
                                  ? const Color(0xFF00A884)
                                  : (_audioOutputMode == 'speaker'
                                      ? Colors.purpleAccent.withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: 0.15)),
                              iconColor: _audioOutputMode == 'bluetooth'
                                  ? Colors.white
                                  : (_audioOutputMode == 'speaker' ? Colors.purpleAccent : Colors.white),
                              onTap: _toggleSpeaker,
                            ),

                            // 4. Mute Microphone (White bg with red icon when muted!)
                            _buildCapsuleButton(
                              icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                              bgColor: _isMuted ? Colors.white : Colors.white.withValues(alpha: 0.12),
                              iconColor: _isMuted ? const Color(0xFFEA0038) : Colors.white,
                              onTap: _toggleMute,
                            ),

                            // 5. Red End Call Button
                            _buildCapsuleButton(
                              icon: Icons.call_end_rounded,
                              bgColor: const Color(0xFFEA0038),
                              iconColor: Colors.white,
                              onTap: _endCall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapsuleButton({
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: 24),
        ),
      ),
    );
  }
}




