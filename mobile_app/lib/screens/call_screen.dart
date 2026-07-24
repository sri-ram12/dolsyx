import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';

class CallScreen extends StatefulWidget {
  final String conversationId;
  final String remoteUserId;
  final String remoteUserName;
  final String? remoteAvatarUrl;
  final bool isAudioOnly;
  final bool isIncoming;
  final String? callId;

  const CallScreen({
    super.key,
    required this.conversationId,
    required this.remoteUserId,
    required this.remoteUserName,
    this.remoteAvatarUrl,
    required this.isAudioOnly,
    required this.isIncoming,
    this.callId,
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
  String _status = 'Connecting...';
  String? _actualCallId;

  @override
  void initState() {
    super.initState();
    _actualCallId = widget.callId;
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _setupSocketListeners();

    if (widget.isIncoming) {
      setState(() => _status = 'Ringing...');
      // Ringing state, wait for user to hit accept
    } else {
      _startCall();
    }
  }

  void _setupSocketListeners() {
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    if (socket == null) return;

    socket.on('call_accepted', (data) async {
      if (!mounted || data['conversationId'] != widget.conversationId) return;
      setState(() {
        _status = 'Connected';
        _callActive = true;
      });
      await _createOffer();
    });

    socket.on('call_rejected', (data) {
      if (!mounted || data['conversationId'] != widget.conversationId) return;
      _endCallLocally('Call rejected');
    });

    socket.on('call_ended', (data) {
      if (!mounted || data['conversationId'] != widget.conversationId) return;
      _endCallLocally('Call ended');
    });

    socket.on('offer', (data) async {
      if (!mounted || data['conversationId'] != widget.conversationId) return;
      final offer = RTCSessionDescription(data['sdp'], data['type']);
      await _peerConnection?.setRemoteDescription(offer);
      await _createAnswer();
    });

    socket.on('answer', (data) async {
      if (!mounted || data['conversationId'] != widget.conversationId) return;
      final answer = RTCSessionDescription(data['sdp'], data['type']);
      await _peerConnection?.setRemoteDescription(answer);
    });

    socket.on('ice_candidate', (data) async {
      if (!mounted || data['conversationId'] != widget.conversationId) return;
      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      await _peerConnection?.addCandidate(candidate);
    });
  }

  Future<void> _startCall() async {
    setState(() => _status = 'Calling...');
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    if (socket == null) return;

    _actualCallId = DateTime.now().millisecondsSinceEpoch.toString();

    // Hardware safe initialization
    final success = await _initWebRTC();
    if (!success) {
      setState(() {
        _hardwareFailed = true;
        _status = 'Hardware not supported';
      });
      return;
    }

    socket.emit('call_invite', {
      'conversationId': widget.conversationId,
      'receiverId': widget.remoteUserId,
      'isAudioOnly': widget.isAudioOnly,
      'callId': _actualCallId,
    });
  }

  Future<void> _acceptCall() async {
    setState(() => _status = 'Connecting...');
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    if (socket == null) return;

    // Hardware safe initialization
    final success = await _initWebRTC();
    if (!success) {
      setState(() {
        _hardwareFailed = true;
        _status = 'Hardware not supported';
      });
      // Tell other side we rejected it due to hardware failure
      socket.emit('call_rejected', {
        'conversationId': widget.conversationId,
        'receiverId': widget.remoteUserId,
      });
      return;
    }

    setState(() {
      _callActive = true;
      _status = 'Connected';
    });

    socket.emit('call_accepted', {
      'conversationId': widget.conversationId,
      'receiverId': widget.remoteUserId,
    });
  }

  void _rejectCall() {
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    socket?.emit('call_rejected', {
      'conversationId': widget.conversationId,
      'receiverId': widget.remoteUserId,
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
          'conversationId': widget.conversationId,
          'receiverId': widget.remoteUserId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };

      _peerConnection?.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video') {
          _remoteRenderer.srcObject = event.streams[0];
        } else if (widget.isAudioOnly && event.track.kind == 'audio') {
          _remoteRenderer.srcObject = event.streams[0];
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

  Future<void> _createOffer() async {
    if (_peerConnection == null) return;
    try {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
      socket?.emit('offer', {
        'conversationId': widget.conversationId,
        'receiverId': widget.remoteUserId,
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (e) {
      print('Error creating offer: $e');
    }
  }

  Future<void> _createAnswer() async {
    if (_peerConnection == null) return;
    try {
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
      socket?.emit('answer', {
        'conversationId': widget.conversationId,
        'receiverId': widget.remoteUserId,
        'sdp': answer.sdp,
        'type': answer.type,
      });
    } catch (e) {
      print('Error creating answer: $e');
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

  void _endCall() {
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    socket?.emit('end_call', {
      'conversationId': widget.conversationId,
      'receiverId': widget.remoteUserId,
    });
    _endCallLocally('Call ended');
  }

  void _endCallLocally(String reason) {
    if (!mounted) return;
    setState(() => _status = reason);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    final socketService = Provider.of<AuthProvider>(context, listen: false).socketService;
    socketService.socket?.off('call_accepted');
    socketService.socket?.off('call_rejected');
    socketService.socket?.off('call_ended');
    socketService.socket?.off('offer');
    socketService.socket?.off('answer');
    socketService.socket?.off('ice_candidate');

    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Video views
            if (!widget.isAudioOnly && _callActive)
              Positioned.fill(
                child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            if (!widget.isAudioOnly && _callActive && !_isVideoOff)
              Positioned(
                right: 20,
                bottom: 120,
                width: 100,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),

            // Audio only / connecting UI
            if (widget.isAudioOnly || !_callActive)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.remoteAvatarUrl != null)
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: NetworkImage(widget.remoteAvatarUrl!),
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
                      _status,
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
                      backgroundColor: _isMuted ? Colors.white : Colors.white24,
                      onPressed: _toggleMute,
                      child: Icon(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        color: _isMuted ? Colors.black : Colors.white,
                      ),
                    ),
                  if (!widget.isAudioOnly && (_callActive || !widget.isIncoming))
                    FloatingActionButton(
                      heroTag: 'video',
                      backgroundColor: _isVideoOff ? Colors.white : Colors.white24,
                      onPressed: _toggleVideo,
                      child: Icon(
                        _isVideoOff ? Icons.videocam_off : Icons.videocam,
                        color: _isVideoOff ? Colors.black : Colors.white,
                      ),
                    ),
                  if (widget.isIncoming && !_callActive && !_hardwareFailed)
                    FloatingActionButton(
                      heroTag: 'accept',
                      backgroundColor: Colors.green,
                      onPressed: _acceptCall,
                      child: const Icon(Icons.call, color: Colors.white),
                    ),
                  FloatingActionButton(
                    heroTag: 'end',
                    backgroundColor: Colors.red,
                    onPressed: widget.isIncoming && !_callActive ? _rejectCall : _endCall,
                    child: const Icon(Icons.call_end, color: Colors.white),
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
