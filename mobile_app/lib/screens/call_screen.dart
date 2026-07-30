import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../services/sound_service.dart';
import '../services/contact_service.dart';

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
  static _CallScreenState? activeCallState;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  // Mesh: multiple peer connections for group calls
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, List<RTCIceCandidate>> _iceCandidateQueues = {};
  final Map<String, Map<String, dynamic>> _participants = {};

  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _hardwareFailed = false;
  bool _callActive = false;
  bool _isSpeakerOn = false;
  String _status = 'Connecting...';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CallScreen.activeConversationId = widget.conversationId;
    CallScreen.activeCallState = this;
    _participants[widget.remoteUserId] = {
      'username': widget.remoteUserName,
      'avatarUrl': widget.remoteAvatarUrl,
    };
    _initRenderers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep call screen visible when app comes back from background
    if (state == AppLifecycleState.resumed && _callActive && mounted) {
      setState(() {});
    }
  }

  Future<void> _initRenderers() async {
    _isSpeakerOn = !widget.isAudioOnly;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    await _localRenderer.initialize();
    _setupSocketListeners();

    if (widget.isIncoming) {
      setState(() => _status = 'Ringing...');
      _timeoutTimer = Timer(const Duration(minutes: 2), () {
        if (!_callActive && mounted) _rejectCall();
      });
    } else {
      _startCall();
    }
  }

  void _setupSocketListeners() {
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    if (socket == null) return;

    socket.on('call_answered', (data) async {
      if (!mounted) return;
      SoundService().stopRingtone();
      _timeoutTimer?.cancel();
      setState(() {
        _status = 'Connected';
        _callActive = true;
        CallScreen.isCallActiveNotifier.value = true;
      });
      final answererId = data['answererId'] ?? widget.remoteUserId;
      if (data['answer'] != null) {
        final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
        await _peerConnections[answererId]?.setRemoteDescription(answer);
        _flushIceCandidates(answererId);
      }
      if (_callTimer == null || !_callTimer!.isActive) _startTimer();
    });

    socket.on('call_rejected', (data) {
      if (!mounted) return;
      _endCallLocally('Call rejected');
    });

    socket.on('call_ended', (data) {
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
    });

    socket.on('ice_candidate', (data) async {
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
    });

    // Group call: someone added a new user — we initiate to them
    socket.on('user_added_to_call', (data) async {
      if (!mounted) return;
      if (data['conversationId'] != widget.conversationId) return;
      final newUserId = data['newUserId'];
      final newUserName = data['newUserName'];
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _participants[newUserId] = {'username': newUserName, 'avatarUrl': null};
      });
      final pc = await _createPeerConnection(newUserId);
      final offer = await pc.createOffer();
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
    });

    // Group call: a new participant calls us (auto-answer)
    socket.on('call_incoming', (data) async {
      if (!mounted) return;
      if (data['conversationId'] != widget.conversationId) return;
      final callerId = data['callerId'];
      final callerName = data['callerName'];
      final callerAvatarUrl = data['callerAvatarUrl'];
      final offerData = data['offer'];
      setState(() {
        _participants[callerId] = {'username': callerName, 'avatarUrl': callerAvatarUrl};
      });
      final pc = await _createPeerConnection(callerId);
      final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
      await pc.setRemoteDescription(offer);
      _flushIceCandidates(callerId);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      if (!mounted) return;
      Provider.of<AuthProvider>(context, listen: false).socketService.socket?.emit('call_answer', {
        'callerId': callerId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
    });

    // Screen Share Request event
    socket.on('screen_share_request', (data) {
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
    });
  }

  void _removeParticipant(String userId) {
    _peerConnections[userId]?.close();
    _peerConnections[userId]?.dispose();
    _peerConnections.remove(userId);
    _remoteRenderers[userId]?.dispose();
    _remoteRenderers.remove(userId);
    _iceCandidateQueues.remove(userId);
    if (mounted) setState(() => _participants.remove(userId));
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
    final configuration = {
      'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
    };
    final pc = await createPeerConnection(configuration);
    _peerConnections[targetUserId] = pc;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    if (mounted) setState(() => _remoteRenderers[targetUserId] = renderer);

    pc.onIceCandidate = (candidate) {
      Provider.of<AuthProvider>(context, listen: false).socketService.socket?.emit('ice_candidate', {
        'targetUserId': targetUserId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      });
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() => _remoteRenderers[targetUserId]?.srcObject = event.streams[0]);
      }
    };

    _localStream?.getTracks().forEach((track) => pc.addTrack(track, _localStream!));
    return pc;
  }

  Future<bool> _initWebRTC() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isAudioOnly ? false : {'facingMode': 'user'},
      });
      _localRenderer.srcObject = _localStream;
      if (widget.isAudioOnly) _isVideoOff = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _startCall() async {
    setState(() => _status = 'Calling...');
    _timeoutTimer = Timer(const Duration(minutes: 2), () {
      if (!_callActive && mounted) _endCallLocally('No answer');
    });
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.socketService.socket == null || authProvider.user == null) return;

    final success = await _initWebRTC();
    if (!mounted) return;
    if (!success) {
      setState(() { _hardwareFailed = true; _status = 'Hardware not supported'; });
      return;
    }
    try {
      final pc = await _createPeerConnection(widget.remoteUserId);
      final offer = await pc.createOffer();
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
      // silently handle
    }
  }

  Future<void> _acceptCall() async {
    SoundService().stopRingtone();
    setState(() => _status = 'Connecting...');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
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
        _flushIceCandidates(widget.remoteUserId);
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        authProvider.socketService.socket?.emit('call_answer', {
          'callerId': widget.remoteUserId,
          'answer': {'sdp': answer.sdp, 'type': answer.type},
        });
        _startTimer();
      } catch (e) {
        // silently handle
      }
    }
  }

  void _rejectCall() {
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    socket?.emit('call_reject', {
      'callerId': widget.remoteUserId,
      'conversationId': widget.conversationId,
      'callType': widget.isAudioOnly ? 'audio' : 'video',
    });
    _endCallLocally('Call rejected');
  }

  void _endCall() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['id'];
    for (final peerId in _participants.keys) {
      authProvider.socketService.socket?.emit('call_end', {
        'peerId': peerId,
        'conversationId': widget.conversationId,
        'callType': widget.isAudioOnly ? 'audio' : 'video',
        'status': _callActive ? 'connected' : 'missed',
        'duration': _callDuration,
        'callerId': widget.isIncoming ? widget.remoteUserId : userId,
      });
    }
    _endCallLocally('Call ended');
  }

  // End call with a single specific participant (group call)
  void _endCallWith(String peerId) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['id'];
    authProvider.socketService.socket?.emit('call_end', {
      'peerId': peerId,
      'conversationId': widget.conversationId,
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
    _localStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.getTracks().forEach((t) => t.stop());
    if (!mounted) return;
    setState(() => _status = reason);
    Future.delayed(const Duration(milliseconds: 500), () {
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
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks[0]);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    });
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
            _localRenderer.srcObject = _screenStream;
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
    if (_participants.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group calls limited to 4 participants.')));
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
    final myUserId = myUser?['id'];
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

    // Also notify the new user about each existing participant so they connect back
    for (final existingPeerId in _peerConnections.keys) {
      if (existingPeerId != newUserId) {
        final peerInfo = _participants[existingPeerId];
        socket?.emit('user_added_to_call', {
          'targetUserId': newUserId,
          'newUserId': existingPeerId,
          'newUserName': peerInfo?['username'] ?? 'User',
          'conversationId': widget.conversationId,
          'callType': widget.isAudioOnly ? 'audio' : 'video',
        });
        // Also tell new user about myself
        socket?.emit('user_added_to_call', {
          'targetUserId': newUserId,
          'newUserId': myUserId,
          'newUserName': myUserName,
          'conversationId': widget.conversationId,
          'callType': widget.isAudioOnly ? 'audio' : 'video',
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallScreen.activeConversationId = null;
    SoundService().stopRingtone();
    _callTimer?.cancel();
    _timeoutTimer?.cancel();
    final socketService = Provider.of<AuthProvider>(context, listen: false).socketService;
    socketService.socket?.off('call_answered');
    socketService.socket?.off('call_rejected');
    socketService.socket?.off('call_ended');
    socketService.socket?.off('ice_candidate');
    socketService.socket?.off('user_added_to_call');
    socketService.socket?.off('call_incoming');
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    for (final pc in _peerConnections.values) { pc.close(); pc.dispose(); }
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
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
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
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

    // 4 Members Layout (Matches Picture 2): 2x2 grid filling screen
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
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (_callActive) {
          // Show ongoing call bar instead of full pop
        }
      },
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

              // === TOP TIMER BAR (video call only) ===
              if (!widget.isAudioOnly && _callActive)
                Positioned(
                  top: 12, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                      child: Text(_formatDuration(_callDuration), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),

              // === ADD PARTICIPANT BUTTON ===
              if (_callActive && _participants.length < 3)
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
                      _ctrlBtn('speaker', _isSpeakerOn ? Icons.volume_up : Icons.volume_down, _toggleSpeaker, active: _isSpeakerOn),
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
