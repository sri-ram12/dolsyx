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
  Plus,
  Trash2,
  Edit2,
  ThumbsUp,
  ThumbsDown,
  Volume2,
  VolumeX,
  Mic,
  MicOff,
  Search,
  ChevronLeft,
  ChevronRight,
  Globe,
  Calculator,
  Compass,
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
  model?: string;
  toolName?: string;
  feedback?: "UP" | "DOWN" | null;
}

export interface ConversationItem {
  id: string;
  title: string;
  updatedAt: string;
  lastMessageSnippet?: string;
}

interface AiWorkspaceProps {
  initialPrompt?: string;
  chats?: Chat[];
  onSelectChat?: (chat: Chat) => void;
}

const STYLE_PRESETS = [
  "Photorealistic",
  "Cinematic",
  "Anime",
  "3D Render",
  "Cyberpunk",
  "Minimalist",
];

const CURATED_PROMPTS = [
  { label: "Explain Docker & Kubernetes", icon: "🐳", prompt: "Explain the architectural difference between Docker and Kubernetes simply." },
  { label: "Two Sum Algorithm", icon: "⚡", prompt: "Write an optimal solution for Two Sum with time and space complexity analysis." },
  { label: "Generate Cyberpunk Wallpaper", icon: "🎨", prompt: "Generate an image of a futuristic cyberpunk city with neon reflections in the rain." },
  { label: "Professional Email Follow-Up", icon: "✉️", prompt: "Draft a concise, professional follow-up email to a project stakeholder." },
  { label: "System Design for Chat App", icon: "🏗️", prompt: "Design an end-to-end scalable architecture for a real-time chat application like DOLSYX." },
];

export default function AiWorkspace({ initialPrompt, chats = [], onSelectChat }: AiWorkspaceProps) {
  const { user, token } = useAuth();
  const { currentTheme } = useTheme();

  // Conversation list & active state
  const [conversations, setConversations] = useState<ConversationItem[]>([]);
  const [activeConversationId, setActiveConversationId] = useState<string | null>(null);
  const [convSearchQuery, setConvSearchQuery] = useState("");
  const [showSidebar, setShowSidebar] = useState(true);

  // Chat messages & input
  const [messages, setMessages] = useState<AiMessage[]>([]);
  const [inputText, setInputText] = useState("");
  const [isStreaming, setIsStreaming] = useState(false);
  const [activeToolActivity, setActiveToolActivity] = useState<string | null>(null);
  const [activePreset, setActivePreset] = useState("Photorealistic");

  // Multimodal & Attachments
  const [attachedImage, setAttachedImage] = useState<string | null>(null);
  const [fullscreenImage, setFullscreenImage] = useState<string | null>(null);

  // Message Actions & Modals
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [shareTargetMsg, setShareTargetMsg] = useState<AiMessage | null>(null);
  const [feedbackModalMsgId, setFeedbackModalMsgId] = useState<string | null>(null);
  const [feedbackType, setFeedbackType] = useState<"UP" | "DOWN">("UP");
  const [feedbackComment, setFeedbackComment] = useState("");

  // Voice Input (STT) & Speech Synthesis (TTS)
  const [isListening, setIsListening] = useState(false);
  const [speakingMsgId, setSpeakingMsgId] = useState<string | null>(null);

  // Renaming state
  const [editingConvId, setEditingConvId] = useState<string | null>(null);
  const [editConvTitle, setEditConvTitle] = useState("");

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const abortControllerRef = useRef<AbortController | null>(null);
  const recognitionRef = useRef<any>(null);
  const initialSentRef = useRef(false);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isStreaming, activeToolActivity]);

  // Load conversations on mount
  useEffect(() => {
    fetchConversations();
  }, [token]);

  // Trigger initial prompt if passed
  useEffect(() => {
    if (initialPrompt && initialPrompt.trim() && !initialSentRef.current) {
      initialSentRef.current = true;
      handleSendMessage(initialPrompt.trim());
    }
  }, [initialPrompt]);

  const fetchConversations = async () => {
    if (!token) return;
    try {
      const res = await fetch(`${API_URL}/api/ai/conversations`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setConversations(data.conversations || []);
      }
    } catch (_) {}
  };

  const loadConversationMessages = async (convId: string) => {
    if (!token) return;
    setActiveConversationId(convId);
    try {
      const res = await fetch(`${API_URL}/api/ai/conversations/${convId}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        const conv = data.conversation;
        if (conv?.messages) {
          const formatted: AiMessage[] = conv.messages.map((m: any) => ({
            id: m.id,
            sender: m.sender === "USER" ? "user" : "ai",
            text: m.content,
            time: new Date(m.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
            type: m.type === "AI_IMAGE" ? "image_result" : "text",
            model: m.model,
            feedback: m.feedback,
          }));
          setMessages(formatted);
        }
      }
    } catch (_) {}
  };

  const handleCreateNewConversation = () => {
    setActiveConversationId(null);
    setMessages([]);
    setInputText("");
    setAttachedImage(null);
  };

  const handleDeleteConversation = async (convId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!token) return;
    try {
      await fetch(`${API_URL}/api/ai/conversations/${convId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      setConversations(prev => prev.filter(c => c.id !== convId));
      if (activeConversationId === convId) {
        handleCreateNewConversation();
      }
    } catch (_) {}
  };

  const handleSaveRename = async (convId: string, e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !editConvTitle.trim()) return;
    try {
      await fetch(`${API_URL}/api/ai/conversations/${convId}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ title: editConvTitle.trim() }),
      });
      setConversations(prev =>
        prev.map(c => (c.id === convId ? { ...c, title: editConvTitle.trim() } : c))
      );
      setEditingConvId(null);
    } catch (_) {}
  };

  // ─────────────────────────────────────────────────────────────────────────
  // SEND MESSAGE & STREAMING
  // ─────────────────────────────────────────────────────────────────────────

  const handleSendMessage = async (promptOverride?: string) => {
    const prompt = (promptOverride || inputText).trim();
    if (!prompt && !attachedImage) return;
    if (isStreaming) return;

    const currentAttached = attachedImage;
    setAttachedImage(null);
    setInputText("");

    const userMsgId = Date.now().toString();
    const userTime = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

    const userMessage: AiMessage = {
      id: userMsgId,
      sender: "user",
      text: prompt || "Analyze this image",
      time: userTime,
      attachedImage: currentAttached,
    };

    setMessages(prev => [...prev, userMessage]);
    setIsStreaming(true);
    setActiveToolActivity(null);

    const aiMsgId = (Date.now() + 1).toString();
    const aiTime = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

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
          setMessages(prev => [
            ...prev,
            {
              id: aiMsgId,
              sender: "ai",
              text: data.reply || "Image analysis completed.",
              time: aiTime,
              type: "text",
              model: data.model,
            },
          ]);
          setIsStreaming(false);
          return;
        }
      } catch (e) {
        console.error("Multimodal error:", e);
      }
    }

    // Check for Image Generation intent
    const isImageGen = /\b(generate|create|draw|make)\s+(an?\s+)?(image|photo|picture|pic|avatar|wallpaper|logo|banner)\b/i.test(prompt);
    if (isImageGen) {
      setActiveToolActivity("Generating image via Cloudinary CDN pipeline... 🎨");
      try {
        const res = await fetch(`${API_URL}/api/ai/generate-image`, {
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
          setMessages(prev => [
            ...prev,
            {
              id: aiMsgId,
              sender: "ai",
              text: data.text || "Here is your generated image ✨",
              time: aiTime,
              type: "image_result",
              imageUrl: data.imageUrl,
              imagePrompt: prompt,
            },
          ]);
          setIsStreaming(false);
          setActiveToolActivity(null);
          fetchConversations();
          return;
        }
      } catch (_) {}
    }

    // Real SSE Token-by-Token Streaming
    const controller = new AbortController();
    abortControllerRef.current = controller;

    // Placeholder message for progressive streaming
    setMessages(prev => [
      ...prev,
      {
        id: aiMsgId,
        sender: "ai",
        text: "",
        time: aiTime,
        type: "text",
      },
    ]);

    try {
      const response = await fetch(`${API_URL}/api/ai/stream`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({
          prompt,
          conversationId: activeConversationId || undefined,
        }),
        signal: controller.signal,
      });

      if (!response.ok || !response.body) {
        throw new Error("Stream connection failed");
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let accumulatedText = "";

      while (true) {
        const { value, done } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || !trimmed.startsWith("data:")) continue;
          const dataStr = trimmed.replace(/^data:\s*/, "");
          if (dataStr === "[DONE]") {
            break;
          }

          try {
            const parsed = JSON.parse(dataStr);
            if (parsed.token) {
              accumulatedText += parsed.token;
              setMessages(prev =>
                prev.map(m => (m.id === aiMsgId ? { ...m, text: accumulatedText } : m))
              );
            } else if (parsed.toolCall) {
              setActiveToolActivity(`Running tool: ${parsed.toolCall.name}... ⚡`);
            } else if (parsed.complete) {
              if (parsed.metadata?.conversationId && !activeConversationId) {
                setActiveConversationId(parsed.metadata.conversationId);
              }
            }
          } catch (_) {}
        }
      }

      setIsStreaming(false);
      setActiveToolActivity(null);
      fetchConversations();
    } catch (err: any) {
      if (err.name === "AbortError") {
        console.log("Stream aborted by user");
      } else {
        // Fallback to standard chat endpoint if SSE streaming is interrupted
        try {
          const fallbackRes = await fetch(`${API_URL}/api/ai/chat`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              ...(token ? { Authorization: `Bearer ${token}` } : {}),
            },
            body: JSON.stringify({
              prompt,
              conversationId: activeConversationId || undefined,
            }),
          });
          if (fallbackRes.ok) {
            const fbData = await fallbackRes.json();
            setMessages(prev =>
              prev.map(m => (m.id === aiMsgId ? { ...m, text: fbData.reply || "Done." } : m))
            );
            setIsStreaming(false);
            setActiveToolActivity(null);
            fetchConversations();
            return;
          }
        } catch (_) {}

        setMessages(prev =>
          prev.map(m =>
            m.id === aiMsgId
              ? { ...m, text: "DOLSYX AI encountered a network interruption. Please retry." }
              : m
          )
        );
      }
      setIsStreaming(false);
      setActiveToolActivity(null);
    }
  };

  const handleStopStreaming = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    setIsStreaming(false);
    setActiveToolActivity(null);
  };

  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  // ─────────────────────────────────────────────────────────────────────────
  // VOICE INPUT (STT) & SPEECH SYNTHESIS (TTS)
  // ─────────────────────────────────────────────────────────────────────────

  const toggleVoiceInput = () => {
    if (isListening) {
      recognitionRef.current?.stop();
      setIsListening(false);
      return;
    }

    const SpeechRec = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SpeechRec) {
      alert("Speech recognition is not supported in this browser. Please use Chrome or Edge.");
      return;
    }

    try {
      const recognition = new SpeechRec();
      recognition.continuous = false;
      recognition.interimResults = true;
      recognition.lang = "en-US";

      recognition.onstart = () => setIsListening(true);
      recognition.onresult = (event: any) => {
        const transcript = Array.from(event.results)
          .map((res: any) => res[0].transcript)
          .join("");
        setInputText(transcript);
      };
      recognition.onerror = () => setIsListening(false);
      recognition.onend = () => setIsListening(false);

      recognition.start();
      recognitionRef.current = recognition;
    } catch (err) {
      console.warn("Speech recognition error:", err);
      setIsListening(false);
    }
  };

  const toggleTextToSpeech = (msgId: string, text: string) => {
    if (typeof window === "undefined" || !("speechSynthesis" in window)) {
      alert("Text-to-speech is not supported in this browser.");
      return;
    }

    if (speakingMsgId === msgId) {
      window.speechSynthesis.cancel();
      setSpeakingMsgId(null);
      return;
    }

    window.speechSynthesis.cancel();
    const cleanText = text.replace(/```[\s\S]*?```/g, "Code block omitted.").replace(/[#*`_~]/g, "");
    const utterance = new SpeechSynthesisUtterance(cleanText);
    utterance.rate = 1.0;
    utterance.onend = () => setSpeakingMsgId(null);
    utterance.onerror = () => setSpeakingMsgId(null);

    setSpeakingMsgId(msgId);
    window.speechSynthesis.speak(utterance);
  };

  // ─────────────────────────────────────────────────────────────────────────
  // FEEDBACK SUBMISSION
  // ─────────────────────────────────────────────────────────────────────────

  const submitFeedback = async () => {
    if (!feedbackModalMsgId) return;
    try {
      await fetch(`${API_URL}/api/ai/feedback`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({
          messageId: feedbackModalMsgId,
          feedback: feedbackType,
          comment: feedbackComment.trim() || undefined,
        }),
      });

      setMessages(prev =>
        prev.map(m => (m.id === feedbackModalMsgId ? { ...m, feedback: feedbackType } : m))
      );
    } catch (_) {}

    setFeedbackModalMsgId(null);
    setFeedbackComment("");
  };

  // ─────────────────────────────────────────────────────────────────────────
  // SHARE TO CHAT
  // ─────────────────────────────────────────────────────────────────────────

  const handleShareToChat = (chat: Chat) => {
    if (!shareTargetMsg) return;
    if (onSelectChat) {
      onSelectChat(chat);
    }
    setShareTargetMsg(null);
  };

  // ─────────────────────────────────────────────────────────────────────────
  // MARKDOWN CODE BLOCK RENDERING
  // ─────────────────────────────────────────────────────────────────────────

  const renderFormattedContent = (content: string) => {
    const parts = content.split(/(```[\s\S]*?```)/g);

    return parts.map((part, index) => {
      if (part.startsWith("```") && part.endsWith("```")) {
        const firstLineEnd = part.indexOf("\n");
        const language = part.slice(3, firstLineEnd).trim() || "code";
        const codeContent = part.slice(firstLineEnd + 1, -3);

        return (
          <div key={index} className="my-3 rounded-xl overflow-hidden border border-[var(--theme-border-color)] bg-[#0d1117] text-gray-100 shadow-md">
            <div className="flex items-center justify-between px-4 py-1.5 bg-[#161b22] border-b border-gray-800 text-xs text-gray-400 font-mono">
              <span className="flex items-center gap-1.5">
                <Code className="w-3.5 h-3.5 text-[var(--theme-accent)]" />
                {language}
              </span>
              <button
                onClick={() => handleCopy(codeContent, `code-${index}`)}
                className="flex items-center gap-1 hover:text-white transition-colors cursor-pointer px-2 py-0.5 rounded bg-gray-800/60"
              >
                {copiedId === `code-${index}` ? (
                  <>
                    <Check className="w-3.5 h-3.5 text-emerald-400" />
                    <span>Copied!</span>
                  </>
                ) : (
                  <>
                    <Copy className="w-3.5 h-3.5" />
                    <span>Copy</span>
                  </>
                )}
              </button>
            </div>
            <pre className="p-4 overflow-x-auto text-sm font-mono leading-relaxed text-gray-200">
              <code>{codeContent}</code>
            </pre>
          </div>
        );
      }

      // Format bold, inline code, and paragraphs
      return (
        <div key={index} className="whitespace-pre-wrap leading-relaxed">
          {part}
        </div>
      );
    });
  };

  const filteredConversations = conversations.filter(c =>
    c.title.toLowerCase().includes(convSearchQuery.toLowerCase())
  );

  return (
    <div className="flex h-full w-full overflow-hidden bg-[var(--theme-bg-container)] text-[var(--theme-text-primary)]">
      {/* ── CONVERSATION HISTORY SIDEBAR ─────────────────────────────────── */}
      <div
        className={`${
          showSidebar ? "w-72" : "w-0"
        } transition-all duration-300 ease-in-out shrink-0 border-r border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] flex flex-col h-full overflow-hidden relative`}
      >
        {/* Sidebar Header */}
        <div className="p-3 border-b border-[var(--theme-border-color)] flex items-center justify-between gap-2">
          <button
            onClick={handleCreateNewConversation}
            className="flex-1 flex items-center justify-center gap-2 px-3 py-2 rounded-xl bg-[var(--theme-accent)] hover:opacity-90 text-white font-medium text-sm transition-all shadow-sm cursor-pointer"
          >
            <Plus className="w-4 h-4" />
            <span>New Chat</span>
          </button>
          <button
            onClick={() => setShowSidebar(false)}
            className="p-2 rounded-lg hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] transition-colors cursor-pointer"
            title="Collapse Sidebar"
          >
            <ChevronLeft className="w-4 h-4" />
          </button>
        </div>

        {/* Search Conversations */}
        <div className="px-3 py-2">
          <div className="flex items-center gap-2 px-2.5 py-1.5 rounded-lg bg-[var(--theme-bg-input)] border border-[var(--theme-border-color)] text-xs">
            <Search className="w-3.5 h-3.5 text-[var(--theme-text-secondary)]" />
            <input
              type="text"
              placeholder="Search chats..."
              value={convSearchQuery}
              onChange={e => setConvSearchQuery(e.target.value)}
              className="w-full bg-transparent outline-none text-[var(--theme-text-primary)] placeholder:text-[var(--theme-text-secondary)]"
            />
          </div>
        </div>

        {/* Conversation List */}
        <div className="flex-1 overflow-y-auto px-2 py-1 space-y-1">
          {filteredConversations.length === 0 ? (
            <div className="text-center py-8 text-xs text-[var(--theme-text-secondary)]">
              No conversations found.
            </div>
          ) : (
            filteredConversations.map(c => {
              const isActive = c.id === activeConversationId;
              const isEditing = editingConvId === c.id;

              return (
                <div
                  key={c.id}
                  onClick={() => loadConversationMessages(c.id)}
                  className={`group flex items-center justify-between px-3 py-2.5 rounded-xl cursor-pointer text-xs transition-all ${
                    isActive
                      ? "bg-[var(--theme-accent)]/15 text-[var(--theme-accent)] font-medium border border-[var(--theme-accent)]/30"
                      : "hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-primary)]"
                  }`}
                >
                  {isEditing ? (
                    <form onSubmit={e => handleSaveRename(c.id, e)} className="flex-1 mr-2">
                      <input
                        type="text"
                        autoFocus
                        value={editConvTitle}
                        onChange={e => setEditConvTitle(e.target.value)}
                        onBlur={() => setEditingConvId(null)}
                        className="w-full px-2 py-1 rounded bg-[var(--theme-bg-input)] border border-[var(--theme-accent)] text-xs outline-none"
                      />
                    </form>
                  ) : (
                    <div className="flex items-center gap-2 truncate flex-1 mr-2">
                      <MessageSquare className="w-3.5 h-3.5 shrink-0 text-[var(--theme-text-secondary)]" />
                      <span className="truncate">{c.title}</span>
                    </div>
                  )}

                  <div className="hidden group-hover:flex items-center gap-1 shrink-0">
                    <button
                      onClick={e => {
                        e.stopPropagation();
                        setEditingConvId(c.id);
                        setEditConvTitle(c.title);
                      }}
                      className="p-1 rounded hover:bg-black/20 text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
                      title="Rename"
                    >
                      <Edit2 className="w-3 h-3" />
                    </button>
                    <button
                      onClick={e => handleDeleteConversation(c.id, e)}
                      className="p-1 rounded hover:bg-red-500/20 text-[var(--theme-text-secondary)] hover:text-red-400"
                      title="Delete"
                    >
                      <Trash2 className="w-3 h-3" />
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>
      </div>

      {/* ── MAIN CHAT WORKSPACE ────────────────────────────────────────── */}
      <div className="flex-1 flex flex-col h-full overflow-hidden relative">
        {/* Workspace Top Bar */}
        <div className="h-14 px-4 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-header)] flex items-center justify-between shrink-0">
          <div className="flex items-center gap-3">
            {!showSidebar && (
              <button
                onClick={() => setShowSidebar(true)}
                className="p-2 rounded-lg hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] cursor-pointer"
                title="Open Conversations"
              >
                <ChevronRight className="w-5 h-5" />
              </button>
            )}

            <div className="flex items-center gap-2.5">
              <div className="p-2 rounded-xl bg-gradient-to-tr from-violet-600 to-fuchsia-600 text-white shadow-md">
                <Sparkles className="w-4 h-4" />
              </div>
              <div>
                <h1 className="font-semibold text-sm leading-tight flex items-center gap-2">
                  <span>DOLSYX AI</span>
                  <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-[var(--theme-accent)]/20 text-[var(--theme-accent)] uppercase tracking-wider">
                    v2.0
                  </span>
                </h1>
                <p className="text-[11px] text-[var(--theme-text-secondary)]">
                  {isStreaming ? "Streaming response..." : "Native Cognitive Intelligence"}
                </p>
              </div>
            </div>
          </div>

          {/* Style Preset Selector */}
          <div className="hidden sm:flex items-center gap-1.5 bg-[var(--theme-bg-input)] px-2 py-1 rounded-lg border border-[var(--theme-border-color)]">
            <span className="text-[11px] text-[var(--theme-text-secondary)] font-medium">Style:</span>
            <select
              value={activePreset}
              onChange={e => setActivePreset(e.target.value)}
              className="bg-transparent text-xs font-semibold text-[var(--theme-accent)] outline-none cursor-pointer"
            >
              {STYLE_PRESETS.map(preset => (
                <option key={preset} value={preset} className="bg-[var(--theme-bg-container)] text-[var(--theme-text-primary)]">
                  {preset}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Messages Scroll Area */}
        <div className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
          {messages.length === 0 ? (
            /* Empty State: Curated Prompts & Introduction */
            <div className="max-w-2xl mx-auto my-auto py-12 flex flex-col items-center text-center">
              <div className="w-16 h-16 rounded-2xl bg-gradient-to-tr from-indigo-500 via-purple-500 to-pink-500 flex items-center justify-center text-white shadow-xl mb-4">
                <Bot className="w-8 h-8" />
              </div>
              <h2 className="text-xl font-bold mb-1.5">How can DOLSYX AI help you today?</h2>
              <p className="text-xs text-[var(--theme-text-secondary)] max-w-md mb-8">
                Your intelligent copilot for conversations, engineering, research, image generation, and chat workflows.
              </p>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 w-full text-left">
                {CURATED_PROMPTS.map((item, idx) => (
                  <button
                    key={idx}
                    onClick={() => handleSendMessage(item.prompt)}
                    className="flex items-start gap-3 p-3.5 rounded-xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] hover:bg-[var(--theme-bg-sidebar-item-hover)] hover:border-[var(--theme-accent)] transition-all cursor-pointer group shadow-sm"
                  >
                    <span className="text-xl shrink-0">{item.icon}</span>
                    <div className="flex-1">
                      <div className="text-xs font-semibold group-hover:text-[var(--theme-accent)] transition-colors">
                        {item.label}
                      </div>
                      <div className="text-[11px] text-[var(--theme-text-secondary)] line-clamp-1 mt-0.5">
                        {item.prompt}
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          ) : (
            /* Chat Messages */
            messages.map(msg => {
              const isUser = msg.sender === "user";

              return (
                <div key={msg.id} className={`flex flex-col ${isUser ? "items-end" : "items-start"}`}>
                  <div
                    className={`max-w-[85%] sm:max-w-[75%] rounded-2xl p-4 shadow-sm relative group ${
                      isUser
                        ? "bg-[var(--theme-accent)] text-white rounded-tr-xs"
                        : "bg-[var(--theme-bg-sidebar)] border border-[var(--theme-border-color)] text-[var(--theme-text-primary)] rounded-tl-xs"
                    }`}
                  >
                    {/* User Attached Image */}
                    {msg.attachedImage && (
                      <div className="mb-3 rounded-xl overflow-hidden max-h-60 border border-white/20">
                        <img src={msg.attachedImage} alt="User upload" className="w-full h-auto object-cover" />
                      </div>
                    )}

                    {/* Image Result */}
                    {msg.type === "image_result" && msg.imageUrl ? (
                      <div className="space-y-2.5">
                        <div
                          onClick={() => setFullscreenImage(msg.imageUrl!)}
                          className="relative rounded-xl overflow-hidden cursor-pointer group/img max-w-md border border-[var(--theme-border-color)] shadow-lg"
                        >
                          <img src={msg.imageUrl} alt={msg.imagePrompt || "AI Image"} className="w-full h-auto object-cover transition-transform duration-300 group-hover/img:scale-[1.02]" />
                          <div className="absolute inset-0 bg-black/40 opacity-0 group-hover/img:opacity-100 transition-opacity flex items-center justify-center gap-3">
                            <span className="p-2 rounded-full bg-white/20 backdrop-blur-md text-white hover:bg-white/30">
                              <Maximize2 className="w-5 h-5" />
                            </span>
                          </div>
                        </div>
                        {msg.text && <p className="text-xs font-medium">{msg.text}</p>}
                      </div>
                    ) : (
                      /* Text Content */
                      <div className="text-xs sm:text-sm">
                        {renderFormattedContent(msg.text)}
                      </div>
                    )}

                    {/* Message Footer & Action Buttons */}
                    <div className="flex items-center justify-between mt-2.5 pt-2 border-t border-black/10 dark:border-white/10 text-[10px] opacity-75">
                      <span>{msg.time}</span>

                      {!isUser && (
                        <div className="flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
                          {/* Text-to-Speech Playback */}
                          <button
                            onClick={() => toggleTextToSpeech(msg.id, msg.text)}
                            className="p-1 rounded hover:bg-black/10 dark:hover:bg-white/10"
                            title="Read Aloud"
                          >
                            {speakingMsgId === msg.id ? (
                              <VolumeX className="w-3.5 h-3.5 text-[var(--theme-accent)]" />
                            ) : (
                              <Volume2 className="w-3.5 h-3.5" />
                            )}
                          </button>

                          {/* Copy */}
                          <button
                            onClick={() => handleCopy(msg.text, msg.id)}
                            className="p-1 rounded hover:bg-black/10 dark:hover:bg-white/10"
                            title="Copy message"
                          >
                            {copiedId === msg.id ? (
                              <Check className="w-3.5 h-3.5 text-emerald-400" />
                            ) : (
                              <Copy className="w-3.5 h-3.5" />
                            )}
                          </button>

                          {/* Share to Chat */}
                          <button
                            onClick={() => setShareTargetMsg(msg)}
                            className="p-1 rounded hover:bg-black/10 dark:hover:bg-white/10"
                            title="Share to chat"
                          >
                            <Share2 className="w-3.5 h-3.5" />
                          </button>

                          {/* Feedback */}
                          <button
                            onClick={() => {
                              setFeedbackModalMsgId(msg.id);
                              setFeedbackType("UP");
                            }}
                            className={`p-1 rounded hover:bg-black/10 dark:hover:bg-white/10 ${
                              msg.feedback === "UP" ? "text-emerald-400" : ""
                            }`}
                            title="Helpful"
                          >
                            <ThumbsUp className="w-3.5 h-3.5" />
                          </button>
                          <button
                            onClick={() => {
                              setFeedbackModalMsgId(msg.id);
                              setFeedbackType("DOWN");
                            }}
                            className={`p-1 rounded hover:bg-black/10 dark:hover:bg-white/10 ${
                              msg.feedback === "DOWN" ? "text-rose-400" : ""
                            }`}
                            title="Not helpful"
                          >
                            <ThumbsDown className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              );
            })
          )}

          {/* Tool activity banner */}
          {activeToolActivity && (
            <div className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-[var(--theme-accent)]/10 border border-[var(--theme-accent)]/30 text-xs text-[var(--theme-accent)] font-medium max-w-fit animate-pulse">
              <Compass className="w-3.5 h-3.5 animate-spin" />
              <span>{activeToolActivity}</span>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* Attached preview */}
        {attachedImage && (
          <div className="px-4 py-2 bg-[var(--theme-bg-sidebar)] border-t border-[var(--theme-border-color)] flex items-center gap-3">
            <div className="relative w-12 h-12 rounded-lg overflow-hidden border border-[var(--theme-border-color)]">
              <img src={attachedImage} alt="Attachment" className="w-full h-full object-cover" />
              <button
                onClick={() => setAttachedImage(null)}
                className="absolute top-0.5 right-0.5 p-0.5 rounded-full bg-black/60 text-white"
              >
                <X className="w-3 h-3" />
              </button>
            </div>
            <span className="text-xs text-[var(--theme-text-secondary)]">Image attached. Ask AI to analyze it.</span>
          </div>
        )}

        {/* Input Bar */}
        <div className="p-3 sm:p-4 border-t border-[var(--theme-border-color)] bg-[var(--theme-bg-header)] shrink-0">
          <div className="max-w-4xl mx-auto flex items-center gap-2">
            {/* Attachment Button */}
            <input
              type="file"
              ref={fileInputRef}
              onChange={e => {
                const file = e.target.files?.[0];
                if (!file) return;
                const reader = new FileReader();
                reader.onload = () => setAttachedImage(reader.result as string);
                reader.readAsDataURL(file);
                e.target.value = "";
              }}
              accept="image/*"
              className="hidden"
            />
            <button
              onClick={() => fileInputRef.current?.click()}
              className="p-2.5 rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)] transition-colors cursor-pointer shrink-0"
              title="Attach Image"
            >
              <Paperclip className="w-5 h-5" />
            </button>

            {/* Voice Input Button */}
            <button
              onClick={toggleVoiceInput}
              className={`p-2.5 rounded-xl transition-colors cursor-pointer shrink-0 ${
                isListening
                  ? "bg-rose-500/20 text-rose-500 animate-pulse"
                  : "hover:bg-[var(--theme-bg-sidebar-item-hover)] text-[var(--theme-text-secondary)] hover:text-[var(--theme-text-primary)]"
              }`}
              title={isListening ? "Stop Listening" : "Voice Input"}
            >
              {isListening ? <MicOff className="w-5 h-5" /> : <Mic className="w-5 h-5" />}
            </button>

            {/* Main Text Input */}
            <div className="flex-1 relative flex items-center">
              <input
                ref={inputRef}
                type="text"
                value={inputText}
                onChange={e => setInputText(e.target.value)}
                onKeyDown={e => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    handleSendMessage();
                  }
                }}
                placeholder={isListening ? "Listening..." : "Ask DOLSYX AI anything, or request image generation..."}
                disabled={isStreaming}
                className="w-full py-2.5 pl-4 pr-10 rounded-xl bg-[var(--theme-bg-input)] border border-[var(--theme-border-color)] text-xs sm:text-sm text-[var(--theme-text-primary)] placeholder:text-[var(--theme-text-secondary)] outline-none focus:border-[var(--theme-accent)] transition-colors"
              />
            </div>

            {/* Send / Stop Button */}
            {isStreaming ? (
              <button
                onClick={handleStopStreaming}
                className="px-3.5 py-2.5 rounded-xl bg-rose-600 hover:bg-rose-700 text-white text-xs font-semibold flex items-center gap-1.5 cursor-pointer shadow-md transition-all"
              >
                <X className="w-4 h-4" />
                <span>Stop</span>
              </button>
            ) : (
              <button
                onClick={() => handleSendMessage()}
                disabled={!inputText.trim() && !attachedImage}
                className="p-2.5 rounded-xl bg-[var(--theme-accent)] hover:opacity-90 disabled:opacity-40 text-white cursor-pointer transition-all shadow-md shrink-0"
              >
                <Send className="w-5 h-5" />
              </button>
            )}
          </div>
        </div>
      </div>

      {/* ── FULLSCREEN IMAGE MODAL ─────────────────────────────────────── */}
      {fullscreenImage && (
        <div className="fixed inset-0 z-50 bg-black/90 flex flex-col items-center justify-center p-4 backdrop-blur-md">
          <div className="absolute top-4 right-4 flex items-center gap-2">
            <a
              href={fullscreenImage}
              download="dolsyx-ai-image.png"
              target="_blank"
              rel="noreferrer"
              className="p-2 rounded-xl bg-white/10 hover:bg-white/20 text-white transition-colors"
              title="Download Image"
            >
              <Download className="w-5 h-5" />
            </a>
            <button
              onClick={() => setFullscreenImage(null)}
              className="p-2 rounded-xl bg-white/10 hover:bg-white/20 text-white transition-colors"
              title="Close"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
          <img src={fullscreenImage} alt="Fullscreen View" className="max-h-[85vh] max-w-[90vw] object-contain rounded-xl shadow-2xl" />
        </div>
      )}

      {/* ── SHARE TO CHAT MODAL ─────────────────────────────────────────── */}
      {shareTargetMsg && (
        <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-2xl bg-[var(--theme-bg-container)] border border-[var(--theme-border-color)] p-5 shadow-2xl">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-sm">Send to DOLSYX Chat</h3>
              <button onClick={() => setShareTargetMsg(null)} className="p-1 text-[var(--theme-text-secondary)]">
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="max-h-60 overflow-y-auto space-y-1 mb-4">
              {chats.length === 0 ? (
                <div className="text-center py-6 text-xs text-[var(--theme-text-secondary)]">
                  No active chats available.
                </div>
              ) : (
                chats.map(c => (
                  <button
                    key={c.id}
                    onClick={() => handleShareToChat(c)}
                    className="w-full flex items-center gap-3 p-2.5 rounded-xl hover:bg-[var(--theme-bg-sidebar-item-hover)] text-left cursor-pointer transition-colors"
                  >
                    <div className="w-8 h-8 rounded-full bg-[var(--theme-accent)]/20 text-[var(--theme-accent)] flex items-center justify-center font-bold text-xs shrink-0">
                      {c.name?.slice(0, 1) || "C"}
                    </div>
                    <div className="truncate flex-1">
                      <div className="text-xs font-semibold truncate">{c.name}</div>
                      <div className="text-[10px] text-[var(--theme-text-secondary)]">{c.isGroup ? "Group" : "Direct"}</div>
                    </div>
                  </button>
                ))
              )}
            </div>
          </div>
        </div>
      )}

      {/* ── FEEDBACK MODAL ─────────────────────────────────────────────── */}
      {feedbackModalMsgId && (
        <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-2xl bg-[var(--theme-bg-container)] border border-[var(--theme-border-color)] p-5 shadow-2xl">
            <h3 className="font-semibold text-sm mb-2">Provide Feedback</h3>
            <p className="text-xs text-[var(--theme-text-secondary)] mb-4">
              Help us improve DOLSYX AI responses with your input.
            </p>

            <textarea
              value={feedbackComment}
              onChange={e => setFeedbackComment(e.target.value)}
              placeholder="Optional notes or reason..."
              rows={3}
              className="w-full p-2.5 rounded-xl bg-[var(--theme-bg-input)] border border-[var(--theme-border-color)] text-xs outline-none focus:border-[var(--theme-accent)] mb-4 resize-none"
            />

            <div className="flex items-center justify-end gap-2">
              <button
                onClick={() => setFeedbackModalMsgId(null)}
                className="px-3 py-1.5 rounded-xl text-xs text-[var(--theme-text-secondary)] hover:bg-black/10"
              >
                Cancel
              </button>
              <button
                onClick={submitFeedback}
                className="px-4 py-1.5 rounded-xl bg-[var(--theme-accent)] text-white text-xs font-semibold shadow"
              >
                Submit
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
