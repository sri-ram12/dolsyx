"use client";

import { useRef, useState, useCallback } from "react";

const STUN_CONFIG: RTCConfiguration = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:stun1.l.google.com:19302" },
    { urls: "stun:stun2.l.google.com:19302" },
    { urls: "stun:stun3.l.google.com:19302" },
    { urls: "stun:stun4.l.google.com:19302" },
    { urls: "stun:stun.cloudflare.com:3478" },
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
    {
      urls: "turn:openrelay.metered.ca:80?transport=udp",
      username: "openrelayproject",
      credential: "openrelayproject",
    },
  ],
  iceCandidatePoolSize: 10,
  iceTransportPolicy: "all",
  bundlePolicy: "max-bundle",
  rtcpMuxPolicy: "require",
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
      console.log("[WebRTC] ontrack track type:", event.track.kind);
      if (event.streams && event.streams[0]) {
        setRemoteStream(event.streams[0]);
      } else {
        setRemoteStream((prev) => {
          if (prev) {
            prev.addTrack(event.track);
            return prev;
          }
          const ns = new MediaStream();
          ns.addTrack(event.track);
          return ns;
        });
      }
    };

    pc.onconnectionstatechange = () => {
      console.log("[WebRTC] Connection state:", pc.connectionState);
    };

    pcRef.current = pc;
    return pc;
  }, [onIceCandidate]);

  const getMedia = useCallback(async (callType: "audio" | "video") => {
    const constraints: MediaStreamConstraints = {
      audio: { echoCancellation: true, noiseSuppression: true },
      video:
        callType === "video"
          ? {
              width: { ideal: 640 },
              height: { ideal: 480 },
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
      console.warn("[WebRTC] ICE error:", e);
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
      const constraints = {
        video: { facingMode: { ideal: newMode }, width: { ideal: 640 }, height: { ideal: 480 } },
        audio: false,
      };
      const newStream = await navigator.mediaDevices.getUserMedia(constraints);
      const newVideoTrack = newStream.getVideoTracks()[0];
      if (!newVideoTrack) return;

      const videoTrack = localStreamRef.current.getVideoTracks()[0];
      if (videoTrack) {
        videoTrack.stop();
        localStreamRef.current.removeTrack(videoTrack);
      }
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
  };
};
