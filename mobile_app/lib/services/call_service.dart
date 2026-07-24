import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'socket_service.dart';

class CallService {
  final SocketService _socketService;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;
  Function()? onCallEnded;
  
  String? _remoteUserId;
  String? _conversationId;
  String _callType = 'video';

  CallService(this._socketService) {
    _socketService.socket?.on('ice_candidate', (data) {
      print("WEBRTC: Received ice_candidate from \${data['fromUserId']}");
      if (data['fromUserId'] == _remoteUserId && _peerConnection != null) {
        _peerConnection!.addCandidate(
          RTCIceCandidate(
            data['candidate']['candidate'],
            data['candidate']['sdpMid'],
            data['candidate']['sdpMLineIndex'],
          ),
        );
      }
    });

    _socketService.socket?.on('call_ended', (data) {
      print('WEBRTC: Received call_ended');
      _cleanUp();
      if (onCallEnded != null) onCallEnded!();
    });
  }

  Future<void> startCall(String targetUserId, String conversationId, bool isVideo, String callerName, String? callerAvatar) async {
    _remoteUserId = targetUserId;
    _conversationId = conversationId;
    _callType = isVideo ? 'video' : 'audio';

    await _initializePeerConnection(isVideo);

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    print('WEBRTC: Emitting call_offer to $targetUserId');
    _socketService.socket?.emit('call_offer', {
      'targetUserId': targetUserId,
      'conversationId': conversationId,
      'callType': _callType,
      'callerName': callerName,
      'callerAvatar': callerAvatar,
      'offer': {
        'type': offer.type,
        'sdp': offer.sdp,
      }
    });

    _socketService.socket?.once('call_answered', (data) async {
      print('WEBRTC: Received call_answered');
      final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
      await _peerConnection!.setRemoteDescription(answer);
    });
    
    _socketService.socket?.once('call_rejected', (data) {
      print('WEBRTC: Received call_rejected');
      _cleanUp();
      if (onCallEnded != null) onCallEnded!();
    });
  }

  Future<void> answerCall(String callerId, String conversationId, dynamic offerData, String callType) async {
    _remoteUserId = callerId;
    _conversationId = conversationId;
    _callType = callType;

    await _initializePeerConnection(callType == 'video');

    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnection!.setRemoteDescription(offer);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _socketService.socket?.emit('call_answer', {
      'callerId': callerId,
      'answer': {
        'type': answer.type,
        'sdp': answer.sdp,
      }
    });
  }

  Future<void> _initializePeerConnection(bool isVideo) async {
    final configuration = {
      'iceServers': [
        {
          'urls': ['stun:stun.l.google.com:19302']
        },
      ]
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      print('WEBRTC: Emitting local ice_candidate');
      if (_remoteUserId != null) {
        _socketService.socket?.emit('ice_candidate', {
          'targetUserId': _remoteUserId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }
        });
      }
    };

    _peerConnection!.onAddStream = (stream) {
      print('WEBRTC: Received remote stream');
      if (onRemoteStream != null) onRemoteStream!(stream);
    };

    final mediaConstraints = {
      'audio': true,
      'video': isVideo ? {
        'facingMode': 'user',
      } : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (onLocalStream != null) onLocalStream!(_localStream!);
    
    // Add local stream to the peer connection so tracks are sent to the remote side
    await _peerConnection!.addStream(_localStream!);
  }

  void endCall() {
    if (_remoteUserId != null) {
      _socketService.socket?.emit('call_end', {
        'peerId': _remoteUserId,
        'conversationId': _conversationId,
        'callType': _callType,
        'status': 'connected', // Simplification
      });
    }
    _cleanUp();
    if (onCallEnded != null) onCallEnded!();
  }

  void _cleanUp() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;
    
    _peerConnection?.close();
    _peerConnection = null;
    
    _remoteUserId = null;
    _conversationId = null;
  }
}
