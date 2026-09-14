"use client";

import React, { useState, useEffect, useRef } from "react";
import {
  Sparkles,
  Send,
  Loader2,
  Bot,
  Image as ImageIcon,
  CheckCircle2,
  Maximize2,
  X,
  RefreshCw,
  Copy,
  Check,
  Paperclip,
  Share2,
  Code,
  Download,
  Terminal,
  HelpCircle,
  Zap,
  ArrowRight,
  MessageSquare,
} from "lucide-react";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";
import { Chat } from "@/components/chat-sidebar";

export interface AiMessage {
  id: string;
  sender: "user" | "ai";
  text: string;
  time: string;
  type?: "text" | "image_result" | "code_result" | "chat_summary";
  imageUrl?: string | null;
  imagePrompt?: string | null;
  attachedImage?: string | null;
}

interface AiWorkspaceProps {
  initialPrompt?: string;
  chats?: Chat[];
  onSelectChat?: (chat: Chat) => void;
}

const QUICK_PROMPTS = [
  "Explain AWS EC2 simply",
  "Write a Java solution for Two Sum",
  "Generate an image of a futuristic cyberpunk city",
  "Create a professional resume summary",
  "Compare Docker vs Kubernetes",
  "Generate a modern logo for my startup",
  "Help me debug and optimize this code",
  "Create a study plan for System Design",
];

const STYLE_PRESETS = [
  "Photorealistic",
  "Cinematic",
  "Anime",
  "3D Render",
  "Cyberpunk",
  "Minimalist",
];

export default function AiWorkspace({ initialPrompt, chats = [], onSelectChat }: AiWorkspaceProps) {
  const { user, token } = useAuth();
  const { currentTheme } = useTheme();

  const [messages, setMessages] = useState<AiMessage[]>([]);
  const [inputText, setInputText] = useState("");
  const [isThinking, setIsThinking] = useState(false);
  const [activePreset, setActivePreset] = useState("Photorealistic");
  const [fullscreenImage, setFullscreenImage] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [attachedImage, setAttachedImage] = useState<string | null>(null);
  const [shareTargetMsg, setShareTargetMsg] = useState<AiMessage | null>(null);
  const [isSharing, setIsSharing] = useState(false);
  const [shareSuccess, setShareSuccess] = useState(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const initialSentRef = useRef(false);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isThinking]);

  // If initialPrompt is passed from the search bar, send it on mount
  useEffect(() => {
    if (initialPrompt && initialPrompt.trim() && !initialSentRef.current) {
      initialSentRef.current = true;
      handleSend(initialPrompt.trim());
    }
  }, [initialPrompt]);

  const handleImageAttachment = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith("image/")) {
      alert("Please upload an image file (PNG, JPG, WEBP).");
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      setAttachedImage(reader.result as string);
    };
    reader.readAsDataURL(file);
    e.target.value = "";
  };

  const handleSend = async (promptToSend?: string) => {
    const prompt = (promptToSend || inputText).trim();
    if (!prompt && !attachedImage) return;
    if (isThinking) return;

    const currentAttached = attachedImage;
    setAttachedImage(null);
    setInputText("");

    const userMsgTime = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    const userMessageId = Date.now().toString();

    const userMessage: AiMessage = {
      id: userMessageId,
      sender: "user",
      text: prompt || "Analyze this attached image",
      time: userMsgTime,
      type: "text",
      attachedImage: currentAttached,
    };

    setMessages((prev) => [...prev, userMessage]);
    setIsThinking(true);

    const aiMessageId = (Date.now() + 1).toString();
    const aiMsgTime = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

    // Multimodal Vision Query
    if (currentAttached) {
      try {
        const res = await fetch(`${API_URL}/api/ai/analyze-image`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
          },
          body: JSON.stringify({
            prompt: prompt || "Analyze and describe this image in detail.",
            imageUrl: currentAttached,
          }),
        });

        if (res.ok) {
          const data = await res.json();
          setMessages((prev) => [
            ...prev,
            {
              id: aiMessageId,
              sender: "ai",
              text: data.reply || "Image analysis completed.",
              time: aiMsgTime,
              type: "text",
            },
          ]);
          setIsThinking(false);
          return;
        }
      } catch (e) {
        console.error("Multimodal error:", e);
      }
    }

    // Standard Chat & Image Generation Query via Unified Backend
    try {
      const res = await fetch(`${API_URL}/api/ai/chat`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({
          prompt,
          preset: activePreset.toLowerCase(),
        }),
      });

      if (res.ok) {
        const data = await res.json();
        let replyText = data.reply || "";
        let type: "text" | "image_result" = data.type === "image_result" || data.imageUrl ? "image_result" : "text";
        let imageUrl = data.imageUrl || data.media?.url || null;

        try {
          if (typeof replyText === "string" && replyText.startsWith("{")) {
            const parsed = JSON.parse(replyText);
            if (parsed.type === "image_result" || parsed.imageUrl) {
              type = "image_result";
              imageUrl = parsed.imageUrl || parsed.media?.url || imageUrl;
              replyText = parsed.text || parsed.reply || "Here is your generated image ✨";
            } else if (parsed.text || parsed.reply) {
              replyText = parsed.text || parsed.reply;
            }
          }
        } catch (_) {}

        setMessages((prev) => [
          ...prev,
          {
            id: aiMessageId,
            sender: "ai",
            text: replyText || "Here is your response.",
            time: aiMsgTime,
            type,
            imageUrl,
            imagePrompt: prompt,
          },
        ]);
        setIsThinking(false);
        return;
      }
    } catch (err) {
      console.error("AI execution error:", err);
    }

    // Graceful error state
    setMessages((prev) => [
      ...prev,
      {
        id: aiMessageId,
        sender: "ai",
        text: "DOLSYX AI encountered a network delay. Please verify your connection and try again.",
        time: aiMsgTime,
        type: "text",
      },
    ]);
    setIsThinking(false);
  };

  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const handleShareToChat = async (targetChatId: string) => {
    if (!shareTargetMsg || !token) return;
    setIsSharing(true);

    try {
      const content = shareTargetMsg.imageUrl
        ? shareTargetMsg.imageUrl
        : shareTargetMsg.text;

      const mediaType = shareTargetMsg.imageUrl ? "IMAGE" : "TEXT";

      const res = await fetch(`${API_URL}/api/messages`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          conversationId: targetChatId,
          content,
          mediaType,
          mediaUrl: shareTargetMsg.imageUrl || undefined,
        }),
      });

      if (res.ok) {
        setShareSuccess(true);
        setTimeout(() => {
          setShareSuccess(false);
          setShareTargetMsg(null);
          const target = chats.find((c) => c.id === targetChatId);
          if (target && onSelectChat) {
            onSelectChat(target);
          }
        }, 800);
      } else {
        alert("Failed to share message to chat.");
      }
    } catch (e) {
      console.error("Share error:", e);
      alert("Error connecting to chat server.");
    } finally {
      setIsSharing(false);
    }
  };

  // Helper to parse message text into text and code blocks
  const renderFormattedContent = (content: string, msgId: string) => {
    const codeBlockRegex = /```([a-zA-Z0-9_-]*)\n([\s\S]*?)```/g;
    const parts = [];
    let lastIndex = 0;
    let match;

    while ((match = codeBlockRegex.exec(content)) !== null) {
      if (match.index > lastIndex) {
        parts.push({
          type: "text",
          content: content.substring(lastIndex, match.index),
        });
      }

      parts.push({
        type: "code",
        language: match[1] || "code",
        code: match[2].trim(),
      });

      lastIndex = match.index + match[0].length;
    }

    if (lastIndex < content.length) {
      parts.push({
        type: "text",
        content: content.substring(lastIndex),
      });
    }

    if (parts.length === 0) {
      return <p className="text-sm font-medium whitespace-pre-wrap leading-relaxed">{content}</p>;
    }

    return (
      <div className="space-y-3">
        {parts.map((part, idx) => {
          if (part.type === "code") {
            const codeKey = `${msgId}_code_${idx}`;
            return (
              <div key={idx} className="rounded-xl overflow-hidden border border-purple-500/30 bg-[#090d16] text-slate-100 my-2 shadow-lg">
                <div className="flex items-center justify-between px-3 py-1.5 bg-slate-900/90 border-b border-purple-500/20 text-xs text-purple-300">
                  <div className="flex items-center gap-1.5 font-mono">
                    <Terminal className="h-3.5 w-3.5 text-purple-400" />
                    <span>{part.language || "code"}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleCopy(part.code || "", codeKey)}
                      className="hover:text-white flex items-center gap-1 cursor-pointer transition-colors px-1.5 py-0.5 rounded bg-white/5"
                    >
                      {copiedId === codeKey ? (
                        <>
                          <Check className="h-3 w-3 text-green-400" /> Copied
                        </>
                      ) : (
                        <>
                          <Copy className="h-3 w-3" /> Copy Code
                        </>
                      )}
                    </button>
                    <button
                      onClick={() => handleSend(`Explain this ${part.language} code step by step:\n\n${part.code}`)}
                      className="hover:text-purple-200 flex items-center gap-1 cursor-pointer px-1.5 py-0.5 rounded bg-purple-500/10 hover:bg-purple-500/20 transition-colors"
                      title="Ask AI to Explain"
                    >
                      <HelpCircle className="h-3 w-3" /> Explain
                    </button>
                    <button
                      onClick={() => handleSend(`Optimize and refactor this ${part.language} code for better performance and clean architecture:\n\n${part.code}`)}
                      className="hover:text-emerald-200 flex items-center gap-1 cursor-pointer px-1.5 py-0.5 rounded bg-emerald-500/10 hover:bg-emerald-500/20 transition-colors text-emerald-400"
                      title="Optimize Code"
                    >
                      <Zap className="h-3 w-3" /> Optimize
                    </button>
                  </div>
                </div>
                <pre className="p-3.5 text-xs font-mono overflow-x-auto text-emerald-300 leading-relaxed">
                  <code>{part.code}</code>
                </pre>
              </div>
            );
          }
          return (
            <p key={idx} className="text-sm font-medium whitespace-pre-wrap leading-relaxed">
              {part.content}
            </p>
          );
        })}
      </div>
    );
  };

  return (
    <div className="flex flex-col h-full w-full bg-[var(--theme-bg-app)] text-[var(--theme-text-primary)] relative overflow-hidden">
      {/* AI Header */}
      <div className="flex items-center justify-between px-6 py-3.5 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] backdrop-blur-md z-10">
        <div className="flex items-center gap-3">
          <div className="p-0.5 rounded-full bg-gradient-to-tr from-purple-500 via-pink-500 to-blue-500 shadow-md">
            <div className="w-9 h-9 rounded-full bg-zinc-900 flex items-center justify-center">
              <Sparkles className="h-5 w-5 text-purple-400 animate-pulse" />
            </div>
          </div>
          <div>
            <div className="flex items-center gap-1.5">
              <h2 className="font-extrabold text-base tracking-wide">DOLSYX AI</h2>
              <span className="bg-purple-500/20 text-purple-300 border border-purple-500/30 text-[10px] font-bold px-1.5 py-0.5 rounded-full flex items-center gap-0.5">
                <CheckCircle2 className="h-3 w-3 text-purple-400" /> Neural Assistant
              </span>
            </div>
            <p className="text-[11px] text-[var(--theme-text-secondary)]">Search, Coding, Image Generation & Multimodal Vision</p>
          </div>
        </div>

        {/* Style Presets Dropdown */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-[var(--theme-text-secondary)] hidden sm:inline">Image Style:</span>
          <div className="flex items-center gap-1 bg-white/5 border border-[var(--theme-border-color)] rounded-xl px-2 py-1">
            <ImageIcon className="h-3.5 w-3.5 text-purple-400" />
            <select
              value={activePreset}
              onChange={(e) => setActivePreset(e.target.value)}
              className="bg-transparent text-xs font-semibold focus:outline-none cursor-pointer text-[var(--theme-text-primary)]"
            >
              {STYLE_PRESETS.map((preset) => (
                <option key={preset} value={preset} className="bg-zinc-900 text-white">
                  {preset}
                </option>
              ))}
            </select>
          </div>

          {messages.length > 0 && (
            <button
              onClick={() => setMessages([])}
              className="p-2 rounded-xl border border-[var(--theme-border-color)] hover:bg-white/10 text-xs font-bold text-[var(--theme-text-secondary)] hover:text-white transition-colors cursor-pointer"
              title="Clear Conversation"
            >
              <RefreshCw className="h-4 w-4" />
            </button>
          )}
        </div>
      </div>

      {/* Main Stream Area */}
      <div className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
        {messages.length === 0 ? (
          /* Welcome View */
          <div className="max-w-2xl mx-auto flex flex-col items-center justify-center min-h-[65vh] text-center px-4">
            <div className="p-3 rounded-3xl bg-gradient-to-tr from-purple-500/20 via-pink-500/20 to-blue-500/20 border border-purple-500/30 mb-6 shadow-xl">
              <Bot className="h-14 w-14 text-purple-400" />
            </div>

            <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight mb-2 bg-clip-text text-transparent bg-gradient-to-r from-white via-slate-200 to-purple-300">
              Welcome to DOLSYX AI
            </h1>
            <p className="text-sm text-[var(--theme-text-secondary)] max-w-md mb-8">
              Ask anything, write code, generate photorealistic images, debug errors, or analyze diagrams.
            </p>

            {/* Quick Prompts Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 w-full text-left">
              {QUICK_PROMPTS.map((prompt, idx) => (
                <button
                  key={idx}
                  onClick={() => handleSend(prompt)}
                  className="flex items-center gap-3 p-3.5 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] hover:border-purple-500/50 hover:bg-white/5 transition-all group cursor-pointer shadow-sm text-left"
                >
                  <Sparkles className="h-4 w-4 text-purple-400 shrink-0 group-hover:scale-110 transition-transform" />
                  <span className="text-xs font-semibold text-[var(--theme-text-primary)] group-hover:text-purple-300 transition-colors">
                    {prompt}
                  </span>
                </button>
              ))}
            </div>
          </div>
        ) : (
          /* Messages Stream */
          <div className="max-w-3xl mx-auto space-y-4">
            {messages.map((msg) => {
              const isUser = msg.sender === "user";

              return (
                <div
                  key={msg.id}
                  className={`flex flex-col ${isUser ? "items-end" : "items-start"} animate-fade-in`}
                >
                  <div
                    className={`relative max-w-[88%] rounded-2xl p-4 shadow-md ${
                      isUser
                        ? "rounded-br-none bg-[var(--theme-bubble-sent)] text-[var(--theme-bubble-sent-text)]"
                        : "rounded-bl-none bg-[var(--theme-bubble-received)] text-[var(--theme-bubble-received-text)] border border-[var(--theme-border-color)]"
                    }`}
                  >
                    {/* Render Attached Image on User Message */}
                    {msg.attachedImage && (
                      <div className="mb-2 rounded-xl overflow-hidden border border-white/10 max-h-48 max-w-xs">
                        <img src={msg.attachedImage} alt="User attachment" className="object-cover w-full h-full" />
                      </div>
                    )}

                    {/* Render Generated Image If Available */}
                    {msg.imageUrl && (
                      <div className="relative group mb-3 rounded-xl overflow-hidden border border-purple-500/30 shadow-lg">
                        <img
                          src={msg.imageUrl}
                          alt="AI Output"
                          className="w-full max-h-[460px] object-cover rounded-xl transition-transform duration-300 group-hover:scale-101"
                        />
                        <div className="absolute top-2 right-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            onClick={() => setFullscreenImage(msg.imageUrl!)}
                            className="p-1.5 rounded-lg bg-black/70 text-white cursor-pointer hover:bg-black/90"
                            title="Fullscreen"
                          >
                            <Maximize2 className="h-4 w-4" />
                          </button>
                          <a
                            href={msg.imageUrl}
                            target="_blank"
                            rel="noreferrer"
                            download="dolsyx-ai-image.jpg"
                            className="p-1.5 rounded-lg bg-black/70 text-white cursor-pointer hover:bg-black/90"
                            title="Download Image"
                          >
                            <Download className="h-4 w-4" />
                          </a>
                        </div>
                      </div>
                    )}

                    {/* Formatted Text & Code Content */}
                    {renderFormattedContent(msg.text, msg.id)}

                    {/* Message Actions */}
                    <div className="flex items-center justify-between gap-4 mt-2.5 pt-1.5 border-t border-white/10 text-[10px] opacity-75">
                      <span>{msg.time}</span>
                      <div className="flex items-center gap-3">
                        {!isUser && (
                          <>
                            <button
                              onClick={() => handleCopy(msg.text, msg.id)}
                              className="hover:opacity-100 cursor-pointer flex items-center gap-1 text-[var(--theme-text-secondary)] hover:text-white"
                            >
                              {copiedId === msg.id ? (
                                <>
                                  <Check className="h-3 w-3 text-green-400" /> Copied
                                </>
                              ) : (
                                <>
                                  <Copy className="h-3 w-3" /> Copy
                                </>
                              )}
                            </button>
                            <button
                              onClick={() => setShareTargetMsg(msg)}
                              className="hover:opacity-100 cursor-pointer flex items-center gap-1 text-purple-300 hover:text-purple-200"
                              title="Send to DOLSYX Chat"
                            >
                              <Share2 className="h-3 w-3" /> Send to Chat
                            </button>
                          </>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}

            {isThinking && (
              <div className="flex items-center gap-2 p-3.5 rounded-2xl bg-[var(--theme-bubble-received)] border border-purple-500/30 max-w-xs animate-pulse">
                <Loader2 className="h-4 w-4 animate-spin text-purple-400" />
                <span className="text-xs font-semibold text-purple-300">
                  DOLSYX AI is generating...
                </span>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Input Bar with Image Attachment */}
      <div className="p-4 border-t border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] backdrop-blur-md">
        {attachedImage && (
          <div className="max-w-3xl mx-auto mb-2 flex items-center gap-2 p-2 rounded-xl bg-purple-500/10 border border-purple-500/30">
            <img src={attachedImage} alt="Attachment" className="h-10 w-10 object-cover rounded-lg" />
            <span className="text-xs text-purple-300 flex-1 truncate">Image attached for analysis</span>
            <button onClick={() => setAttachedImage(null)} className="p-1 hover:bg-white/10 rounded-lg text-slate-400 hover:text-white cursor-pointer">
              <X className="h-4 w-4" />
            </button>
          </div>
        )}

        <form
          onSubmit={(e) => {
            e.preventDefault();
            handleSend();
          }}
          className="max-w-3xl mx-auto flex items-center gap-2 bg-[var(--theme-bg-sidebar-search)] border border-[var(--theme-border-color)] rounded-2xl px-3 py-1.5 shadow-inner focus-within:border-purple-500/60 transition-all"
        >
          <input
            type="file"
            ref={fileInputRef}
            onChange={handleImageAttachment}
            accept="image/*"
            className="hidden"
          />
          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            className="p-2 rounded-xl text-[var(--theme-text-secondary)] hover:text-purple-300 hover:bg-white/5 transition-colors cursor-pointer"
            title="Attach Image for AI Analysis"
          >
            <Paperclip className="h-4 w-4" />
          </button>

          <input
            ref={inputRef}
            type="text"
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            placeholder="Ask DOLSYX AI, write code, or create images ('generate a cyberpunk car')..."
            className="flex-1 bg-transparent py-1.5 text-sm text-[var(--theme-text-primary)] focus:outline-none placeholder-[var(--theme-text-secondary)]/50"
          />

          <button
            type="submit"
            disabled={(!inputText.trim() && !attachedImage) || isThinking}
            className="p-2 rounded-xl bg-gradient-to-tr from-purple-600 to-indigo-600 text-white disabled:opacity-40 disabled:cursor-not-allowed hover:opacity-95 transition-opacity cursor-pointer shadow-md"
          >
            {isThinking ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Send className="h-4 w-4" />
            )}
          </button>
        </form>
      </div>

      {/* Share to Chat Modal */}
      {shareTargetMsg && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4 animate-fade-in">
          <div className="w-full max-w-md rounded-2xl border border-[var(--theme-border-color)] bg-[#111827] p-5 shadow-2xl text-[var(--theme-text-primary)]">
            <div className="flex items-center justify-between pb-3 border-b border-white/10">
              <div className="flex items-center gap-2">
                <Share2 className="h-5 w-5 text-purple-400" />
                <h3 className="font-bold text-sm">Send to DOLSYX Chat</h3>
              </div>
              <button onClick={() => setShareTargetMsg(null)} className="p-1 rounded-lg hover:bg-white/10 cursor-pointer">
                <X className="h-5 w-5" />
              </button>
            </div>

            {shareSuccess ? (
              <div className="py-8 text-center flex flex-col items-center gap-2">
                <CheckCircle2 className="h-10 w-10 text-emerald-400 animate-bounce" />
                <p className="text-sm font-bold text-emerald-300">Sent to chat successfully!</p>
              </div>
            ) : (
              <div className="mt-4 space-y-2 max-h-64 overflow-y-auto">
                <p className="text-xs text-[var(--theme-text-secondary)] mb-2">Select a chat to share this AI content with:</p>
                {chats.length === 0 ? (
                  <p className="text-xs text-center py-4 text-slate-400">No active conversations found.</p>
                ) : (
                  chats.map((chat) => (
                    <button
                      key={chat.id}
                      disabled={isSharing}
                      onClick={() => handleShareToChat(chat.id)}
                      className="flex w-full items-center gap-3 p-2.5 rounded-xl border border-white/5 hover:border-purple-500/40 hover:bg-white/5 transition-all text-left cursor-pointer group"
                    >
                      <div className="w-9 h-9 rounded-full bg-slate-800 flex items-center justify-center font-bold text-xs text-purple-300">
                        {chat.name?.slice(0, 2).toUpperCase() || "CH"}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-bold truncate group-hover:text-purple-300">{chat.name || "Chat"}</p>
                        <p className="text-[10px] text-slate-400 truncate">{chat.isGroup ? "Group" : "Direct Message"}</p>
                      </div>
                      <ArrowRight className="h-4 w-4 text-slate-400 group-hover:text-purple-300" />
                    </button>
                  ))
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Fullscreen Image Preview Modal */}
      {fullscreenImage && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/90 backdrop-blur-lg p-4"
          onClick={() => setFullscreenImage(null)}
        >
          <button
            onClick={() => setFullscreenImage(null)}
            className="absolute top-6 right-6 p-2 rounded-full bg-white/10 hover:bg-white/20 text-white cursor-pointer"
          >
            <X className="h-6 w-6" />
          </button>
          <img
            src={fullscreenImage}
            alt="Fullscreen AI Art"
            className="max-w-full max-h-[90vh] object-contain rounded-2xl shadow-2xl"
          />
        </div>
      )}
    </div>
  );
}
