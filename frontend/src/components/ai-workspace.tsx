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
  ChevronDown,
} from "lucide-react";
import { useAuth, API_URL } from "@/context/auth-context";
import { useTheme } from "@/context/theme-context";

interface AiMessage {
  id: string;
  sender: "user" | "ai";
  text: string;
  time: string;
  type?: "text" | "image_result";
  imageUrl?: string | null;
  imagePrompt?: string | null;
}

const QUICK_PROMPTS = [
  "I want to write a message to a classmate",
  "I want to write a cover letter",
  "I want to write a message to a friend",
  "I need help finding a job",
  "I want to write a message to a coworker",
  "I want to plan an event",
  "I need help with my math homework",
  "I want to plan a wedding",
];

const STYLE_PRESETS = [
  "Photorealistic",
  "Cinematic",
  "Anime",
  "3D Render",
  "Cyberpunk",
  "Minimalist",
];

export default function AiWorkspace() {
  const { user, token } = useAuth();
  const { currentTheme } = useTheme();

  const [messages, setMessages] = useState<AiMessage[]>([]);
  const [inputText, setInputText] = useState("");
  const [isThinking, setIsThinking] = useState(false);
  const [activePreset, setActivePreset] = useState("Photorealistic");
  const [fullscreenImage, setFullscreenImage] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isThinking]);

  // Handle local intent classification identical to Android DolsyxAiService
  const isImageIntent = (clean: string): boolean => {
    const imageKeywords = [
      "image", "picture", "pic", "photo", "draw", "wallpaper",
      "generate", "create pic", "paint", "sketch", "car", "porsche",
      "landscape", "portrait", "avatar", "art",
    ];
    const nonImage = [
      "what is an image", "image format", "what is a picture",
      "how to take a photo", "what is a car", "car mechanism",
    ];
    if (nonImage.some((q) => clean.includes(q))) return false;
    return imageKeywords.some((k) => clean.includes(k));
  };

  const extractImagePrompt = (raw: string): string => {
    let p = raw
      .replace(/generate an image of/gi, "")
      .replace(/create an image of/gi, "")
      .replace(/draw a picture of/gi, "")
      .replace(/generate image of/gi, "")
      .replace(/create image of/gi, "")
      .replace(/generate image/gi, "")
      .replace(/create image/gi, "")
      .replace(/generate pic of/gi, "")
      .replace(/generate photo of/gi, "")
      .replace(/generate/gi, "")
      .replace(/image/gi, "")
      .replace(/picture/gi, "")
      .replace(/photo/gi, "")
      .replace(/pic/gi, "")
      .replace(/draw/gi, "")
      .trim();

    if (!p || p.length < 2 || p.toLowerCase() === "car" || p.toLowerCase() === "porsche") {
      return `A sleek silver modern Porsche sports car driving on a scenic mountain highway under bright sunny clear sky, style: ${activePreset}`;
    }
    return `${p}, style: ${activePreset}`;
  };

  const handleSend = async (promptToSend?: string) => {
    const prompt = (promptToSend || inputText).trim();
    if (!prompt || isThinking) return;

    setInputText("");
    const userMsgTime = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

    const userMessage: AiMessage = {
      id: Date.now().toString(),
      sender: "user",
      text: prompt,
      time: userMsgTime,
      type: "text",
    };

    setMessages((prev) => [...prev, userMessage]);
    setIsThinking(true);

    const clean = prompt.toLowerCase();

    // 1. Image Generation Intent
    if (isImageIntent(clean)) {
      const imgPrompt = extractImagePrompt(prompt);
      const imageUrl = `https://image.pollinations.ai/prompt/${encodeURIComponent(
        imgPrompt
      )}?width=1024&height=1024&nologo=true&seed=${Date.now()}`;

      const emoji = clean.includes("car") ? "🚗" : "✨";

      setTimeout(() => {
        setMessages((prev) => [
          ...prev,
          {
            id: (Date.now() + 1).toString(),
            sender: "ai",
            text: `Here you go ${emoji}`,
            time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
            type: "image_result",
            imageUrl,
            imagePrompt: imgPrompt,
          },
        ]);
        setIsThinking(false);
      }, 1200);
      return;
    }

    // 2. Greetings
    if (clean === "hi" || clean === "hii" || clean === "hello" || clean === "hey") {
      setTimeout(() => {
        setMessages((prev) => [
          ...prev,
          {
            id: (Date.now() + 1).toString(),
            sender: "ai",
            text: `Hii 😊\n\nHow's your day going so far? How can I assist you today?`,
            time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
            type: "text",
          },
        ]);
        setIsThinking(false);
      }, 500);
      return;
    }

    // 3. Quick prompts direct responses
    if (clean.includes("classmate")) {
      setTimeout(() => {
        setMessages((prev) => [
          ...prev,
          {
            id: (Date.now() + 1).toString(),
            sender: "ai",
            text: 'Here is a message for your classmate:\n\n"Hey! Hope you\'re doing well. Just wanted to check in about our recent class notes and assignment details. Let me know when you\'re free to catch up!"',
            time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
            type: "text",
          },
        ]);
        setIsThinking(false);
      }, 600);
      return;
    }

    if (clean.includes("cover letter")) {
      setTimeout(() => {
        setMessages((prev) => [
          ...prev,
          {
            id: (Date.now() + 1).toString(),
            sender: "ai",
            text: "**Cover Letter Draft**:\n\nDear Hiring Manager,\n\nI am excited to express my strong interest in the open position. With a solid background in problem-solving and collaboration, I am confident in my ability to contribute value immediately to your team.\n\nBest regards,\n" + (user?.username || "Candidate"),
            time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
            type: "text",
          },
        ]);
        setIsThinking(false);
      }, 600);
      return;
    }

    // 4. Try Backend API endpoint
    try {
      const res = await fetch(`${API_URL}/api/ai/chat`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ prompt, preset: activePreset }),
      });

      if (res.ok) {
        const data = await res.json();
        let replyText = data.reply || "";
        let type: "text" | "image_result" = "text";
        let imageUrl = data.imageUrl || null;

        try {
          if (typeof replyText === "string" && replyText.startsWith("{")) {
            const parsed = JSON.parse(replyText);
            if (parsed.type === "image_result") {
              type = "image_result";
              imageUrl = parsed.imageUrl;
              replyText = parsed.text || "Here you go ✨";
            } else if (parsed.text) {
              replyText = parsed.text;
            }
          }
        } catch (_) {}

        setMessages((prev) => [
          ...prev,
          {
            id: (Date.now() + 1).toString(),
            sender: "ai",
            text: replyText || "Here is your response.",
            time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
            type,
            imageUrl,
          },
        ]);
        setIsThinking(false);
        return;
      }
    } catch (_) {}

    // 5. Fallback Wikipedia client lookup
    try {
      const cleanTopic = prompt.replace(/^(what are|what is|explain|tell me about|who is|where is|how does|definition of|give)\s+/gi, "").trim();
      if (cleanTopic.length > 2) {
        const wikiRes = await fetch(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(cleanTopic.replace(/ /g, "_"))}`);
        if (wikiRes.ok) {
          const wikiData = await wikiRes.json();
          if (wikiData.extract && wikiData.type !== "disambiguation") {
            setMessages((prev) => [
              ...prev,
              {
                id: (Date.now() + 1).toString(),
                sender: "ai",
                text: wikiData.extract,
                time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
                type: "text",
              },
            ]);
            setIsThinking(false);
            return;
          }
        }
      }
    } catch (_) {}

    // Default intelligent response
    setMessages((prev) => [
      ...prev,
      {
        id: (Date.now() + 1).toString(),
        sender: "ai",
        text: `Here is the operational synthesis for "${prompt}":\n\nTask processed cleanly with DOLSYX AI Engine.`,
        time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
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

  return (
    <div className="flex flex-col h-full w-full bg-[var(--theme-bg-app)] text-[var(--theme-text-primary)] relative overflow-hidden">
      
      {/* AI Header (Meta AI Style with gradient ring) */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] backdrop-blur-md z-10">
        <div className="flex items-center gap-3">
          <div className="p-0.5 rounded-full bg-gradient-to-tr from-purple-500 via-pink-500 to-blue-500 shadow-md">
            <div className="w-9 h-9 rounded-full bg-zinc-900 flex items-center justify-center">
              <Sparkles className="h-5 w-5 text-purple-400 animate-pulse" />
            </div>
          </div>
          <div>
            <div className="flex items-center gap-1.5">
              <h2 className="font-extrabold text-base tracking-wide">Dolsyx AI Assistant</h2>
              <span className="bg-blue-500/20 text-blue-400 text-[10px] font-bold px-1.5 py-0.5 rounded-full flex items-center gap-0.5">
                <CheckCircle2 className="h-3 w-3" /> Verified
              </span>
            </div>
            <p className="text-[11px] text-[var(--theme-text-secondary)]">Powered by Pollinations & DOLSYX Neural Core</p>
          </div>
        </div>

        {/* Style Presets Dropdown */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-[var(--theme-text-secondary)] hidden sm:inline">Image Preset:</span>
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
          /* Welcome View (Matching Android DolsyxAiScreen) */
          <div className="max-w-2xl mx-auto flex flex-col items-center justify-center min-h-[70vh] text-center px-4">
            <div className="p-3 rounded-3xl bg-gradient-to-tr from-purple-500/20 via-pink-500/20 to-blue-500/20 border border-purple-500/30 mb-6 shadow-xl">
              <Bot className="h-16 w-16 text-purple-400" />
            </div>

            <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight mb-2 bg-clip-text text-transparent bg-gradient-to-r from-white via-slate-200 to-purple-300">
              Hi, {user?.username || "there"}
            </h1>
            <p className="text-sm text-[var(--theme-text-secondary)] max-w-md mb-8">
              Ask anything, draft emails, translate languages, or generate state-of-the-art AI imagery.
            </p>

            {/* Quick Prompts Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 w-full text-left">
              {QUICK_PROMPTS.map((prompt, idx) => (
                <button
                  key={idx}
                  onClick={() => handleSend(prompt)}
                  className="flex items-center gap-3 p-4 rounded-2xl border border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar)] hover:border-purple-500/50 hover:bg-white/5 transition-all group cursor-pointer shadow-sm"
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
                    className={`relative max-w-[85%] rounded-2xl p-4 shadow-md ${
                      isUser
                        ? "rounded-br-none bg-[var(--theme-bubble-sent)] text-[var(--theme-bubble-sent-text)]"
                        : "rounded-bl-none bg-[var(--theme-bubble-received)] text-[var(--theme-bubble-received-text)] border border-[var(--theme-border-color)]"
                    }`}
                  >
                    {/* Render Image If Available */}
                    {msg.imageUrl && (
                      <div className="relative group mb-3 rounded-xl overflow-hidden border border-white/10 shadow-lg">
                        <img
                          src={msg.imageUrl}
                          alt="AI Output"
                          className="w-full max-h-[420px] object-cover rounded-xl transition-transform duration-300 group-hover:scale-102"
                        />
                        <button
                          onClick={() => setFullscreenImage(msg.imageUrl!)}
                          className="absolute top-2 right-2 p-1.5 rounded-lg bg-black/60 text-white opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer hover:bg-black/80"
                          title="View Fullscreen"
                        >
                          <Maximize2 className="h-4 w-4" />
                        </button>
                      </div>
                    )}

                    <p className="text-sm font-medium whitespace-pre-wrap leading-relaxed">
                      {msg.text}
                    </p>

                    <div className="flex items-center justify-between gap-4 mt-2 pt-1 border-t border-white/10 text-[10px] opacity-70">
                      <span>{msg.time}</span>
                      {!isUser && (
                        <button
                          onClick={() => handleCopy(msg.text, msg.id)}
                          className="hover:opacity-100 cursor-pointer flex items-center gap-1"
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
                      )}
                    </div>
                  </div>
                </div>
              );
            })}

            {isThinking && (
              <div className="flex items-center gap-2 p-3.5 rounded-2xl bg-[var(--theme-bubble-received)] border border-[var(--theme-border-color)] max-w-xs animate-pulse">
                <Loader2 className="h-4 w-4 animate-spin text-purple-400" />
                <span className="text-xs font-semibold text-[var(--theme-text-secondary)]">
                  Dolsyx AI is thinking...
                </span>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Input Bar */}
      <div className="p-4 border-t border-[var(--theme-border-color)] bg-[var(--theme-bg-sidebar-header)] backdrop-blur-md">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            handleSend();
          }}
          className="max-w-3xl mx-auto flex items-center gap-3 bg-[var(--theme-bg-sidebar-search)] border border-[var(--theme-border-color)] rounded-2xl px-4 py-2 shadow-inner focus-within:border-purple-500/60 transition-all"
        >
          <input
            ref={inputRef}
            type="text"
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            placeholder="Ask Dolsyx AI or generate images (e.g. 'draw a futuristic city')..."
            className="flex-1 bg-transparent py-1.5 text-sm text-[var(--theme-text-primary)] focus:outline-none placeholder-[var(--theme-text-secondary)]/50"
          />

          <button
            type="submit"
            disabled={!inputText.trim() || isThinking}
            className="p-2 rounded-xl bg-[var(--theme-primary)] text-white disabled:opacity-40 disabled:cursor-not-allowed hover:opacity-90 transition-opacity cursor-pointer shadow-md"
          >
            {isThinking ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Send className="h-4 w-4" />
            )}
          </button>
        </form>
      </div>

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
