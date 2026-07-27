import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../services/sound_service.dart';

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

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
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

  // ICE Candidate Queue
  final List<RTCIceCandidate> _iceCandidateQueue = [];

  // Local Video Dragging
  double _localVideoX = 20;
  double _localVideoY = 120;
  
  // Video Swapping
  bool _isLocalMain = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    _isSpeakerOn = !widget.isAudioOnly;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _setupSocketListeners();

    if (widget.isIncoming) {
      setState(() => _status = 'Ringing...');
      // Ringing state, wait for user to hit accept
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
      if (data['answer'] != null) {
        final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
        await _peerConnection?.setRemoteDescription(answer);
        _flushIceCandidates();
      }
      _startTimer();
    });

    socket.on('call_rejected', (data) {
      if (!mounted) return;
      _endCallLocally('Call rejected');
    });

    socket.on('call_ended', (data) {
      if (!mounted) return;
      String reason = 'Call ended';
      if (data != null && data['status'] == 'answered_elsewhere') {
        reason = 'Answered elsewhere';
      }
      _endCallLocally(reason);
    });

    socket.on('ice_candidate', (data) async {
      if (!mounted) return;
      if (data['candidate'] != null) {
        final candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex'],
        );
        if (_peerConnection == null || await _peerConnection!.getRemoteDescription() == null) {
          _iceCandidateQueue.add(candidate);
        } else {
          await _peerConnection?.addCandidate(candidate);
        }
      }
    });
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _callDuration++);
    });
  }

  Future<void> _flushIceCandidates() async {
    for (var candidate in _iceCandidateQueue) {
      await _peerConnection?.addCandidate(candidate);
    }
    _iceCandidateQueue.clear();
  }

  Future<void> _startCall() async {
    // No ringback tone - caller will hear silence
    setState(() => _status = 'Calling...');
    _timeoutTimer = Timer(const Duration(minutes: 2), () {
      if (!_callActive && mounted) {
        _endCallLocally('No answer');
      }
    });
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (socket == null || user == null) return;

    // Hardware safe initialization
    final success = await _initWebRTC();
    if (!mounted) return;
    if (!success) {
      setState(() {
        _hardwareFailed = true;
        _status = 'Hardware not supported';
      });
      return;
    }

    if (_peerConnection == null) return;
    try {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

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

    // Hardware safe initialization
    final success = await _initWebRTC();
    if (!mounted) return;
    if (!success) {
      setState(() {
        _hardwareFailed = true;
        _status = 'Hardware not supported';
      });
      // Tell other side we rejected it due to hardware failure
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

    if (widget.initialOffer != null && _peerConnection != null) {
      try {
        final offer = RTCSessionDescription(widget.initialOffer!['sdp'], widget.initialOffer!['type']);
        await _peerConnection!.setRemoteDescription(offer);
        _flushIceCandidates();
        
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

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

      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      };

      _peerConnection = await createPeerConnection(configuration);

      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
        socket?.emit('ice_candidate', {
          'targetUserId': widget.remoteUserId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }
        });
      };

      _peerConnection?.onTrack = (RTCTrackEvent event) {
        // Always bind the full stream to avoid Android track-kind splitting bugs.
        // Both audio and video tracks arrive via event.streams[0] on Android.
        if (event.streams.isNotEmpty) {
          if (mounted) {
            setState(() {
              _remoteRenderer.srcObject = event.streams[0];
            });
          }
        }
      };

      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      return true;
    } catch (e) {
      print("WebRTC Initialization Failed: $e");
      return false;
    }
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
      // Local renderer automatically reflects the flip
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    });
  }

  void _endCall() {
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    final userId = Provider.of<AuthProvider>(context, listen: false).user?['id'];
    socket?.emit('call_end', {
      'peerId': widget.remoteUserId,
      'conversationId': widget.conversationId,
      'callType': widget.isAudioOnly ? 'audio' : 'video',
      'status': _callActive ? 'connected' : 'missed',
      'duration': _callDuration,
      'callerId': widget.isIncoming ? widget.remoteUserId : userId,
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

  @override
  void dispose() {
    SoundService().stopRingtone();
    _callTimer?.cancel();
    _timeoutTimer?.cancel();
    final socketService = Provider.of<AuthProvider>(context, listen: false).socketService;
    socketService.socket?.off('call_answered');
    socketService.socket?.off('call_rejected');
    socketService.socket?.off('call_ended');
    socketService.socket?.off('ice_candidate');

    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Main Fullscreen Video
            if (!widget.isAudioOnly && _callActive)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    // Tap background to do nothing or hide controls
                  },
                  child: RTCVideoView(_isLocalMain ? _localRenderer : _remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: _isLocalMain),
                ),
              ),

            // Draggable Picture-in-Picture Local Video
            if (!widget.isAudioOnly && _callActive && !_isVideoOff)
              Positioned(
                right: _localVideoX,
                bottom: _localVideoY,
                width: 100,
                height: 150,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _localVideoX -= details.delta.dx;
                      _localVideoY -= details.delta.dy;
                    });
                  },
                  onDoubleTap: () {
                    setState(() {
                      _isLocalMain = !_isLocalMain;
                    });
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.grey[900],
                      child: RTCVideoView(_isLocalMain ? _remoteRenderer : _localRenderer, mirror: !_isLocalMain, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    ),
                  ),
                ),
              ),

            // Audio only / connecting UI (Overlayed timer if active audio)
            if (widget.isAudioOnly || !_callActive)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.remoteAvatarUrl != null && widget.remoteAvatarUrl!.trim().isNotEmpty)
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: AppTheme.surfaceColor,
                        backgroundImage: widget.remoteAvatarUrl!.startsWith('http')
                            ? NetworkImage(widget.remoteAvatarUrl!)
                            : NetworkImage('https://dolsyx-app.onrender.com${widget.remoteAvatarUrl!}'),
                        onBackgroundImageError: (exception, stackTrace) {
                          print("Call avatar load error: $exception");
                        },
                      )
                    else
                      ColorAvatar(name: widget.remoteUserName, radius: 60, fontSize: 40),
                    const SizedBox(height: 24),
                    Text(
                      widget.remoteUserName,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _callActive ? _formatDuration(_callDuration) : _status,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    if (_hardwareFailed)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          "Your device's camera/mic could not be initialized.\nCross-platform WebRTC is not supported on this specific OS/kernel version.",
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
