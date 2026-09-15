import https from 'https';
import http from 'http';
import type {
  AIProviderConfig,
  ChatMessage,
  AIResponsePayload,
  AIStreamCallbacks,
  ToolDefinition,
  ToolExecutionContext,
} from './types.js';
import { AIToolRegistry } from './tools/registry.js';
import { AISafetyLayer } from './safety-layer.js';

export class OpenAICompatibleProvider {
  private config: AIProviderConfig;

  constructor(config: AIProviderConfig) {
    this.config = config;
  }

  /**
   * Generates a complete non-streaming response with optional tool calling.
   */
  public async generateCompletion(
    messages: ChatMessage[],
    tools: ToolDefinition[] = [],
    context: ToolExecutionContext
  ): Promise<AIResponsePayload> {
    const payloadObj: any = {
      model: this.config.model,
      messages: messages.map(m => ({ role: m.role, content: m.content })),
      temperature: this.config.temperature ?? 0.7,
      max_tokens: this.config.maxTokens ?? 2000,
    };

    if (tools.length > 0) {
      payloadObj.tools = tools.map(t => ({
        type: 'function',
        function: {
          name: t.name,
          description: t.description,
          parameters: t.parameters,
        },
      }));
      payloadObj.tool_choice = 'auto';
    }

    const payload = JSON.stringify(payloadObj);
    const rawResponse = await this.postJson(payload);

    let parsed: any;
    try {
      parsed = JSON.parse(rawResponse);
    } catch (_) {
      return {
        text: AISafetyLayer.sanitizeOutput(rawResponse),
        model: this.config.model,
        tokens: Math.ceil(rawResponse.length / 4),
      };
    }

    const choice = parsed?.choices?.[0];
    const message = choice?.message;

    // Check if the model decided to call tools
    if (message?.tool_calls && message.tool_calls.length > 0) {
      const toolResults: any[] = [];
      const followUpMessages: ChatMessage[] = [...messages, message];

      for (const tc of message.tool_calls) {
        const fnName = tc.function?.name;
        let fnArgs = {};
        try {
          fnArgs = JSON.parse(tc.function?.arguments || '{}');
        } catch (_) {}

        console.log(`[OpenAIProvider] Executing tool: ${fnName} with args:`, fnArgs);
        const result = await AIToolRegistry.executeTool(fnName, fnArgs, context);
        toolResults.push(result);

        followUpMessages.push({
          role: 'tool',
          name: fnName,
          tool_call_id: tc.id,
          content: JSON.stringify(result.result || { error: result.error }),
        });
      }

      // Re-invoke model with tool execution output to generate final natural response
      const followUpPayload = JSON.stringify({
        model: this.config.model,
        messages: followUpMessages.map(m => ({ role: m.role, content: m.content })),
        temperature: this.config.temperature ?? 0.7,
        max_tokens: this.config.maxTokens ?? 2000,
      });

      try {
        const followUpRaw = await this.postJson(followUpPayload);
        const followUpParsed = JSON.parse(followUpRaw);
        const finalText = followUpParsed?.choices?.[0]?.message?.content || '';
        return {
          text: AISafetyLayer.sanitizeOutput(finalText),
          model: this.config.model,
          tokens: Math.ceil((finalText.length + rawResponse.length) / 4),
          toolResults,
        };
      } catch (err) {
        console.warn('[OpenAIProvider] Follow-up tool synthesis error, returning raw tool output:', err);
        return {
          text: `Tool results: ${JSON.stringify(toolResults.map(t => t.result))}`,
          model: this.config.model,
          tokens: 100,
          toolResults,
        };
      }
    }

    const text = message?.content || parsed?.reply || parsed?.text || '';
    return {
      text: AISafetyLayer.sanitizeOutput(text),
      model: this.config.model,
      tokens: parsed?.usage?.total_tokens || Math.ceil(text.length / 4),
    };
  }

  /**
   * Real-time Token-by-Token SSE Streaming execution
   */
  public streamCompletion(
    messages: ChatMessage[],
    callbacks: AIStreamCallbacks,
    tools: ToolDefinition[] = [],
    context: ToolExecutionContext
  ): () => void {
    let isCancelled = false;
    let accumulatedText = '';

    const payload = JSON.stringify({
      model: this.config.model,
      messages: messages.map(m => ({ role: m.role, content: m.content })),
      temperature: this.config.temperature ?? 0.7,
      max_tokens: this.config.maxTokens ?? 2000,
      stream: true,
    });

    const parsedUrl = new URL(this.config.baseURL || 'https://api.groq.com/openai/v1/chat/completions');
    const isHttps = parsedUrl.protocol === 'https:';
    const client = isHttps ? https : http;

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'User-Agent': 'DOLSYX-AI/2.0',
    };

    if (this.config.apiKey) {
      headers['Authorization'] = `Bearer ${this.config.apiKey}`;
    }

    const req = client.request(
      {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port || (isHttps ? 443 : 80),
        path: `${parsedUrl.pathname}${parsedUrl.search}`,
        method: 'POST',
        headers,
        timeout: 45000,
      },
      res => {
        let buffer = '';

        res.on('data', chunk => {
          if (isCancelled) return;
          buffer += chunk.toString();

          const lines = buffer.split('\n');
          buffer = lines.pop() || '';

          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || !trimmed.startsWith('data:')) continue;
            const dataStr = trimmed.replace(/^data:\s*/, '');
            if (dataStr === '[DONE]') {
              callbacks.onComplete(accumulatedText);
              return;
            }

            try {
              const parsed = JSON.parse(dataStr);
              const delta = parsed?.choices?.[0]?.delta?.content;
              if (delta) {
                accumulatedText += delta;
                callbacks.onToken(delta);
              }
            } catch (_) {}
          }
        });

        res.on('end', () => {
          if (!isCancelled) {
            callbacks.onComplete(accumulatedText);
          }
        });

        res.on('error', err => {
          if (!isCancelled) {
            callbacks.onError(err);
          }
        });
      }
    );

    req.on('error', err => {
      if (!isCancelled) {
        callbacks.onError(err);
      }
    });

    req.write(payload);
    req.end();

    return () => {
      isCancelled = true;
      try {
        req.destroy();
      } catch (_) {}
    };
  }

  private postJson(payload: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const parsedUrl = new URL(this.config.baseURL || 'https://api.groq.com/openai/v1/chat/completions');
      const isHttps = parsedUrl.protocol === 'https:';
      const client = isHttps ? https : http;

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload).toString(),
        'User-Agent': 'DOLSYX-AI/2.0',
      };

      if (this.config.apiKey) {
        headers['Authorization'] = `Bearer ${this.config.apiKey}`;
      }

      const req = client.request(
        {
          hostname: parsedUrl.hostname,
          port: parsedUrl.port || (isHttps ? 443 : 80),
          path: `${parsedUrl.pathname}${parsedUrl.search}`,
          method: 'POST',
          headers,
          timeout: 30000,
        },
        res => {
          let data = '';
          res.on('data', chunk => (data += chunk));
          res.on('end', () => {
            if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
              resolve(data);
            } else {
              reject(new Error(`AI Provider returned HTTP ${res.statusCode}: ${data}`));
            }
          });
        }
      );

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('AI Provider request timed out'));
      });

      req.write(payload);
      req.end();
    });
  }
}
