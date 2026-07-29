"use client";

import React, { useEffect, useRef, useState } from "react";
import { Phone, Video, PhoneOff, Mic, MicOff, VideoOff, Volume2, VolumeX, Camera, User, RefreshCw } from "lucide-react";
import { getAvatarUrl } from "@/utils/avatar";
import { SoundEngine } from "@/utils/sound";

interface CallModalProps {
  isOpen: boolean;
  callType: "audio" | "video";
  status: "incoming" | "outgoing" | "connected" | "disconnected";
  callerName: string;
  callerAvatar: string | null;
  localStream: MediaStream | null;
  remoteStream: MediaStream | null;
  isMuted: boolean;
  isCameraOff: boolean;
  isSpeakerOff: boolean;
  onAccept: () => void;
  onDecline: () => void;
  onHangup: () => void;
  onToggleMute: () => void;
  onToggleCamera: () => void;
  onToggleSpeaker: () => void;
  onSwitchCamera: () => void;
  isScreenSharing?: boolean;
  onToggleScreenShare?: () => void;
  duration: number;
}

function VideoPlayer({ stream, muted, mirror, className }: { stream: MediaStream | null; muted?: boolean; mirror?: boolean; className?: string; }) {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    if (ref.current) ref.current.srcObject = stream;
  }, [stream]);
  if (!stream) return null;
  return <video ref={ref} autoPlay playsInline muted={muted} className={className} style={mirror ? { transform: "scaleX(-1)" } : undefined} />;
}

// Keep this permanently rendered in DOM with stable ref to bypass dynamic autoplay blocks
function RemoteAudio({ stream, muted }: { stream: MediaStream | null; muted: boolean }) {
  const ref = useRef<HTMLAudioElement>(null);
  useEffect(() => {
    if (ref.current) {
      ref.current.srcObject = stream;
    }
  }, [stream]);
  useEffect(() => {
    if (ref.current) {
      ref.current.muted = muted;
    }
  }, [muted]);
  return <audio ref={ref} autoPlay playsInline style={{ display: "none" }} />;
}

function CtrlBtn({ onClick, active, title, children }: { onClick: () => void; active?: boolean; title: string; children: React.ReactNode; }) {
  return (
    <div className="flex flex-col items-center gap-1.5">
      <button onClick={onClick} title={title} className={`flex items-center justify-center w-[52px] h-[52px] rounded-full border active:scale-95 transition-all cursor-pointer ${active ? "bg-white text-slate-900 border-white/80" : "bg-white/10 text-white border-white/20 hover:bg-white/20"}`}>
        {children}
      </button>
      <span className="text-[10px] text-white/50">{title}</span>
    </div>
  );
}

export default function CallModal({
  isOpen,
  callType,
  status,
  callerName,
  callerAvatar,
  localStream,
  remoteStream,
  isMuted,
  isCameraOff,
  isSpeakerOff,
  onAccept,
  onDecline,
  onHangup,
  onToggleMute,
  onToggleCamera,
  onToggleSpeaker,
  onSwitchCamera,
  isScreenSharing,
  onToggleScreenShare,
  duration
}: CallModalProps) {
  const [localVideoPosition, setLocalVideoPosition] = useState({ x: 16, y: 96 });
  const [isDraggingLocal, setIsDraggingLocal] = useState(false);
  const [isLocalFullScreen, setIsLocalFullScreen] = useState(false);
  const dragStartRef = useRef<{ x: number, y: number, startPosX: number, startPosY: number } | null>(null);

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    dragStartRef.current = { x: e.clientX, y: e.clientY, startPosX: localVideoPosition.x, startPosY: localVideoPosition.y };
    setIsDraggingLocal(true);
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!isDraggingLocal || !dragStartRef.current) return;
    const dx = e.clientX - dragStartRef.current.x;
    const dy = e.clientY - dragStartRef.current.y;
    setLocalVideoPosition({
      x: dragStartRef.current.startPosX - dx,
      y: dragStartRef.current.startPosY + dy
    });
  };
  const handlePointerUp = (e: React.PointerEvent<HTMLDivElement>) => {
    setIsDraggingLocal(false);
    dragStartRef.current = null;
    e.currentTarget.releasePointerCapture(e.pointerId);
  };

  useEffect(() => {
    if (status === "incoming" && isOpen) SoundEngine.playRingtone();
    else SoundEngine.stopRingtone();
    return () => SoundEngine.stopRingtone();
  }, [status, isOpen]);

  if (!isOpen) return null;

  const fmt = (s: number) => `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, "0")}`;
  const isVideoConnected = callType === "video" && status === "connected";
  const statusText = status === "incoming" ? "Incoming call..." : status === "outgoing" ? "Calling..." : status === "connected" ? fmt(duration) : "Call ended";

  return (
    <div className="fixed inset-0 z-[9999] flex flex-col bg-black select-none font-sans">
      <RemoteAudio stream={remoteStream} muted={isSpeakerOff} />

      {isVideoConnected ? (
        <div className="relative flex-1 bg-black overflow-hidden">
          {isLocalFullScreen ? (
            <VideoPlayer stream={localStream} muted mirror className="absolute inset-0 w-full h-full object-cover" />
          ) : remoteStream ? (
            <VideoPlayer stream={remoteStream} className="absolute inset-0 w-full h-full object-cover" />
          ) : (
            <div className="absolute inset-0 flex flex-col items-center justify-center bg-slate-950">
              <div className="w-28 h-28 rounded-full overflow-hidden bg-slate-800 border-2 border-slate-600 mb-4 flex items-center justify-center">
                {callerAvatar ? <img src={getAvatarUrl(callerAvatar, callerName)} alt={callerName} className="w-full h-full object-cover" /> : <User className="w-14 h-14 text-slate-400" />}
              </div>
              <p className="text-white font-semibold text-lg">{callerName}</p>
              <p className="text-slate-400 text-sm mt-1">Connecting video...</p>
            </div>
          )}
          
          <div className="absolute top-0 left-0 right-0 z-20 px-4 pt-12 pb-8 bg-gradient-to-b from-black/70 to-transparent pointer-events-none">
            <p className="text-white text-center font-bold text-xl tracking-wide">{callerName}</p>
            <p className="text-slate-300 text-center text-sm">{statusText}</p>
          </div>

          {!isLocalFullScreen && !isCameraOff && localStream && (
            <div 
              className="absolute w-28 h-44 rounded-2xl overflow-hidden border-2 border-white/25 shadow-2xl z-30 bg-slate-900 cursor-move"
              style={{ top: `${localVideoPosition.y}px`, right: `${localVideoPosition.x}px`, touchAction: 'none' }}
              onPointerDown={handlePointerDown}
              onPointerMove={handlePointerMove}
              onPointerUp={handlePointerUp}
              onPointerCancel={handlePointerUp}
              onDoubleClick={() => setIsLocalFullScreen(true)}
              title="Double click to maximize"
            >
              <VideoPlayer stream={localStream} muted mirror className="w-full h-full object-cover pointer-events-none" />
            </div>
          )}

          {isLocalFullScreen && remoteStream && (
            <div 
              className="absolute w-28 h-44 rounded-2xl overflow-hidden border-2 border-white/25 shadow-2xl z-30 bg-slate-900 cursor-move"
              style={{ top: `${localVideoPosition.y}px`, right: `${localVideoPosition.x}px`, touchAction: 'none' }}
              onPointerDown={handlePointerDown}
              onPointerMove={handlePointerMove}
              onPointerUp={handlePointerUp}
              onPointerCancel={handlePointerUp}
              onDoubleClick={() => setIsLocalFullScreen(false)}
              title="Double click to maximize"
            >
              <VideoPlayer stream={remoteStream} className="w-full h-full object-cover pointer-events-none" />
            </div>
          )}
          <div className="absolute bottom-0 left-0 right-0 z-20 pb-12 pt-6 px-8 bg-gradient-to-t from-black/75 to-transparent">
            <div className="flex items-end justify-center gap-7 mb-6">
              <CtrlBtn onClick={onToggleMute} active={isMuted} title={isMuted ? "Unmute" : "Mute"}>{isMuted ? <MicOff className="w-5 h-5" /> : <Mic className="w-5 h-5" />}</CtrlBtn>
              <CtrlBtn onClick={onToggleCamera} active={isCameraOff} title={isCameraOff ? "Cam On" : "Cam Off"}>{isCameraOff ? <VideoOff className="w-5 h-5" /> : <Camera className="w-5 h-5" />}</CtrlBtn>
              <CtrlBtn onClick={onSwitchCamera} title="Switch Cam">
                <RefreshCw className="w-5 h-5" />
              </CtrlBtn>
              <CtrlBtn onClick={onToggleSpeaker} active={isSpeakerOff} title={isSpeakerOff ? "Speaker On" : "Speaker"}>{isSpeakerOff ? <VolumeX className="w-5 h-5" /> : <Volume2 className="w-5 h-5" />}</CtrlBtn>
            </div>
            <div className="flex justify-center">
              <button onClick={onHangup} className="flex items-center justify-center w-16 h-16 rounded-full bg-red-600 hover:bg-red-500 active:scale-95 transition-all shadow-xl cursor-pointer"><PhoneOff className="w-7 h-7 text-white" /></button>
            </div>
          </div>
        </div>
      ) : (
        <div className="flex-1 flex flex-col bg-black">
          <div className="flex flex-col items-center pt-24 pb-6 px-6 text-white">
            <div className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-[10px] font-bold tracking-widest uppercase mb-5 ${callType === "video" ? "bg-cyan-500/15 border border-cyan-500/30 text-cyan-300" : "bg-emerald-500/15 border border-emerald-500/30 text-emerald-300"}`}>
              {callType === "video" ? <><Video className="h-3 w-3" /> Video Call</> : <><Phone className="h-3 w-3" /> Voice Call</>}
            </div>
            <h2 className="text-3xl font-bold tracking-tight">{callerName}</h2>
            <p className="text-slate-400 mt-2 text-base">{statusText}</p>
          </div>
          <div className="flex-1 flex items-center justify-center">
            <div className="relative flex items-center justify-center">
              {(status === "incoming" || status === "outgoing") && (
                <>
                  <div className="absolute inset-[-24px] rounded-full border border-purple-400/25 animate-ping" />
                  <div className="absolute inset-[-44px] rounded-full border border-purple-400/12 animate-ping" style={{ animationDelay: "0.4s" }} />
                </>
              )}
              <div className="w-44 h-44 rounded-full border-4 border-slate-700/60 overflow-hidden bg-slate-800 flex items-center justify-center shadow-2xl">
                {callerAvatar ? <img src={getAvatarUrl(callerAvatar, callerName)} alt={callerName} className="w-full h-full object-cover" /> : <User className="w-24 h-24 text-slate-400" />}
              </div>
            </div>
          </div>
          <div className="flex flex-col items-center gap-8 pb-20 px-8">
            {status === "incoming" ? (
              <div className="flex items-center gap-20">
                <div className="flex flex-col items-center gap-2">
                  <button onClick={onDecline} className="flex items-center justify-center w-16 h-16 rounded-full bg-red-600 hover:bg-red-500 active:scale-95 transition-all shadow-xl cursor-pointer"><PhoneOff className="w-7 h-7 text-white" /></button>
                  <span className="text-slate-400 text-xs">Decline</span>
                </div>
                <div className="flex flex-col items-center gap-2">
                  <button onClick={onAccept} className={`flex items-center justify-center w-16 h-16 rounded-full active:scale-95 transition-all shadow-xl cursor-pointer animate-bounce ${callType === "video" ? "bg-cyan-600 hover:bg-cyan-500" : "bg-emerald-600 hover:bg-emerald-500"}`}>
                    {callType === "video" ? <Video className="w-7 h-7 text-white" /> : <Phone className="w-7 h-7 text-white" />}
                  </button>
                  <span className="text-slate-400 text-xs">Accept</span>
                </div>
              </div>
            ) : (
              <>
                <div className="flex items-center gap-7">
                  <CtrlBtn onClick={onToggleMute} active={isMuted} title={isMuted ? "Unmute" : "Mute"}>{isMuted ? <MicOff className="w-5 h-5" /> : <Mic className="w-5 h-5" />}</CtrlBtn>
                  {callType === "video" && (
                    <>
                      <CtrlBtn
                        active={isScreenSharing}
                        onClick={() => onToggleScreenShare?.()}
                        title={isScreenSharing ? "Stop Sharing" : "Share Screen"}
                      >
                        <RefreshCw className="h-6 w-6" />
                      </CtrlBtn>
                      <CtrlBtn
                        active={isCameraOff}
                        onClick={onToggleCamera}
                        title={isCameraOff ? "Camera Off" : "Camera On"}
                      >
                        {isCameraOff ? <VideoOff className="h-6 w-6" /> : <Video className="h-6 w-6" />}
                      </CtrlBtn>
                    </>
                  )}
                  <CtrlBtn onClick={onToggleSpeaker} active={isSpeakerOff} title={isSpeakerOff ? "Speaker On" : "Speaker"}>{isSpeakerOff ? <VolumeX className="w-5 h-5" /> : <Volume2 className="w-5 h-5" />}</CtrlBtn>
                </div>
                <button onClick={onHangup} className="flex items-center justify-center w-16 h-16 rounded-full bg-red-600 hover:bg-red-500 active:scale-95 transition-all shadow-xl cursor-pointer"><PhoneOff className="w-7 h-7 text-white" /></button>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
