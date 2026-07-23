import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';

class CallScreen extends StatefulWidget {
  final String remoteUserId;
  final String remoteUserName;
  final bool isVideo;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.remoteUserId,
    required this.remoteUserName,
    this.isVideo = true,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _isVideoOff = false;

  CallService? _callService;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    // Request permissions first
    try {
      await Permission.microphone.request();
      if (widget.isVideo) {
        await Permission.camera.request();
      }
    } catch (e) {
      print("Permission request error: $e");
    }

    if (!mounted) return;

    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    if (!mounted) return;
    final socketService = Provider.of<AuthProvider>(context, listen: false).socketService;
    _callService = CallService(socketService);
    
    _callService!.onLocalStream = (stream) {
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    };
    
    _callService!.onRemoteStream = (stream) {
      if (mounted) setState(() => _remoteRenderer.srcObject = stream);
    };
    
    _callService!.onCallEnded = () {
      if (mounted) Navigator.pop(context);
    };

    if (widget.isIncoming) {
      // In a real app we'd pass the offer through to answerCall, but simplifying here
    } else {
      if (!mounted) return;
      final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
      final callerName = currentUser?['username'] ?? 'Unknown User';
      final callerAvatar = currentUser?['avatarUrl'];
      
      await _callService!.startCall(
        widget.remoteUserId, 
        widget.remoteUserId, // using remoteUserId as conversationId placeholder for simplicity if needed
        widget.isVideo,
        callerName,
        callerAvatar,
      );
    }
  }

  @override
  void dispose() {
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _callService?.endCall();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _toggleMute() {
    if (_localRenderer.srcObject != null) {
      final audioTracks = _localRenderer.srcObject!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final track = audioTracks.first;
        track.enabled = _isMuted;
        setState(() => _isMuted = !_isMuted);
      }
    }
  }

  void _toggleVideo() {
    if (_localRenderer.srcObject != null) {
      final videoTracks = _localRenderer.srcObject!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final track = videoTracks.first;
        track.enabled = _isVideoOff;
        setState(() => _isVideoOff = !_isVideoOff);
      }
    }
  }

  void _endCall() {
    _callService?.endCall();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote Video (Full Screen)
            if (widget.isVideo)
              Center(
                child: _remoteRenderer.srcObject != null
                    ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppTheme.primaryColor),
                          SizedBox(height: 16),
                          Text('Connecting...', style: TextStyle(color: Colors.white)),
                        ],
                      ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(radius: 60, backgroundColor: AppTheme.surfaceColor, child: const Icon(Icons.person, size: 60)),
                    const SizedBox(height: 24),
                    Text(widget.remoteUserName, style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Audio Calling...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),

            // Local Video (Picture in Picture)
            if (widget.isVideo && !_isVideoOff)
              Positioned(
                right: 16,
                top: 16,
                child: Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: RTCVideoView(_localRenderer, mirror: true),
                  ),
                ),
              ),

            // Call Controls
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted ? Colors.redAccent : AppTheme.surfaceColor,
                    onTap: _toggleMute,
                  ),
                  _buildControlButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    onTap: _endCall,
                    size: 64,
                  ),
                  if (widget.isVideo)
                    _buildControlButton(
                      icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
                      color: _isVideoOff ? Colors.redAccent : AppTheme.surfaceColor,
                      onTap: _toggleVideo,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required Color color, required VoidCallback onTap, double size = 56}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}
