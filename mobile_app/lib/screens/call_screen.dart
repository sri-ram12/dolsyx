import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../services/sound_service.dart';
import '../services/contact_service.dart';
import 'chat_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/e2ee/crypto_service.dart';

class CallScreen extends StatefulWidget {
  final String conversationId;
  final String remoteUserId;
  final String remoteUserName;
  final String? remoteAvatarUrl;
  final bool isAudioOnly;
  final bool isIncoming;
  final bool autoAccept;
  final Map<String, dynamic>? initialOffer;

  const CallScreen({
    super.key,
    required this.conversationId,
    required this.remoteUserId,
    required this.remoteUserName,
    this.remoteAvatarUrl,
    required this.isAudioOnly,
    required this.isIncoming,
    this.autoAccept = false,
    this.initialOffer,
  });

  static String? activeConversationId;
  static ValueNotifier<bool> isCallActiveNotifier = ValueNotifier<bool>(false);
  static dynamic activeCallState;

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

  // 1-on-1 PiP dragging
  double _localVideoRight = 20;
  double _localVideoBottom = 140;

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
    _participants[widget.remoteUserId] = {
      'username': widget.remoteUserName,
      'avatarUrl': widget.remoteAvatarUrl,
    };

    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'onCallTaskRemoved') {
        if (_callActive) {
          _endCall();
        }
      }
    });

    _initRenderers();
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
      if (widget.autoAccept) {
        _acceptCall();
      } else {
        SoundService().startRingtone();
        if (mounted) setState(() => _status = 'Incoming Call...');
      }
    } else {
      SoundService().startRingbackTone();
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
      final answererId = data['answererId']?.toString() ?? widget.remoteUserId;
      if (data['answer'] != null) {
        final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
        final targetPc = _peerConnections[answererId] ?? _peerConnections[widget.remoteUserId] ?? (_peerConnections.isNotEmpty ? _peerConnections.values.first : null);
        if (targetPc != null) {
          try {
            await targetPc.setRemoteDescription(answer);
          } catch (e) {
            debugPrint('[WebRTC] setRemoteDescription error: $e');
          }
          if (!mounted) return;
          await _flushIceCandidates(answererId);
          if (answererId != widget.remoteUserId) {
            await _flushIceCandidates(widget.remoteUserId);
          }
        }
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
        // Ensure speaker is set correctly when connection is established
        Helper.setSpeakerphoneOn(_isSpeakerOn);
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
        // Enable speaker so remote audio is heard
        _selectAudioOutputMode(_audioOutputMode);
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
        _selectAudioOutputMode(_audioOutputMode);
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
      _selectAudioOutputMode(_audioOutputMode);
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
      if (micStatus != PermissionStatus.granted) {
        debugPrint('[WebRTC] Microphone permission denied');
        return false;
      }
      if (!widget.isAudioOnly) {
        final camStatus = await Permission.camera.request();
        if (camStatus != PermissionStatus.granted) {
          debugPrint('[WebRTC] Camera permission denied — falling back to audio-only');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final lowDataMode = prefs.getBool('low_bandwidth_call_mode') ?? false;

      final videoConstraints = widget.isAudioOnly
          ? false
          : (lowDataMode
              ? {'facingMode': 'user', 'width': {'ideal': 320}, 'height': {'ideal': 240}, 'frameRate': {'ideal': 15}}
              : {'facingMode': 'user', 'width': {'ideal': 1280}, 'height': {'ideal': 720}, 'frameRate': {'ideal': 30, 'max': 30}});

      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': videoConstraints,
        });
      } catch (_) {
        // Fallback for strict Web browsers or devices
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': widget.isAudioOnly ? false : true,
        });
      }

      // Verify we actually got audio tracks — empty stream means hardware isn't ready
      if (_localStream == null || _localStream!.getAudioTracks().isEmpty) {
        debugPrint('[WebRTC] getUserMedia returned no audio tracks');
        return false;
      }

      _localRenderer.srcObject = _localStream;
      if (widget.isAudioOnly) _isVideoOff = true;

      // Always use speakerphone so remote voice is audible \u2014 user can toggle via UI
      _isSpeakerOn = true;
      Helper.setSpeakerphoneOn(widget.isIncoming ? true : false);
      _localStream?.getAudioTracks().forEach((track) {
        track.enabled = true;
      });
      return true;
    } catch (e) {
      debugPrint('[WebRTC] getUserMedia error: $e');
      return false;
    }
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
      // Explicit offer constraints are required on some Android WebRTC builds.
      // Without them, createOffer() can fail with WEBRTC_CREATE_OFFER_ERROR.
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
        'callerName': authProvider.user?['username'],
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
        // Explicit answer constraints for compatibility with Android WebRTC builds
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
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['id'];
    for (final peerId in _peerConnections.keys) {
      final payloadData = jsonEncode({
        'peerId': peerId,
        'conversationId': widget.conversationId,
        'callType': widget.isAudioOnly ? 'audio' : 'video',
        'status': _callActive ? 'connected' : 'missed',
        'duration': _callDuration,
        'callerId': widget.isIncoming ? widget.remoteUserId : userId,
      });
      final encryptedPayload = await CryptoService().encryptLocalString(payloadData);
      authProvider.socketService.socket?.emit('call_end', {
        'peerId': peerId,
        'conversationId': widget.conversationId,
        'encryptedData': encryptedPayload,
        'callType': widget.isAudioOnly ? 'audio' : 'video',
        'status': _callActive ? 'connected' : 'missed',
        'duration': _callDuration,
        'callerId': widget.isIncoming ? widget.remoteUserId : userId,
      });
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
    SoundService().stopRingtone();
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

  String _audioOutputMode = 'speaker';

  void _selectAudioOutputMode(String mode) async {
    setState(() {
      _audioOutputMode = mode;
    });
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
          final btDevice = devices.firstWhere(
            (d) => d.kind == 'audiooutput' && (
              d.label.toLowerCase().contains('bluetooth') ||
              d.label.toLowerCase().contains('headset') ||
              d.label.toLowerCase().contains('earbuds')
            ),
            orElse: () => devices.firstWhere((d) => d.kind == 'audiooutput', orElse: () => devices.first),
          );
          if (btDevice.deviceId.isNotEmpty) {
            await Helper.selectAudioOutput(btDevice.deviceId);
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
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Audio Output',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.volume_up_rounded, color: Colors.purpleAccent),
                title: const Text('Loudspeaker (Speakerphone)', style: TextStyle(color: Colors.white)),
                trailing: _audioOutputMode == 'speaker' ? const Icon(Icons.check_circle, color: Colors.purpleAccent) : null,
                onTap: () {
                  _selectAudioOutputMode('speaker');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.phone_in_talk_rounded, color: Colors.blueAccent),
                title: const Text('Ear Speaker (Phone Earpiece)', style: TextStyle(color: Colors.white)),
                trailing: _audioOutputMode == 'earpiece' ? const Icon(Icons.check_circle, color: Colors.blueAccent) : null,
                onTap: () {
                  _selectAudioOutputMode('earpiece');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bluetooth_audio_rounded, color: Colors.greenAccent),
                title: const Text('Bluetooth Device / Headset', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Connects automatically if paired', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: _audioOutputMode == 'bluetooth' ? const Icon(Icons.check_circle, color: Colors.greenAccent) : null,
                onTap: () {
                  _selectAudioOutputMode('bluetooth');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
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
              for (final sender in await pc.getSenders()) {
                if (sender.track?.kind == 'audio') await sender.replaceTrack(micAudioTracks.first);
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
            for (final pc in _peerConnections.values) {
              final senders = await pc.getSenders();
              for (final sender in senders) {
                if (sender.track?.kind == 'video') await sender.replaceTrack(screenVideoTrack);
              }
              // Also inject screen audio so remote user hears device media
              if (audioTracks.isNotEmpty) {
                final screenAudioTrack = audioTracks.first;
                for (final sender in await pc.getSenders()) {
                  if (sender.track?.kind == 'audio') await sender.replaceTrack(screenAudioTrack);
                }
              }
            }
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
    if (_participants.length >= 15) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group calls limited to 15 participants.')));
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
          final id = c['contact']['id'] ?? c['contact']['_id'];
          return !_participants.containsKey(id) && id != widget.remoteUserId;
        }).toList();
        return Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text('Add to Call', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold))),
            Expanded(
              child: available.isEmpty
                ? Center(child: Text('No contacts available', style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.builder(
                  itemCount: available.length,
                  itemBuilder: (ctx, i) {
                    final c = available[i];
                    final name = c['savedName'] ?? c['contact']['username'] ?? 'User';
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
    final newUserId = contact['contact']['id'] ?? contact['contact']['_id'];
    final newUserName = contact['savedName'] ?? contact['contact']['username'];
    final newUserAvatar = contact['contact']['avatarUrl'];
    setState(() => _participants[newUserId] = {'username': newUserName, 'avatarUrl': newUserAvatar});
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final myUser = authProvider.user;
    final myUserName = myUser?['username'] ?? 'User';
    final socket = authProvider.socketService.socket;

    // Create offer from me (caller) to new user
    final pc = await _createPeerConnection(newUserId);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket?.emit('call_offer', {
      'targetUserId': newUserId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'callType': widget.isAudioOnly ? 'audio' : 'video',
      'conversationId': widget.conversationId,
      'callerName': myUserName,
      'callerAvatar': myUser?['avatarUrl'],
    });

    // Notify all existing participants to connect to new user
    for (final existingPeerId in _peerConnections.keys) {
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

  String _formatDuration(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  bool get _isGroupCall => _participants.length > 1;

  // 1-on-1 video: classic fullscreen remote + draggable PiP local
  Widget _buildOneToOneVideoView() {
    final mainRenderer = _isScreenSharing ? _localRenderer : (_remoteRenderers[widget.remoteUserId] ?? _localRenderer);
    final pipRenderer = _isScreenSharing ? (_remoteRenderers[widget.remoteUserId]) : _localRenderer;

    return Stack(
      children: [
        // Fullscreen main video
        Positioned.fill(
          child: RTCVideoView(
            mainRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: false,
          ),
        ),
        // Draggable PiP
        if (pipRenderer != null && !_isVideoOff)
          Positioned(
            right: _localVideoRight,
            bottom: _localVideoBottom,
            width: 110,
            height: 160,
            child: GestureDetector(
              onPanUpdate: (d) {
                setState(() {
                  _localVideoRight = (_localVideoRight - d.delta.dx).clamp(0.0, 300.0);
                  _localVideoBottom = (_localVideoBottom - d.delta.dy).clamp(0.0, 600.0);
                });
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.grey[900],
                  child: RTCVideoView(
                    pipRenderer,
                    mirror: !_isScreenSharing,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Group call: Responsive 3 & 4 member grid layout (Matching reference UI)
  Widget _buildGroupVideoGrid() {
    final List<Widget> views = [];

    _participants.forEach((id, data) {
      final renderer = _remoteRenderers[id];
      views.add(Stack(
        fit: StackFit.expand,
        children: [
          renderer != null
            ? RTCVideoView(
                renderer,
                objectFit: _isScreenSharing ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Container(color: Colors.grey[900], child: Center(child: ColorAvatar(name: data['username'] ?? '?', radius: 36, fontSize: 22))),
          Positioned(
            bottom: 8, left: 8,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: Text(data['username'] ?? 'User', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showEndCallWithDialog(id, data['username'] ?? 'User'),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 14),
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
            bottom: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: const Text('You', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ));
    }

    if (views.isEmpty) return const SizedBox.shrink();
    if (views.length == 1) return views.first;
    if (views.length == 2) {
      return Column(children: [Expanded(child: views[0]), const SizedBox(height: 2), Expanded(child: views[1])]);
    }
    if (views.length == 3) {
      // 3 Members Layout (Matches Picture 1): Top half 2 tiles side-by-side, Bottom half 1 large tile
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: views[0]),
                const SizedBox(width: 2),
                Expanded(child: views[1]),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(child: views[2]),
        ],
      );
    }

    if (views.length == 4) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: views[0]),
                const SizedBox(width: 2),
                Expanded(child: views[1]),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                Expanded(child: views[2]),
                const SizedBox(width: 2),
                Expanded(child: views[3]),
              ],
            ),
          ),
        ],
      );
    }

    // Dynamic grid layout for 5+ participants
    int crossAxisCount = views.length <= 6 ? 2 : 3;
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.0,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: views.length,
      itemBuilder: (context, index) => views[index],
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block ALL back-button pops during an active call.
      // User must use the red hang-up button to end, or the minimize button to go home.
      canPop: !_callActive,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // === VIDEO VIEWS ===
              if (!widget.isAudioOnly && _callActive)
                Positioned.fill(
                  child: _isGroupCall ? _buildGroupVideoGrid() : _buildOneToOneVideoView(),
                ),

              // === AUDIO ONLY / CONNECTING UI ===
              if (widget.isAudioOnly || !_callActive)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_isGroupCall) ...[
                        if (widget.remoteAvatarUrl != null && widget.remoteAvatarUrl!.trim().isNotEmpty)
                          CircleAvatar(
                            radius: 60,
                            backgroundImage: widget.remoteAvatarUrl!.startsWith('http')
                              ? NetworkImage(widget.remoteAvatarUrl!)
                              : NetworkImage('https://dolsyx-app.onrender.com${widget.remoteAvatarUrl!}'),
                          )
                        else
                          ColorAvatar(name: widget.remoteUserName, radius: 60, fontSize: 40),
                        const SizedBox(height: 20),
                        Text(widget.remoteUserName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      ] else ...[
                        Wrap(
                          spacing: 24, runSpacing: 16, alignment: WrapAlignment.center,
                          children: _participants.values.map((p) => Column(mainAxisSize: MainAxisSize.min, children: [
                            ColorAvatar(name: p['username'] ?? '?', radius: 40, fontSize: 24),
                            const SizedBox(height: 6),
                            Text(p['username'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ])).toList(),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        _callActive ? _formatDuration(_callDuration) : _status,
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      if (_hardwareFailed)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text("Camera/mic unavailable on this device.", textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                        ),
                    ],
                  ),
                ),

              // === TOP TIMER & SIGNAL QUALITY BAR ===
              if (_callActive)
                Positioned(
                  top: 12, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.signal_cellular_alt, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 6),
                          Text('HD • ${_formatDuration(_callDuration)}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),

              // === MINIMIZE BUTTON ===
              Positioned(
                top: 12, left: 16,
                child: GestureDetector(
                  onTap: () {
                    // Push the home screen ON TOP of CallScreen so CallScreen
                    // stays alive in the navigation stack. The green banner in
                    // main.dart lets the user tap back into this CallScreen.
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        settings: const RouteSettings(name: 'ChatListScreen'),
                        builder: (_) => const ChatListScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)),
                    child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 24),
                  ),
                ),
              ),

              // === ADD PARTICIPANT BUTTON ===
              if (_callActive && _participants.length < 15)
                Positioned(
                  top: 12, right: 16,
                  child: GestureDetector(
                    onTap: _showAddParticipantModal,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)),
                      child: const Icon(Icons.person_add, color: Colors.white, size: 22),
                    ),
                  ),
                ),

              // === CONTROL BUTTONS ===
              Positioned(
                bottom: 40, left: 0, right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (_callActive || !widget.isIncoming)
                      _ctrlBtn('mute', _isMuted ? Icons.mic_off : Icons.mic, _toggleMute, active: _isMuted),
                    if (_callActive || !widget.isIncoming)
                      _ctrlBtn(
                        'speaker',
                        _audioOutputMode == 'bluetooth'
                            ? Icons.bluetooth_audio
                            : (_audioOutputMode == 'earpiece' ? Icons.phone_in_talk : Icons.volume_up),
                        _toggleSpeaker,
                        active: _isSpeakerOn || _audioOutputMode == 'bluetooth',
                      ),
                    if (!widget.isAudioOnly && (_callActive || !widget.isIncoming))
                      _ctrlBtn('cam', Icons.flip_camera_ios, _switchCamera),
                    if (!widget.isAudioOnly && _callActive)
                      _ctrlBtn('screen', _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share, _toggleScreenShare, highlight: _isScreenSharing),
                    if (!widget.isAudioOnly && (_callActive || !widget.isIncoming))
                      _ctrlBtn('video', _isVideoOff ? Icons.videocam_off : Icons.videocam, _toggleVideo, active: _isVideoOff),

                    if (widget.isIncoming && !_callActive)
                      FloatingActionButton(heroTag: 'reject', backgroundColor: Colors.red, onPressed: _rejectCall, child: const Icon(Icons.call_end, color: Colors.white))
                    else
                      FloatingActionButton(heroTag: 'end', backgroundColor: Colors.red, onPressed: _endCall, child: const Icon(Icons.call_end, color: Colors.white)),

                    if (widget.isIncoming && !_callActive && !_hardwareFailed)
                      FloatingActionButton(
                        heroTag: 'accept', backgroundColor: Colors.green, onPressed: _acceptCall,
                        child: Icon(widget.isAudioOnly ? Icons.call : Icons.videocam, color: Colors.white),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ctrlBtn(String tag, IconData icon, VoidCallback onTap, {bool active = false, bool highlight = false}) {
    return FloatingActionButton(
      heroTag: tag,
      mini: true,
      backgroundColor: highlight ? Colors.blue : (active ? Colors.white : Colors.white24),
      onPressed: onTap,
      child: Icon(icon, color: (active && !highlight) ? Colors.black : Colors.white),
    );
  }
}
