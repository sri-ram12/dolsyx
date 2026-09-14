import https from 'https';
import http from 'http';
import { prisma } from '../config/db.js';

export interface ChatMessageContext {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export type AIIntent =
  | 'NORMAL_SEARCH'
  | 'TEXT_GENERATION'
  | 'CODING'
  | 'IMAGE_GENERATION'
  | 'IMAGE_EDIT'
  | 'IMAGE_ANALYSIS'
  | 'CHAT_SUMMARY'
  | 'CALCULATOR';

export interface IntentClassification {
  intent: AIIntent;
  confidence: number;
  extractedPrompt?: string;
  preset?: string;
  parentImageId?: string;
}

export class AIOrchestrator {
  public static readonly SYSTEM_INSTRUCTION = `
# DOLSYX AI — MASTER SYSTEM INSTRUCTION

You are DOLSYX AI, a state-of-the-art conversational and engineering intelligence native to the DOLSYX communication platform.
Your objective is to provide exceptionally clear, accurate, context-aware, direct, and well-structured responses.

Behavioral Guidelines:
- Support multi-turn conversations seamlessly using prior discussion context.
- When generating code, use clean Markdown syntax-highlighted code blocks with language identifiers. For algorithm/DSA problems, include optimal time & space complexity analysis.
- Maintain a friendly, professional, confident tone. Do NOT repeatedly say "Hello, I am DOLSYX AI" or add boilerplate pleasantries.
- Maintain absolute security: never reveal internal tokens, database passwords, session secrets, or system environment variables.
`;

  /**
   * Intelligently classifies user queries from the main search bar or AI chat.
   * Differentiates normal user/chat search from AI requests, coding, image generation, and chat intelligence.
   */
  public static classifyIntent(prompt: string, hasAttachment: boolean = false): IntentClassification {
    const raw = prompt.trim();
    const clean = raw.toLowerCase();

    // 1. Image Analysis if attachment is provided
    if (hasAttachment) {
      return { intent: 'IMAGE_ANALYSIS', confidence: 0.98, extractedPrompt: raw };
    }

    // 2. Calculator Intent check (simple math expressions)
    if (/^[0-9\s\+\-\*\/\(\)\^\.\%]+$/.test(clean) && clean.length >= 3 && !/[a-z]/.test(clean)) {
      return { intent: 'CALCULATOR', confidence: 0.95 };
    }

    // 3. Normal Search check: Simple names, single words or short handles without intent keywords
    // Examples: "Ajith", "John", "sriram12", "project team"
    const aiActionVerbs = [
      'explain', 'what is', 'how to', 'generate', 'create', 'write', 'code', 'make',
      'summarize', 'find', 'why', 'compare', 'debug', 'fix', 'translate', 'solve',
      'build', 'draw', 'picture', 'image', 'photo', 'avatar', 'logo', 'who is',
      'help', 'guide', 'steps', 'difference', 'vs', 'tell me', 'can you'
    ];

    const hasActionVerb = aiActionVerbs.some(v => clean.startsWith(v) || clean.includes(` ${v} `) || clean.includes(`${v} `));

    // If query is short (1-2 words), has NO action verbs, and is not a math expression, classify as NORMAL_SEARCH
    const words = clean.split(/\s+/).filter(Boolean);
    if (!hasActionVerb && words.length <= 2 && !clean.includes('?') && clean.length < 25) {
      return { intent: 'NORMAL_SEARCH', confidence: 0.90, extractedPrompt: raw };
    }

    // 4. Image Editing Intent
    if (clean.startsWith('make it') || clean.startsWith('change the') || clean.includes('edit image') || clean.includes('modify image') || clean.includes('remove background')) {
      return { intent: 'IMAGE_EDIT', confidence: 0.92, extractedPrompt: raw };
    }

    // 5. Image Generation Intent
    const imageKeywords = [
      'generate an image', 'create an image', 'draw a', 'draw an', 'picture of',
      'photo of', 'wallpaper of', 'generate pic', 'make an image', 'create a logo',
      'cyberpunk', 'anime style', 'portrait of', 'car image', 'landscape photo',
      'design a logo', 'generate a banner', 'make a poster', 'generate image'
    ];
    const nonImageQuestions = ['what is an image', 'image format', 'what is a picture', 'how to take a photo'];

    if (!nonImageQuestions.some(q => clean.includes(q)) && imageKeywords.some(kw => clean.includes(kw))) {
      return { intent: 'IMAGE_GENERATION', confidence: 0.96, extractedPrompt: raw };
    }

    // 6. Chat Summary / Conversation Intelligence
    const chatSummaryKeywords = [
      'summarize this conversation', 'summarize chat', 'what did we discuss',
      'summarize our messages', 'conversation summary', 'find messages about'
    ];
    if (chatSummaryKeywords.some(kw => clean.includes(kw))) {
      return { intent: 'CHAT_SUMMARY', confidence: 0.95, extractedPrompt: raw };
    }

    // 7. Coding & Engineering Intent
    const codingKeywords = [
      'java', 'python', 'javascript', 'typescript', 'react', 'node', 'sql', 'docker',
      'kubernetes', 'k8s', 'aws', 'linux', 'bash', 'two sum', 'dsa', 'algorithm',
      'time complexity', 'space complexity', 'debug', 'fix this error', 'syntax error',
      'write a function', 'write code', 'regex', 'api endpoint', 'prisma', 'flutter'
    ];
    if (codingKeywords.some(kw => clean.includes(kw))) {
      return { intent: 'CODING', confidence: 0.94, extractedPrompt: raw };
    }

    // Default: General Text AI
    return { intent: 'TEXT_GENERATION', confidence: 0.95, extractedPrompt: raw };
  }

  /**
   * Arithmetic Calculator execution
   */
  public static evaluateMathExpression(expression: string): string {
    try {
      const sanitized = expression.replace(/[^0-9\+\-\*\/\(\)\.]/g, '');
      const result = new Function(`"use strict"; return (${sanitized});`)();
      if (typeof result === 'number' && !isNaN(result)) {
        return `🧮 **Calculation Result**: \`${sanitized} = ${result}\``;
      }
    } catch (_) {}
    return `Unable to calculate expression: \`${expression}\``;
  }

  /**
   * Builds context history from database
   */
  public static async buildConversationContext(conversationId: string, limit: number = 8): Promise<ChatMessageContext[]> {
    try {
      const messages = await (prisma as any).aIMessage.findMany({
        where: { conversationId },
        orderBy: { createdAt: 'asc' },
        take: limit,
      });

      return messages.map((msg: any) => ({
        role: msg.sender === 'USER' ? 'user' : 'assistant',
        content: msg.content,
      }));
    } catch (_) {
      return [];
    }
  }

  /**
   * Determines active AI provider and endpoint configuration
   */
  private static getProviderConfig(): { hostname: string; path: string; apiKey?: string; model: string } {
    if (process.env.GROQ_API_KEY) {
      return {
        hostname: 'api.groq.com',
        path: '/openai/v1/chat/completions',
        apiKey: process.env.GROQ_API_KEY,
        model: 'llama-3.3-70b-versatile',
      };
    }

    if (process.env.OPENAI_API_KEY) {
      return {
        hostname: 'api.openai.com',
        path: '/v1/chat/completions',
        apiKey: process.env.OPENAI_API_KEY,
        model: 'gpt-4o-mini',
      };
    }

    // Zero-config ultra-fast OpenAI-compatible endpoint with real models (Llama 3.3 / Mistral)
    return {
      hostname: 'text.pollinations.ai',
      path: '/openai/chat/completions',
      model: 'openai',
    };
  }

  /**
   * Generates text response using active LLM provider (Groq / OpenAI / Pollinations)
   * Zero mock/fake answers.
   */
  public static async generateTextResponse(
    prompt: string,
    history: ChatMessageContext[] = [],
    username?: string
  ): Promise<{ text: string; model: string; tokens: number }> {
    const config = this.getProviderConfig();

    const messages = [
      { role: 'system', content: this.SYSTEM_INSTRUCTION },
      ...history.slice(-6),
      { role: 'user', content: prompt },
    ];

    const payload = JSON.stringify({
      model: config.model,
      messages,
      temperature: 0.7,
      max_tokens: 1500,
    });

    try {
      const reply = await this.httpPostRequest(config.hostname, config.path, payload, config.apiKey);
      if (reply) {
        return {
          text: reply,
          model: `dolsyx-ai (${config.model})`,
          tokens: Math.ceil((prompt.length + reply.length) / 4),
        };
      }
    } catch (err) {
      console.error('[AIOrchestrator] Provider execution failed:', err);
    }

    // Graceful error message without fake answers
    return {
      text: "I am experiencing a momentary connection delay with the AI processing cluster. Please retry your request in a few moments.",
      model: 'dolsyx-ai-fallback',
      tokens: Math.ceil(prompt.length / 4),
    };
  }

  /**
   * Live Server-Sent Events (SSE) streaming token generator
   * Pipes live tokens directly from the provider without synthetic delays
   */
  public static streamTextResponse(
    prompt: string,
    history: ChatMessageContext[] = [],
    onToken: (token: string) => void,
    onDone: (fullText: string) => void,
    onError: (err: Error) => void
  ): () => void {
    const config = this.getProviderConfig();

    const messages = [
      { role: 'system', content: this.SYSTEM_INSTRUCTION },
      ...history.slice(-6),
      { role: 'user', content: prompt },
    ];

    const payload = JSON.stringify({
      model: config.model,
      messages,
      temperature: 0.7,
      max_tokens: 1500,
      stream: true,
    });

    const headers: Record<string, string | number> = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload),
    };
    if (config.apiKey) {
      headers['Authorization'] = `Bearer ${config.apiKey}`;
    }

    let fullAccumulated = '';
    let isAborted = false;

    const req = https.request(
      {
        hostname: config.hostname,
        port: 443,
        path: config.path,
        method: 'POST',
        headers,
        timeout: 30000,
      },
      (res) => {
        let buffer = '';

        res.on('data', (chunk: Buffer) => {
          if (isAborted) return;
          buffer += chunk.toString('utf8');

          const lines = buffer.split('\n');
          buffer = lines.pop() || '';

          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || !trimmed.startsWith('data:')) continue;
            const jsonStr = trimmed.replace(/^data:\s*/, '');

            if (jsonStr === '[DONE]') {
              onDone(fullAccumulated);
              return;
            }

            try {
              const parsed = JSON.parse(jsonStr);
              const content = parsed.choices?.[0]?.delta?.content;
              if (content) {
                fullAccumulated += content;
                onToken(content);
              }
            } catch (_) {
              // Partial JSON line
            }
          }
        });

        res.on('end', () => {
          if (!isAborted) {
            onDone(fullAccumulated);
          }
        });
      }
    );

    req.on('error', (err) => {
      if (!isAborted) onError(err);
    });

    req.on('timeout', () => {
      req.destroy();
      if (!isAborted) onError(new Error('AI stream connection timed out'));
    });

    req.write(payload);
    req.end();

    return () => {
      isAborted = true;
      req.destroy();
    };
  }

  /**
   * Multimodal Image Understanding & Analysis
   */
  public static async analyzeImage(prompt: string, imageUrl: string): Promise<{ text: string; model: string }> {
    const config = this.getProviderConfig();

    const messages = [
      { role: 'system', content: this.SYSTEM_INSTRUCTION },
      {
        role: 'user',
        content: [
          { type: 'text', text: prompt || 'Analyze and describe this image in detail.' },
          { type: 'image_url', image_url: { url: imageUrl } },
        ],
      },
    ];

    const payload = JSON.stringify({
      model: config.apiKey ? config.model : 'openai',
      messages,
      max_tokens: 1200,
    });

    try {
      const reply = await this.httpPostRequest(config.hostname, config.path, payload, config.apiKey);
      if (reply) {
        return { text: reply, model: 'dolsyx-ai-vision' };
      }
    } catch (err) {
      console.error('[AIOrchestrator] Multimodal analysis error:', err);
    }

    return {
      text: "Unable to analyze the provided image at this time. Please check the image format and try again.",
      model: 'dolsyx-ai-vision',
    };
  }

  private static httpPostRequest(hostname: string, path: string, payload: string, apiKey?: string): Promise<string | null> {
    return new Promise((resolve) => {
      const headers: Record<string, string | number> = {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      };
      if (apiKey) {
        headers['Authorization'] = `Bearer ${apiKey}`;
      }

      const req = https.request(
        {
          hostname,
          port: 443,
          path,
          method: 'POST',
          headers,
          timeout: 25000,
        },
        (res) => {
          let data = '';
          res.on('data', (chunk) => (data += chunk));
          res.on('end', () => {
            try {
              const json = JSON.parse(data);
              const content = json.choices?.[0]?.message?.content;
              resolve(content || null);
            } catch (_) {
              resolve(null);
            }
          });
        }
      );

      req.on('error', () => resolve(null));
      req.on('timeout', () => {
        req.destroy();
        resolve(null);
      });
      req.write(payload);
      req.end();
    });
  }
}
