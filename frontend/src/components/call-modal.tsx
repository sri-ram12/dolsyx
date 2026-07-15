"use client";

import React, { useEffect, useRef, useState } from "react";
import {
  Phone,
  Video,
  PhoneOff,
  Mic,
  MicOff,
  VideoOff,
  Volume2,
  VolumeX,
  Camera,
  User,
} from "lucide-react";
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
  duration: number;
}

function VideoPlayer({
  stream,
  muted,
  className,
}: {
  stream: MediaStream | null;
  muted?: boolean;
  className?: string;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.srcObject = stream;
    }
  }, [stream]);

  if (!stream) return null;

  return (
    <video
      ref={videoRef}
      muted={muted}
      className={className}
      autoPlay
      playsInline
    />
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
  duration,
}: CallModalProps) {

  // Audio Ringtone
  useEffect(() => {
    if (status === "incoming" && isOpen) {
      SoundEngine.playRingtone();
    } else {
      SoundEngine.stopRingtone();
    }
    return () => {
      SoundEngine.stopRingtone();
    };
  }, [status, isOpen]);

  if (!isOpen) return null;

  const formatDuration = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, "0")}`;
  };

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/80 backdrop-blur-sm p-4 font-sans select-none">
      <div className="relative w-full max-w-sm bg-gradient-to-b from-slate-900 to-slate-950 rounded-3xl shadow-2xl flex flex-col overflow-hidden border border-slate-700/30" style={{ minHeight: "480px", maxHeight: "90vh" }}>

        {/* Header Info */}
        <div className="flex flex-col items-center pt-12 pb-6 px-6 text-white z-10">
          {/* Call type icon badge */}
          <div className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-[10px] font-bold tracking-widest uppercase mb-3 ${
            callType === "video"
              ? "bg-cyan-500/15 border border-cyan-500/30 text-cyan-300"
              : "bg-emerald-500/15 border border-emerald-500/30 text-emerald-300"
          }`}>
            {callType === "video" ? (
              <><Video className="h-3 w-3" /> Video Call</>
            ) : (
              <><Phone className="h-3 w-3" /> Voice Call</>
            )}
          </div>
          <h2 className="text-2xl font-bold tracking-tight">{callerName}</h2>
          <p className="text-sm text-slate-400 mt-1">
            {status === "incoming"
              ? "Incoming call..."
              : status === "outgoing"
              ? "Calling..."
              : status === "connected"
              ? formatDuration(duration)
              : "Call ended"}
          </p>
        </div>

        {/* Main Content Area */}
        <div className="flex-1 min-h-0 relative overflow-hidden">
          {callType === "video" && status === "connected" ? (
            <div className="relative w-full h-full">
              {/* Remote Video */}
              {remoteStream && !isSpeakerOff ? (
                <VideoPlayer
                  stream={remoteStream}
                  className="w-full h-full object-cover"
                />
              ) : (
                <div className="w-full h-full flex flex-col items-center justify-center bg-slate-950">
                  <div className="relative shrink-0 w-24 h-24 rounded-full border border-slate-700/50 flex items-center justify-center bg-slate-800 text-slate-400">
                    {callerAvatar ? (
                      <img
                        src={getAvatarUrl(callerAvatar, callerName)}
                        alt={callerName}
                        className="w-full h-full rounded-full object-cover"
                      />
                    ) : (
                      <User className="w-12 h-12" />
                    )}
                  </div>
                  <span className="text-xs text-slate-500 mt-4">
                    Remote video is disabled or speaker is off
                  </span>
                </div>
              )}

              {/* Local video (PiP - Picture in Picture) */}
              {!isCameraOff && localStream && (
                <div className="absolute bottom-24 right-4 w-32 h-44 rounded-2xl border-2 border-slate-700/80 shadow-lg overflow-hidden bg-slate-900 z-20">
                  <VideoPlayer
                    stream={localStream}
                    muted
                    className="w-full h-full object-cover"
                  />
                </div>
              )}
            </div>
          ) : (
            // Audio Call or connecting state (large avatar with pulsing background)
            <div className="relative flex items-center justify-center w-full h-full min-h-[200px] pointer-events-none">
              <div
                className={`relative flex items-center justify-center w-36 h-36 rounded-full bg-slate-800 border-4 border-cyan-500/30 ${
                  status === "incoming" || status === "outgoing"
                    ? "animate-pulse"
                    : ""
                }`}
              >
                {callerAvatar ? (
                  <img
                    src={getAvatarUrl(callerAvatar, callerName)}
                    alt={callerName}
                    className="w-full h-full rounded-full object-cover"
                  />
                ) : (
                  <User className="w-16 h-16 text-slate-400" />
                )}
                {/* Ring wave effects */}
                {(status === "incoming" || status === "outgoing") && (
                  <>
                    <div className="absolute inset-0 rounded-full border border-cyan-400 animate-ping opacity-25" />
                    <div className="absolute inset-[-12px] rounded-full border border-cyan-500 animate-ping opacity-15" />
                  </>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Buttons / Controls Overlay */}
        <div className="flex flex-col items-center gap-6 w-full z-10 pb-10 pt-6 px-6">
          {status === "incoming" ? (
            // Incoming Call Buttons
            <div className="flex items-center gap-12">
              <button
                onClick={onDecline}
                className="flex items-center justify-center w-16 h-16 rounded-full bg-red-600 hover:bg-red-500 border border-red-500/20 active:scale-95 transition-all shadow-lg hover:shadow-red-900/50 cursor-pointer animate-[pulse_1.5s_infinite]"
                title="Decline Call"
              >
                <PhoneOff className="w-7 h-7" />
              </button>
              <button
                onClick={onAccept}
                className="flex items-center justify-center w-16 h-16 rounded-full bg-emerald-600 hover:bg-emerald-500 border border-emerald-500/20 active:scale-95 transition-all shadow-lg hover:shadow-emerald-900/50 cursor-pointer animate-[bounce_1.5s_infinite]"
                title="Accept Call"
              >
                <Phone className="w-7 h-7" />
              </button>
            </div>
          ) : (
            // Active / Outgoing Controls
            <div className="flex flex-col items-center gap-6 w-full">
              <div className="flex items-center justify-center gap-6">
                {/* Mute Button */}
                <button
                  onClick={onToggleMute}
                  className={`flex items-center justify-center w-12 h-12 rounded-full border active:scale-95 transition-all cursor-pointer ${
                    isMuted
                      ? "bg-slate-100 text-slate-900 border-slate-200"
                      : "bg-slate-800/80 text-white border-slate-700/60 hover:bg-slate-700"
                  }`}
                  title={isMuted ? "Unmute Mic" : "Mute Mic"}
                >
                  {isMuted ? <MicOff className="w-5 h-5" /> : <Mic className="w-5 h-5" />}
                </button>

                {/* Camera Toggle Button */}
                {callType === "video" && (
                  <button
                    onClick={onToggleCamera}
                    className={`flex items-center justify-center w-12 h-12 rounded-full border active:scale-95 transition-all cursor-pointer ${
                      isCameraOff
                        ? "bg-slate-100 text-slate-900 border-slate-200"
                        : "bg-slate-800/80 text-white border-slate-700/60 hover:bg-slate-700"
                    }`}
                    title={isCameraOff ? "Turn Video On" : "Turn Video Off"}
                  >
                    {isCameraOff ? (
                      <VideoOff className="w-5 h-5" />
                    ) : (
                      <Camera className="w-5 h-5" />
                    )}
                  </button>
                )}

                {/* Speaker Toggle Button */}
                <button
                  onClick={onToggleSpeaker}
                  className={`flex items-center justify-center w-12 h-12 rounded-full border active:scale-95 transition-all cursor-pointer ${
                    isSpeakerOff
                      ? "bg-slate-100 text-slate-900 border-slate-200"
                      : "bg-slate-800/80 text-white border-slate-700/60 hover:bg-slate-700"
                  }`}
                  title={isSpeakerOff ? "Turn Speaker On" : "Turn Speaker Off"}
                >
                  {isSpeakerOff ? (
                    <VolumeX className="w-5 h-5" />
                  ) : (
                    <Volume2 className="w-5 h-5" />
                  )}
                </button>
              </div>

              {/* End Call Button */}
              <button
                onClick={onHangup}
                className="flex items-center justify-center w-16 h-16 rounded-full bg-red-600 hover:bg-red-500 border border-red-500/20 active:scale-95 transition-all shadow-lg hover:shadow-red-900/50 cursor-pointer"
                title="End Call"
              >
                <PhoneOff className="w-7 h-7" />
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
