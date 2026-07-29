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

  static String? activeConversationId;

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

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, List<RTCIceCandidate>> _iceCandidateQueues = {};
  
  // Track all participants in the call (excluding ourselves)
  // key: userId, value: { 'username': str, 'avatarUrl': str? }
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

  // Local Video Dragging (PiP mode for 1-on-1)
  double _localVideoX = 20;
  double _localVideoY = 120;
  
  // Screen Sharing
  bool _isScreenSharing = false;
  MediaStream? _screenStream;

  static const _channel = MethodChannel('com.dolsyx/screen_share');

  @override
  void initState() {
    super.initState();
    CallScreen.activeConversationId = widget.conversationId;
    
    // Add the initial remote user
    _participants[widget.remoteUserId] = {
      'username': widget.remoteUserName,
      'avatarUrl': widget.remoteAvatarUrl,
    };

    _initRenderers();
  }

  Future<void> _initRenderers() async {
    _isSpeakerOn = !widget.isAudioOnly;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    await _localRenderer.initialize();
    _setupSocketListeners();

    if (widget.isIncoming) {
      setState(() => _status = 'Ringing...');
      _timeoutTimer = Timer(const Duration(minutes: 2), () {
        if (!_callActive && mounted) {
          _rejectCall();
        }
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
      });
      final answererId = data['answererId'];
      if (data['answer'] != null && _peerConnections.containsKey(answererId)) {
        final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
        await _peerConnections[answererId]?.setRemoteDescription(answer);
        _flushIceCandidates(answererId);
      }
      if (_callTimer == null || !_callTimer!.isActive) {
        _startTimer();
      }
    });

    socket.on('call_rejected', (data) {
      if (!mounted) return;
      final rejecterId = data['rejecterId'];
      _removeParticipant(rejecterId, 'Rejected');
      if (_participants.isEmpty) {
        _endCallLocally('Call rejected');
      }
    });

    socket.on('call_ended', (data) {
      if (!mounted) return;
      final endedBy = data?['endedBy'];
      if (endedBy != null && endedBy != Provider.of<AuthProvider>(context, listen: false).user?['id']) {
         _removeParticipant(endedBy, 'Ended');
      }
      if (_participants.isEmpty || data?['status'] == 'answered_elsewhere') {
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

    // Mesh: Someone added a new user to the call. We need to initiate connection to them.
    socket.on('user_added_to_call', (data) async {
      if (!mounted) return;
      if (data['conversationId'] == widget.conversationId) {
        final newUserId = data['newUserId'];
        final newUserName = data['newUserName'];
        
        setState(() {
          _participants[newUserId] = {
            'username': newUserName,
            'avatarUrl': null, // We don't have avatar here, but that's ok
          };
        });
        
        // We act as caller to this new user
        final pc = await _createPeerConnection(newUserId);
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        
        final user = Provider.of<AuthProvider>(context, listen: false).user;
        socket.emit('call_offer', {
          'targetUserId': newUserId,
          'offer': { 'sdp': offer.sdp, 'type': offer.type },
          'callType': widget.isAudioOnly ? 'audio' : 'video',
          'conversationId': widget.conversationId,
          'callerName': user?['username'] ?? 'User',
          'callerAvatar': user?['avatarUrl'],
        });
      }
    });

    // Mesh: A new user we didn't call is calling us (because they were added to the call)
    socket.on('call_incoming', (data) async {
      if (!mounted) return;
      if (data['conversationId'] == widget.conversationId) {
        final callerId = data['callerId'];
        final callerName = data['callerName'];
        final callerAvatarUrl = data['callerAvatarUrl'];
        final offerData = data['offer'];
        
        setState(() {
          _participants[callerId] = {
            'username': callerName,
            'avatarUrl': callerAvatarUrl,
          };
        });

        // Auto-answer since we are already in this call
        final pc = await _createPeerConnection(callerId);
        final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
        await pc.setRemoteDescription(offer);
        _flushIceCandidates(callerId);
        
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        socket.emit('call_answer', {
          'callerId': callerId,
          'answer': { 'sdp': answer.sdp, 'type': answer.type },
        });
      }
    });
  }

  void _removeParticipant(String userId, String reason) {
    setState(() {
      _participants.remove(userId);
    });
    _peerConnections[userId]?.close();
    _peerConnections[userId]?.dispose();
    _peerConnections.remove(userId);
    
    _remoteRenderers[userId]?.dispose();
    _remoteRenderers.remove(userId);
    
    _iceCandidateQueues.remove(userId);
    
    if (_participants.isEmpty) {
      _endCallLocally(reason);
    }
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _callDuration++);
    });
  }

  Future<void> _flushIceCandidates(String userId) async {
    final queue = _iceCandidateQueues[userId];
    if (queue != null) {
      for (var candidate in queue) {
        await _peerConnections[userId]?.addCandidate(candidate);
      }
      _iceCandidateQueues[userId]?.clear();
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String targetUserId) async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    final pc = await createPeerConnection(configuration);
    _peerConnections[targetUserId] = pc;
    
    // Create renderer for this peer
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    setState(() {
      _remoteRenderers[targetUserId] = renderer;
    });

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
      socket?.emit('ice_candidate', {
        'targetUserId': targetUserId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        if (mounted) {
          setState(() {
            _remoteRenderers[targetUserId]?.srcObject = event.streams[0];
          });
        }
      }
    };

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    return pc;
  }

  Future<bool> _initWebRTC() async {
    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': widget.isAudioOnly ? false : {
          'facingMode': 'user',
        },
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      if (widget.isAudioOnly) {
        _isVideoOff = true;
      }
      return true;
    } catch (e) {
      print("WebRTC Initialization Failed: $e");
      return false;
    }
  }

  Future<void> _startCall() async {
    setState(() => _status = 'Calling...');
    _timeoutTimer = Timer(const Duration(minutes: 2), () {
      if (!_callActive && mounted) {
        _endCallLocally('No answer');
      }
    });
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (socket == null || user == null) return;

    final success = await _initWebRTC();
    if (!mounted) return;
    if (!success) {
      setState(() {
        _hardwareFailed = true;
        _status = 'Hardware not supported';
      });
      return;
    }

    try {
      final pc = await _createPeerConnection(widget.remoteUserId);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      socket.emit('call_offer', {
        'targetUserId': widget.remoteUserId,
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
        'callType': widget.isAudioOnly ? 'audio' : 'video',
        'conversationId': widget.conversationId,
        'callerName': user['username'],
        'callerAvatar': user['avatarUrl'],
      });
    } catch (e) {
      print('Error creating offer: $e');
    }
  }

  Future<void> _acceptCall() async {
    SoundService().stopRingtone();
    setState(() => _status = 'Connecting...');
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    if (socket == null) return;

    final success = await _initWebRTC();
    if (!mounted) return;
    if (!success) {
      setState(() {
        _hardwareFailed = true;
        _status = 'Hardware not supported';
      });
      socket.emit('call_reject', {
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
    });

    if (widget.initialOffer != null) {
      try {
        final pc = await _createPeerConnection(widget.remoteUserId);
        final offer = RTCSessionDescription(widget.initialOffer!['sdp'], widget.initialOffer!['type']);
        await pc.setRemoteDescription(offer);
        _flushIceCandidates(widget.remoteUserId);
        
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        socket.emit('call_answer', {
          'callerId': widget.remoteUserId,
          'answer': {
            'sdp': answer.sdp,
            'type': answer.type,
          },
        });
        _startTimer();
      } catch (e) {
        print('Error handling initial offer: $e');
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
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    final userId = Provider.of<AuthProvider>(context, listen: false).user?['id'];
    
    // Broadcast end call to all participants
    _participants.keys.forEach((peerId) {
       socket?.emit('call_end', {
         'peerId': peerId,
         'conversationId': widget.conversationId,
         'callType': widget.isAudioOnly ? 'audio' : 'video',
         'status': _callActive ? 'connected' : 'missed',
         'duration': _callDuration,
         'callerId': widget.isIncoming ? widget.remoteUserId : userId,
       });
    });
    
    _endCallLocally('Call ended');
  }

  void _endCallLocally(String reason) {
    SoundService().stopRingtone();
    if (!mounted) return;
    setState(() => _status = reason);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final track = audioTracks[0];
        track.enabled = !track.enabled;
        setState(() => _isMuted = !track.enabled);
      }
    }
  }

  void _toggleVideo() {
    if (widget.isAudioOnly || _localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      final track = videoTracks[0];
      track.enabled = !track.enabled;
      setState(() => _isVideoOff = !track.enabled);
    }
  }

  void _switchCamera() async {
    if (widget.isAudioOnly || _localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks[0]);
    }
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
        if (Platform.isAndroid) {
          await _channel.invokeMethod('stopScreenShareService');
        }
      } catch (e) {}

      if (_localStream != null) {
        final videoTracks = _localStream!.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          final videoTrack = videoTracks.first;
          for (var pc in _peerConnections.values) {
            final senders = await pc.getSenders();
            for (var sender in senders) {
              if (sender.track?.kind == 'video') {
                await sender.replaceTrack(videoTrack);
              }
            }
          }
        }
        _localRenderer.srcObject = _localStream;
      }
      setState(() {
        _isScreenSharing = false;
      });
    } else {
      try {
        if (Platform.isAndroid) {
          await _channel.invokeMethod('startScreenShareService');
        }
        await Future.delayed(const Duration(milliseconds: 300));
        
        _screenStream = await navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': false});
        
        if (_screenStream != null) {
          final videoTracks = _screenStream!.getVideoTracks();
          if (videoTracks.isNotEmpty) {
            final screenVideoTrack = videoTracks.first;
            for (var pc in _peerConnections.values) {
              final senders = await pc.getSenders();
              for (var sender in senders) {
                if (sender.track?.kind == 'video') {
                  await sender.replaceTrack(screenVideoTrack);
                }
              }
            }
            _localRenderer.srcObject = _screenStream;
            
            setState(() {
              _isScreenSharing = true;
            });
            
            screenVideoTrack.onEnded = () {
              if (mounted && _isScreenSharing) {
                _toggleScreenShare();
              }
            };
          }
        }
      } catch (e) {
        try {
          if (Platform.isAndroid) await _channel.invokeMethod('stopScreenShareService');
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start screen sharing.')));
        }
      }
    }
  }
  
  // Modals for adding participants
  void _showAddParticipantModal() async {
    if (_participants.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group calls are limited to 4 participants.')),
      );
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
        return _AddParticipantSheet(
          contacts: contacts,
          currentParticipants: _participants.keys.toList(),
          onAdd: (contact) {
            Navigator.pop(context);
            _addParticipantToCall(contact);
          },
        );
      },
    );
  }
  
  void _addParticipantToCall(dynamic contact) async {
    final userId = contact['contact']['id'] ?? contact['contact']['_id'];
    final username = contact['savedName'] ?? contact['contact']['username'];
    final avatarUrl = contact['contact']['avatarUrl'];
    
    setState(() {
      _participants[userId] = {
        'username': username,
        'avatarUrl': avatarUrl,
      };
    });
    
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    final myUser = Provider.of<AuthProvider>(context, listen: false).user;
    
    // Create PC and Offer
    final pc = await _createPeerConnection(userId);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    
    // Send standard offer to new user
    socket?.emit('call_offer', {
      'targetUserId': userId,
      'offer': { 'sdp': offer.sdp, 'type': offer.type },
      'callType': widget.isAudioOnly ? 'audio' : 'video',
      'conversationId': widget.conversationId,
      'callerName': myUser?['username'] ?? 'User',
      'callerAvatar': myUser?['avatarUrl'],
    });
    
    // Notify existing users to also call the new user (Mesh)
    for (String existingPeerId in _peerConnections.keys) {
      if (existingPeerId != userId) {
        socket?.emit('user_added_to_call', {
          'targetUserId': existingPeerId,
          'newUserId': userId,
          'newUserName': username,
          'conversationId': widget.conversationId,
          'callType': widget.isAudioOnly ? 'audio' : 'video',
        });
      }
    }
  }

  @override
  void dispose() {
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

    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    
    for (var pc in _peerConnections.values) {
      pc.close();
      pc.dispose();
    }
    _peerConnections.clear();
    
    _localRenderer.dispose();
    for (var r in _remoteRenderers.values) {
      r.dispose();
    }
    _remoteRenderers.clear();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildVideoGrid() {
    List<Widget> views = [];
    
    // Add remote streams
    _participants.forEach((id, data) {
      if (_remoteRenderers[id] != null) {
        views.add(
          Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(_remoteRenderers[id]!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
              Positioned(
                bottom: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: Text(data['username'] ?? 'User', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              )
            ],
          )
        );
      } else {
        // Audio only or not connected yet
        views.add(
          Container(
            color: Colors.grey[900],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ColorAvatar(name: data['username'] ?? '?', radius: 40, fontSize: 24),
                  const SizedBox(height: 8),
                  Text(data['username'] ?? 'Connecting...', style: const TextStyle(color: Colors.white)),
                ],
              )
            ),
          )
        );
      }
    });

    // Add local stream if not audio only
    if (!widget.isAudioOnly && !_isVideoOff) {
      views.add(
        Stack(
          fit: StackFit.expand,
          children: [
            RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
            Positioned(
              bottom: 8, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: const Text('You', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            )
          ],
        )
      );
    }

    if (views.isEmpty) return const SizedBox.shrink();
    if (views.length == 1) return views.first;
    if (views.length == 2) {
      return Column(
        children: [
          Expanded(child: views[0]),
          const Divider(height: 1, color: Colors.black),
          Expanded(child: views[1]),
        ],
      );
    }
    
    // Grid for 3 or 4
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 0.75,
      children: views,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Video Grid
            if (!widget.isAudioOnly && _callActive)
              Positioned.fill(
                child: _buildVideoGrid(),
              ),

            // Audio only / connecting UI
            if (widget.isAudioOnly || !_callActive)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_participants.length == 1) ...[
                      if (widget.remoteAvatarUrl != null && widget.remoteAvatarUrl!.trim().isNotEmpty)
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: AppTheme.surfaceColor,
                          backgroundImage: widget.remoteAvatarUrl!.startsWith('http')
                              ? NetworkImage(widget.remoteAvatarUrl!)
                              : NetworkImage('https://dolsyx-app.onrender.com${widget.remoteAvatarUrl!}'),
                        )
                      else
                        ColorAvatar(name: widget.remoteUserName, radius: 60, fontSize: 40),
                      const SizedBox(height: 24),
                      Text(
                        widget.remoteUserName,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ] else ...[
                       // Group Audio Call Display
                       Wrap(
                         spacing: 16,
                         runSpacing: 16,
                         alignment: WrapAlignment.center,
                         children: _participants.values.map((p) {
                           return Column(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               ColorAvatar(name: p['username'] ?? 'User', radius: 40, fontSize: 24),
                               const SizedBox(height: 8),
                               Text(p['username'] ?? '', style: const TextStyle(color: Colors.white)),
                             ],
                           );
                         }).toList(),
                       ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      _callActive ? _formatDuration(_callDuration) : _status,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    if (_hardwareFailed)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          "Your device's camera/mic could not be initialized.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.redAccent, fontSize: 14),
                        ),
                      )
                  ],
                ),
              ),

            // Top Status Bar Overlay (Timer for Video Call)
            if (!widget.isAudioOnly && _callActive)
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatDuration(_callDuration),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              
            // Add Participant Button
            if (_callActive && _participants.length < 4)
              Positioned(
                top: 20,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.person_add, color: Colors.white),
                  onPressed: _showAddParticipantModal,
                  tooltip: 'Add Participant',
                ),
              ),

            // Controls
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_callActive || !widget.isIncoming)
                    FloatingActionButton(
                      heroTag: 'mute',
                      mini: true,
                      backgroundColor: _isMuted ? Colors.white : Colors.white24,
                      onPressed: _toggleMute,
                      child: Icon(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        color: _isMuted ? Colors.black : Colors.white,
                      ),
                    ),
                  if (_callActive || !widget.isIncoming)
                    FloatingActionButton(
                      heroTag: 'speaker',
                      mini: true,
                      backgroundColor: _isSpeakerOn ? Colors.white : Colors.white24,
                      onPressed: _toggleSpeaker,
                      child: Icon(
                        _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                        color: _isSpeakerOn ? Colors.black : Colors.white,
                      ),
                    ),
                  if (!widget.isAudioOnly && (_callActive || !widget.isIncoming))
                    FloatingActionButton(
                      heroTag: 'switch_cam',
                      mini: true,
                      backgroundColor: Colors.white24,
                      onPressed: _switchCamera,
                      child: const Icon(Icons.flip_camera_ios, color: Colors.white),
                    ),
                  if (!widget.isAudioOnly && _callActive)
                    FloatingActionButton(
                      heroTag: 'screen_share',
                      mini: true,
                      backgroundColor: _isScreenSharing ? Colors.blue : Colors.white24,
                      onPressed: _toggleScreenShare,
                      child: Icon(
                        _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                        color: Colors.white,
                      ),
                    ),
                  if (!widget.isAudioOnly && (_callActive || !widget.isIncoming))
                    FloatingActionButton(
                      heroTag: 'video',
                      mini: true,
                      backgroundColor: _isVideoOff ? Colors.white : Colors.white24,
                      onPressed: _toggleVideo,
                      child: Icon(
                        _isVideoOff ? Icons.videocam_off : Icons.videocam,
                        color: _isVideoOff ? Colors.black : Colors.white,
                      ),
                    ),
                  if (widget.isIncoming && !_callActive)
                    FloatingActionButton(
                      heroTag: 'end',
                      backgroundColor: Colors.red,
                      onPressed: _rejectCall,
                      child: const Icon(Icons.call_end, color: Colors.white),
                    )
                  else if (!widget.isIncoming || _callActive)
                    FloatingActionButton(
                      heroTag: 'end',
                      backgroundColor: Colors.red,
                      onPressed: _endCall,
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                  if (widget.isIncoming && !_callActive && !_hardwareFailed)
                    FloatingActionButton(
                      heroTag: 'accept',
                      backgroundColor: Colors.green,
                      onPressed: _acceptCall,
                      child: Icon(widget.isAudioOnly ? Icons.call : Icons.videocam, color: Colors.white),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddParticipantSheet extends StatelessWidget {
  final List<dynamic> contacts;
  final List<String> currentParticipants;
  final Function(dynamic) onAdd;

  const _AddParticipantSheet({
    required this.contacts,
    required this.currentParticipants,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final available = contacts.where((c) {
      final id = c['contact']['id'] ?? c['contact']['_id'];
      return !currentParticipants.contains(id);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Add to Call', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: available.isEmpty
            ? Center(child: Text('No contacts available', style: TextStyle(color: AppTheme.textSecondary)))
            : ListView.builder(
              itemCount: available.length,
              itemBuilder: (context, i) {
                final c = available[i];
                final name = c['savedName'] ?? c['contact']['username'] ?? 'User';
                return ListTile(
                  leading: ColorAvatar(name: name, radius: 20, fontSize: 16),
                  title: Text(name, style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () => onAdd(c),
                );
              },
            ),
        ),
      ],
    );
  }
}
