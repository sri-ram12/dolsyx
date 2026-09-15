import type { AIProviderConfig } from './types.js';
import { OpenAICompatibleProvider } from './openai-provider.js';

export class AIProviderRegistry {
  public static getActiveConfig(): AIProviderConfig {
    const groqKey = (process.env.GROQ_API_KEY || process.env.GROK_API_KEY || process.env.GROQ_KEY || process.env.GROK_KEY || '').trim();
    const xaiKey = (process.env.XAI_API_KEY || (groqKey.startsWith('xai-') ? groqKey : '')).trim();
    const geminiKey = (process.env.GEMINI_API_KEY || '').trim();
    const openaiKey = (process.env.OPENAI_API_KEY || '').trim();
    const customKey = (process.env.AI_API_KEY || '').trim();

    // 1. xAI Grok (if key starts with xai- or XAI_API_KEY is provided)
    if (xaiKey) {
      return {
        name: 'xai',
        apiKey: xaiKey,
        baseURL: 'https://api.x.ai/v1/chat/completions',
        model: process.env.AI_MODEL || 'grok-2-latest',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 2. Groq Cloud (keys start with gsk_ or GROQ_API_KEY/GROK_API_KEY set)
    if (groqKey) {
      return {
        name: 'groq',
        apiKey: groqKey,
        baseURL: 'https://api.groq.com/openai/v1/chat/completions',
        model: process.env.AI_MODEL || 'openai/gpt-oss-120b',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 3. OpenAI API Key
    if (openaiKey) {
      return {
        name: 'openai',
        apiKey: openaiKey,
        baseURL: 'https://api.openai.com/v1/chat/completions',
        model: process.env.AI_MODEL || 'gpt-4o-mini',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 4. Gemini API Key
    if (geminiKey) {
      return {
        name: 'gemini',
        apiKey: geminiKey,
        baseURL: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        model: process.env.AI_MODEL || 'gemini-1.5-flash',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 5. Custom AI_BASE_URL (for Ollama, vLLM, OpenRouter, LocalAI)
    if (process.env.AI_BASE_URL) {
      return {
        name: process.env.AI_PROVIDER || 'custom',
        apiKey: customKey || groqKey || openaiKey,
        baseURL: process.env.AI_BASE_URL,
        model: process.env.AI_MODEL || 'default-model',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 6. Native Built-in Synthesizer (default zero-key mode)
    return {
      name: 'synthesizer',
      baseURL: 'local://synthesizer',
      model: 'dolsyx-ai-synthesizer',
      temperature: 0.7,
      maxTokens: 2048,
    };
  }

  public static hasExternalApiKey(): boolean {
    const rawKey = (
      process.env.GROQ_API_KEY ||
      process.env.GROK_API_KEY ||
      process.env.GROQ_KEY ||
      process.env.GROK_KEY ||
      process.env.XAI_API_KEY ||
      process.env.AI_API_KEY ||
      process.env.OPENAI_API_KEY ||
      process.env.GEMINI_API_KEY ||
      process.env.AI_BASE_URL ||
      ''
    ).trim();
    return rawKey.length > 0;
  }

  public static getActiveProvider(): OpenAICompatibleProvider {
    const config = this.getActiveConfig();
    return new OpenAICompatibleProvider(config);
  }
}
