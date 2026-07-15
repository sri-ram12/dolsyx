"use client";

import { useRef, useState, useCallback } from "react";

const STUN_CONFIG: RTCConfiguration = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:stun1.l.google.com:19302" },
    { urls: "stun:stun2.l.google.com:19302" },
  ],
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

  const createPeerConnection = useCallback(() => {
    if (pcRef.current) { pcRef.current.close(); }
    const pc = new RTCPeerConnection(STUN_CONFIG);
    pc.onicecandidate = (event) => { if (event.candidate) { onIceCandidate(event.candidate.toJSON()); } };
    pc.ontrack = (event) => { const stream = event.streams[0]; if (stream) { setRemoteStream(stream); } };
    pc.onconnectionstatechange = () => { console.log("[WebRTC] Connection state:", pc.connectionState); };
    pcRef.current = pc;
    return pc;
  }, [onIceCandidate]);

  const getMedia = useCallback(async (callType: "audio" | "video") => {
    const constraints: MediaStreamConstraints = {
      audio: { echoCancellation: true, noiseSuppression: true },
      video: callType === "video" ? { width: { ideal: 1280 }, height: { ideal: 720 }, facingMode: "user" } : false,
    };
    const stream = await navigator.mediaDevices.getUserMedia(constraints);
    localStreamRef.current = stream;
    setLocalStream(stream);
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
    for (const candidate of iceCandidateQueueRef.current) { await pc.addIceCandidate(new RTCIceCandidate(candidate)); }
    iceCandidateQueueRef.current = [];
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer;
  }, [getMedia, createPeerConnection]);

  const handleAnswer = useCallback(async (answer: RTCSessionDescriptionInit) => {
    const pc = pcRef.current;
    if (!pc) return;
    await pc.setRemoteDescription(new RTCSessionDescription(answer));
    for (const candidate of iceCandidateQueueRef.current) { await pc.addIceCandidate(new RTCIceCandidate(candidate)); }
    iceCandidateQueueRef.current = [];
  }, []);

  const addIceCandidate = useCallback(async (candidate: RTCIceCandidateInit) => {
    const pc = pcRef.current;
    if (!pc || !pc.remoteDescription) { iceCandidateQueueRef.current.push(candidate); return; }
    try { await pc.addIceCandidate(new RTCIceCandidate(candidate)); } catch (e) { console.warn("[WebRTC] ICE error:", e); }
  }, []);

  const hangup = useCallback(() => {
    localStreamRef.current?.getTracks().forEach((track) => track.stop());
    localStreamRef.current = null;
    setLocalStream(null); setRemoteStream(null);
    setIsMuted(false); setIsCameraOff(false); setIsSpeakerOff(false);
    iceCandidateQueueRef.current = [];
    if (pcRef.current) { pcRef.current.close(); pcRef.current = null; }
  }, []);

  const toggleMute = useCallback(() => {
    localStreamRef.current?.getAudioTracks().forEach((t) => { t.enabled = !t.enabled; });
    setIsMuted((prev) => !prev);
  }, []);

  const toggleCamera = useCallback(() => {
    localStreamRef.current?.getVideoTracks().forEach((t) => { t.enabled = !t.enabled; });
    setIsCameraOff((prev) => !prev);
  }, []);

  const toggleSpeaker = useCallback(() => { setIsSpeakerOff((prev) => !prev); }, []);

  return { localStream, remoteStream, isMuted, isCameraOff, isSpeakerOff, createOffer, handleOffer, handleAnswer, addIceCandidate, hangup, toggleMute, toggleCamera, toggleSpeaker };
};
