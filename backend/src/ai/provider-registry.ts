import type { AIProviderConfig } from './types.js';
import { OpenAICompatibleProvider } from './openai-provider.js';

export class AIProviderRegistry {
  public static getActiveConfig(): AIProviderConfig {
    // 1. Explicit AI_PROVIDER or Groq API Key
    if (process.env.GROQ_API_KEY) {
      return {
        name: 'groq',
        apiKey: process.env.GROQ_API_KEY,
        baseURL: 'https://api.groq.com/openai/v1/chat/completions',
        model: process.env.AI_MODEL || 'llama-3.3-70b-versatile',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 2. OpenAI API Key
    if (process.env.OPENAI_API_KEY) {
      return {
        name: 'openai',
        apiKey: process.env.OPENAI_API_KEY,
        baseURL: 'https://api.openai.com/v1/chat/completions',
        model: process.env.AI_MODEL || 'gpt-4o-mini',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 3. Gemini API Key (via Google's official OpenAI-compatible endpoint)
    if (process.env.GEMINI_API_KEY) {
      return {
        name: 'gemini',
        apiKey: process.env.GEMINI_API_KEY,
        baseURL: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        model: process.env.AI_MODEL || 'gemini-1.5-flash',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 4. Custom AI_BASE_URL (for Ollama, vLLM, OpenRouter, LocalAI)
    if (process.env.AI_BASE_URL) {
      return {
        name: process.env.AI_PROVIDER || 'custom',
        apiKey: process.env.AI_API_KEY,
        baseURL: process.env.AI_BASE_URL,
        model: process.env.AI_MODEL || 'default-model',
        temperature: 0.7,
        maxTokens: 2048,
      };
    }

    // 5. Zero-config live endpoint for development & testing
    return {
      name: 'pollinations',
      baseURL: 'https://text.pollinations.ai/openai/chat/completions',
      model: process.env.AI_MODEL || 'openai',
      temperature: 0.7,
      maxTokens: 2048,
    };
  }

  public static getActiveProvider(): OpenAICompatibleProvider {
    const config = this.getActiveConfig();
    return new OpenAICompatibleProvider(config);
  }
}
