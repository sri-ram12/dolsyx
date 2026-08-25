"use client";

import { useRef, useState, useCallback } from "react";

const STUN_CONFIG: RTCConfiguration = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:stun1.l.google.com:19302" },
    { urls: "stun:stun2.l.google.com:19302" },
    { urls: "stun:stun3.l.google.com:19302" },
    { urls: "stun:stun4.l.google.com:19302" },
    { urls: "stun:stun.services.mozilla.com:3478" },
    { urls: "stun:global.stun.twilio.com:3478" },
    {
      urls: "turn:openrelay.metered.ca:80",
      username: "openrelayproject",
      credential: "openrelayproject",
    },
    {
      urls: "turn:openrelay.metered.ca:443",
      username: "openrelayproject",
      credential: "openrelayproject",
    },
    {
      urls: "turn:openrelay.metered.ca:443?transport=tcp",
      username: "openrelayproject",
      credential: "openrelayproject",
    },
  ],
  iceCandidatePoolSize: 10,
  iceTransportPolicy: "all",
  bundlePolicy: "max-bundle",
};

interface UseWebRTCOptions {
  onIceCandidate: (candidate: RTCIceCandidateInit) => void;
}

export const useWebRTC = ({ onIceCandidate }: UseWebRTCOptions) => {
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const localStreamRef = useRef<MediaStream | null>(null);
  const iceCandidateQueueRef = useRef<RTCIceCandidateInit[]>([]);

  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);
  const [isMuted, setIsMuted] = useState(false);
  const [isCameraOff, setIsCameraOff] = useState(false);
  const [isSpeakerOff, setIsSpeakerOff] = useState(false);
  const [isScreenSharing, setIsScreenSharing] = useState(false);
  const [facingMode, setFacingMode] = useState<"user" | "environment">("user");

  const createPeerConnection = useCallback(() => {
    if (pcRef.current) {
      pcRef.current.close();
    }
    const pc = new RTCPeerConnection(STUN_CONFIG);

    pc.onicecandidate = (event) => {
      if (event.candidate) {
        onIceCandidate(event.candidate.toJSON());
      }
    };

    pc.ontrack = (event) => {
      if (event.streams && event.streams[0]) {
        const stream = event.streams[0];
        stream.getAudioTracks().forEach((t) => { t.enabled = true; });
        stream.getVideoTracks().forEach((t) => { t.enabled = true; });
        setRemoteStream(new MediaStream(stream.getTracks()));
      } else {
        setRemoteStream((prev) => {
          const ns = prev ? new MediaStream(prev.getTracks()) : new MediaStream();
          ns.addTrack(event.track);
          event.track.enabled = true;
          return ns;
        });
      }
    };

    pc.onconnectionstatechange = () => {
      // Connection state changed
    };

    pcRef.current = pc;
    return pc;
  }, [onIceCandidate]);

  const getMedia = useCallback(async (callType: "audio" | "video") => {
    const constraints: MediaStreamConstraints = {
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
        sampleRate: { ideal: 48000 },
        channelCount: { ideal: 1 },
      },
      video:
        callType === "video"
          ? {
              width: { ideal: 1920, min: 1280 },
              height: { ideal: 1080, min: 720 },
              frameRate: { ideal: 30, max: 60 },
              facingMode: "user",
            }
          : false,
    };
    const stream = await navigator.mediaDevices.getUserMedia(constraints);
    localStreamRef.current = stream;
    setLocalStream(stream);
    setFacingMode("user"); // reset to front camera
    return stream;
  }, []);

  const createOffer = useCallback(async (callType: "audio" | "video"): Promise<RTCSessionDescriptionInit> => {
    const stream = await getMedia(callType);
    const pc = createPeerConnection();
    stream.getTracks().forEach((track) => pc.addTrack(track, stream));
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return offer;
  }, [getMedia, createPeerConnection]);

  const handleOffer = useCallback(async (offer: RTCSessionDescriptionInit, callType: "audio" | "video"): Promise<RTCSessionDescriptionInit> => {
    const stream = await getMedia(callType);
    const pc = createPeerConnection();
    stream.getTracks().forEach((track) => pc.addTrack(track, stream));
    await pc.setRemoteDescription(new RTCSessionDescription(offer));
    for (const candidate of iceCandidateQueueRef.current) {
      await pc.addIceCandidate(new RTCIceCandidate(candidate));
    }
    iceCandidateQueueRef.current = [];
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer;
  }, [getMedia, createPeerConnection]);

  const handleAnswer = useCallback(async (answer: RTCSessionDescriptionInit) => {
    const pc = pcRef.current;
    if (!pc) return;
    await pc.setRemoteDescription(new RTCSessionDescription(answer));
    for (const candidate of iceCandidateQueueRef.current) {
      await pc.addIceCandidate(new RTCIceCandidate(candidate));
    }
    iceCandidateQueueRef.current = [];
  }, []);

  const addIceCandidate = useCallback(async (candidate: RTCIceCandidateInit) => {
    const pc = pcRef.current;
    if (!pc || !pc.remoteDescription) {
      iceCandidateQueueRef.current.push(candidate);
      return;
    }
    try {
      await pc.addIceCandidate(new RTCIceCandidate(candidate));
    } catch (e) {
      // ICE error suppressed
    }
  }, []);

  const hangup = useCallback(() => {
    localStreamRef.current?.getTracks().forEach((track) => track.stop());
    localStreamRef.current = null;
    setLocalStream(null);
    setRemoteStream(null);
    setIsMuted(false);
    setIsCameraOff(false);
    setIsSpeakerOff(false);
    setFacingMode("user");
    iceCandidateQueueRef.current = [];
    if (pcRef.current) {
      pcRef.current.close();
      pcRef.current = null;
    }
  }, []);

  const toggleMute = useCallback(() => {
    localStreamRef.current?.getAudioTracks().forEach((t) => {
      t.enabled = !t.enabled;
    });
    setIsMuted((prev) => !prev);
  }, []);

  const toggleCamera = useCallback(() => {
    localStreamRef.current?.getVideoTracks().forEach((t) => {
      t.enabled = !t.enabled;
    });
    setIsCameraOff((prev) => !prev);
  }, []);

  const toggleSpeaker = useCallback(() => {
    setIsSpeakerOff((prev) => !prev);
  }, []);

  const switchCallCamera = useCallback(async () => {
    if (!localStreamRef.current) return;
    const newMode = facingMode === "user" ? "environment" : "user";
    setFacingMode(newMode);
    try {
      const oldVideoTrack = localStreamRef.current.getVideoTracks()[0];
      if (oldVideoTrack) {
        oldVideoTrack.stop();
        localStreamRef.current.removeTrack(oldVideoTrack);
      }

      let newStream: MediaStream | null = null;
      try {
        const devices = await navigator.mediaDevices.enumerateDevices();
        const videoDevices = devices.filter(d => d.kind === 'videoinput');
        
        let targetDevice = null;
        if (newMode === 'environment') {
          targetDevice = videoDevices.find(d => d.label.toLowerCase().includes('back') || d.label.toLowerCase().includes('environment'));
        } else {
          targetDevice = videoDevices.find(d => d.label.toLowerCase().includes('front') || d.label.toLowerCase().includes('user'));
        }

        let constraints: any = {
          video: targetDevice ? { deviceId: { exact: targetDevice.deviceId } } : { facingMode: { exact: newMode } },
          audio: false,
        };

        try {
          newStream = await navigator.mediaDevices.getUserMedia(constraints);
        } catch {
        // Fallback or handle failure
          constraints.video = { facingMode: { ideal: newMode } };
          newStream = await navigator.mediaDevices.getUserMedia(constraints);
        }
      } catch {
        newStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      }
      
      if (!newStream) return;
      const newVideoTrack = newStream.getVideoTracks()[0];
      if (!newVideoTrack) return;

      localStreamRef.current.addTrack(newVideoTrack);
      setLocalStream(new MediaStream(localStreamRef.current.getTracks()));

      const pc = pcRef.current;
      if (pc) {
        const senders = pc.getSenders();
        const videoSender = senders.find((s) => s.track?.kind === "video");
        if (videoSender) {
          await videoSender.replaceTrack(newVideoTrack);
        }
      }
    } catch (e) {
      console.error("[WebRTC] switchCallCamera error:", e);
    }
  }, [facingMode]);

  const toggleScreenShare = useCallback(async () => {
    try {
      if (isScreenSharing) {
        // Stop screen share
        const videoTrack = localStreamRef.current?.getVideoTracks()[0];
        const pc = pcRef.current;
        if (pc) {
          const senders = pc.getSenders();
          const videoSender = senders.find((s) => s.track?.kind === "video" || s.track === null);
          if (videoSender && videoTrack) {
            await videoSender.replaceTrack(videoTrack);
          }
        }
        setIsScreenSharing(false);
      } else {
        // Start 60fps zero-lag ultra-low latency screen share
        const screenStream = await navigator.mediaDevices.getDisplayMedia({
          video: {
            cursor: "always",
            frameRate: { ideal: 60, max: 60 },
            width: { max: 1920 },
            height: { max: 1080 },
          },
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          },
        });
        const screenTrack = screenStream.getVideoTracks()[0];
        if (!screenTrack) return;

        // Set low-latency motion hint for zero-lag 60fps screen sharing
        try {
          (screenTrack as any).contentHint = "motion";
        } catch (_) {}

        const pc = pcRef.current;
        if (pc) {
          const senders = pc.getSenders();
          const videoSender = senders.find((s) => s.track?.kind === "video" || (s.track && s.track.kind === "video"));
          if (videoSender) {
            await videoSender.replaceTrack(screenTrack);
            try {
              const params = videoSender.getParameters();
              if (!params.encodings || params.encodings.length === 0) {
                params.encodings = [{}];
              }
              params.encodings[0].maxBitrate = 4000000; // 4 Mbps
              params.encodings[0].maxFramerate = 60;
              params.encodings[0].priority = "high";
              params.encodings[0].networkPriority = "high";
              (params as any).degradationPreference = "maintain-framerate";
              await videoSender.setParameters(params);
            } catch (_) {}
          } else {
            // Audio call converted to screen share: add track
            if (localStreamRef.current) {
              const sender = pc.addTrack(screenTrack, localStreamRef.current);
              try {
                const params = sender.getParameters();
                if (!params.encodings || params.encodings.length === 0) params.encodings = [{}];
                params.encodings[0].maxBitrate = 4000000;
                params.encodings[0].maxFramerate = 60;
                (params as any).degradationPreference = "maintain-framerate";
                await sender.setParameters(params);
              } catch (_) {}
            } else {
              pc.addTrack(screenTrack, screenStream);
            }
          }
        }
        
        setIsScreenSharing(true);

        // Listen for OS-level stream stop
        screenTrack.onended = () => {
          setIsScreenSharing(false);
          const videoTrack = localStreamRef.current?.getVideoTracks()[0];
          if (pc) {
            const senders = pc.getSenders();
            const videoSender = senders.find((s) => s.track?.kind === "video");
            if (videoSender) {
              videoSender.replaceTrack(videoTrack || null);
            }
          }
        };
      }
    } catch (e) {
      console.error("Screen sharing error:", e);
    }
  }, [isScreenSharing]);

  return {
    localStream,
    remoteStream,
    isMuted,
    isCameraOff,
    isSpeakerOff,
    facingMode,
    createOffer,
    handleOffer,
    handleAnswer,
    addIceCandidate,
    hangup,
    toggleMute,
    toggleCamera,
    toggleSpeaker,
    switchCallCamera,
    isScreenSharing,
    toggleScreenShare,
  };
};
