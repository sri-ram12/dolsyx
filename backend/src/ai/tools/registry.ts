import type { ToolDefinition, ToolExecutionContext, AIToolResult } from '../types.js';
import { prisma } from '../../config/db.js';
import { AIMemoryManager } from '../memory-manager.js';

export interface ToolHandler {
  definition: ToolDefinition;
  execute: (args: any, context: ToolExecutionContext) => Promise<any>;
}

export class AIToolRegistry {
  private static tools: Map<string, ToolHandler> = new Map();

  public static registerTool(handler: ToolHandler): void {
    this.tools.set(handler.definition.name, handler);
  }

  public static getToolDefinitions(): ToolDefinition[] {
    return Array.from(this.tools.values()).map(t => t.definition);
  }

  public static async executeTool(
    toolName: string,
    args: any,
    context: ToolExecutionContext
  ): Promise<AIToolResult> {
    const handler = this.tools.get(toolName);
    if (!handler) {
      return {
        toolName,
        success: false,
        result: null,
        error: `Tool '${toolName}' is not recognized or permitted.`,
      };
    }

    try {
      // Execute tool with 15s timeout
      const result = await Promise.race([
        handler.execute(args, context),
        new Promise((_, reject) => setTimeout(() => reject(new Error(`Tool '${toolName}' timed out`)), 15000)),
      ]);

      return {
        toolName,
        success: true,
        result,
      };
    } catch (err: any) {
      console.error(`[AIToolRegistry] Error executing tool '${toolName}':`, err.message);
      return {
        toolName,
        success: false,
        result: null,
        error: err.message || 'Tool execution failed',
      };
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REGISTER CORE BUILT-IN TOOLS
// ─────────────────────────────────────────────────────────────────────────────

// 1. Calculator Tool
AIToolRegistry.registerTool({
  definition: {
    name: 'calculate',
    description: 'Safely evaluate a mathematical or arithmetic expression.',
    parameters: {
      type: 'object',
      properties: {
        expression: {
          type: 'string',
          description: 'The math expression to evaluate, e.g. "482 * 19" or "(2500 / 12) * 1.18"',
        },
      },
      required: ['expression'],
    },
  },
  execute: async ({ expression }) => {
    if (!expression || typeof expression !== 'string') return 'Invalid expression';
    const clean = expression.replace(/[^0-9\+\-\*\/\(\)\.\%\^\s]/g, '');
    try {
      const result = new Function(`"use strict"; return (${clean});`)();
      if (typeof result === 'number' && !isNaN(result)) {
        return { expression: clean, result };
      }
    } catch (_) {}
    return { expression: clean, error: 'Could not compute expression' };
  },
});

// 2. Weather Tool (Using Open-Meteo free public API)
AIToolRegistry.registerTool({
  definition: {
    name: 'getWeather',
    description: 'Get current weather and temperature for a given city or location.',
    parameters: {
      type: 'object',
      properties: {
        location: {
          type: 'string',
          description: 'City or location name, e.g. "Hyderabad", "London", "Tokyo"',
        },
      },
      required: ['location'],
    },
  },
  execute: async ({ location }) => {
    try {
      // Geocode city name
      const geoUrl = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1&language=en&format=json`;
      const geoRes = await fetch(geoUrl, { signal: AbortSignal.timeout(5000) });
      const geoData = await geoRes.json();

      if (!geoData.results || geoData.results.length === 0) {
        return { error: `Location "${location}" could not be geocoded.` };
      }

      const place = geoData.results[0];
      const weatherUrl = `https://api.open-meteo.com/v1/forecast?latitude=${place.latitude}&longitude=${place.longitude}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&timezone=auto`;
      const wRes = await fetch(weatherUrl, { signal: AbortSignal.timeout(5000) });
      const wData = await wRes.json();

      return {
        location: `${place.name}, ${place.country || ''}`,
        temperatureCelsius: wData.current?.temperature_2m,
        humidity: wData.current?.relative_humidity_2m,
        windSpeedKmh: wData.current?.wind_speed_10m,
      };
    } catch (err: any) {
      return { error: `Unable to fetch weather: ${err.message}` };
    }
  },
});

// 3. Live Web Information Tool (Using DuckDuckGo Instant Answer / Wikipedia REST API)
AIToolRegistry.registerTool({
  definition: {
    name: 'searchWeb',
    description: 'Search the web for up-to-date information, facts, definitions, or current events.',
    parameters: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'The search query or entity name',
        },
      },
      required: ['query'],
    },
  },
  execute: async ({ query }) => {
    if (!query) return { error: 'Query is required' };
    const results: any = { query, findings: [] };

    // Search Wikipedia Summary API
    try {
      const topic = query.replace(/^(what is|who is|explain|tell me about)\s+/i, '').trim();
      const wikiUrl = `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(topic.replace(/\s+/g, '_'))}`;
      const wikiRes = await fetch(wikiUrl, {
        headers: { 'User-Agent': 'DOLSYX-AI/2.0 (contact@dolsyx.com)' },
        signal: AbortSignal.timeout(6000),
      });

      if (wikiRes.ok) {
        const wikiData = await wikiRes.json();
        if (wikiData.extract && wikiData.type !== 'disambiguation') {
          results.findings.push({
            source: 'Wikipedia',
            title: wikiData.title,
            extract: wikiData.extract,
            url: wikiData.content_urls?.desktop?.page || null,
          });
        }
      }
    } catch (_) {}

    // Search DuckDuckGo Instant Answers
    try {
      const ddgUrl = `https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1`;
      const ddgRes = await fetch(ddgUrl, { signal: AbortSignal.timeout(6000) });
      if (ddgRes.ok) {
        const ddgData = await ddgRes.json();
        if (ddgData.AbstractText) {
          results.findings.push({
            source: ddgData.AbstractSource || 'DuckDuckGo',
            title: ddgData.Heading,
            extract: ddgData.AbstractText,
            url: ddgData.AbstractURL || null,
          });
        }
      }
    } catch (_) {}

    if (results.findings.length === 0) {
      return { query, message: 'No immediate external articles found. Relying on core knowledge base.' };
    }

    return results;
  },
});

// 4. Search Messages Tool (Authorized: only messages in conversations the user belongs to)
AIToolRegistry.registerTool({
  definition: {
    name: 'searchMessages',
    description: 'Search for messages containing specific keywords in the user\'s authorized conversations.',
    parameters: {
      type: 'object',
      properties: {
        searchTerm: {
          type: 'string',
          description: 'The search text to match in messages',
        },
      },
      required: ['searchTerm'],
    },
  },
  execute: async ({ searchTerm }, context) => {
    if (!context.userId || context.userId === 'guest_user') {
      return { error: 'Authentication required to search messages.' };
    }

    try {
      // Find conversations the user is a participant in
      const participations = await (prisma as any).participant.findMany({
        where: { userId: context.userId },
        select: { conversationId: true },
      });

      const convIds = participations.map((p: any) => p.conversationId);
      if (convIds.length === 0) {
        return { messages: [], count: 0 };
      }

      const matchedMessages = await (prisma as any).message.findMany({
        where: {
          conversationId: { in: convIds },
          content: { contains: searchTerm, mode: 'insensitive' },
        },
        orderBy: { createdAt: 'desc' },
        take: 10,
        select: {
          id: true,
          content: true,
          createdAt: true,
          sender: { select: { username: true } },
          conversationId: true,
        },
      });

      return {
        count: matchedMessages.length,
        messages: matchedMessages.map((m: any) => ({
          sender: m.sender?.username || 'User',
          content: m.content,
          date: m.createdAt,
          conversationId: m.conversationId,
        })),
      };
    } catch (err: any) {
      return { error: `Failed to search messages: ${err.message}` };
    }
  },
});

// 5. Search Contacts Tool (Authorized)
AIToolRegistry.registerTool({
  definition: {
    name: 'searchContacts',
    description: 'Search user contacts and registered profiles in DOLSYX.',
    parameters: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Name or username to search for',
        },
      },
      required: ['query'],
    },
  },
  execute: async ({ query }, context) => {
    if (!context.userId || context.userId === 'guest_user') {
      return { error: 'Authentication required to search contacts.' };
    }

    try {
      const users = await (prisma as any).user.findMany({
        where: {
          OR: [
            { username: { contains: query, mode: 'insensitive' } },
            { statusMessage: { contains: query, mode: 'insensitive' } },
          ],
        },
        take: 5,
        select: {
          id: true,
          username: true,
          avatarUrl: true,
          statusMessage: true,
        },
      });

      return { users };
    } catch (err: any) {
      return { error: `Failed to search contacts: ${err.message}` };
    }
  },
});

// 6. Summarize Conversation Tool (Authorized)
AIToolRegistry.registerTool({
  definition: {
    name: 'summarizeConversation',
    description: 'Summarize the recent messages from an authorized chat conversation.',
    parameters: {
      type: 'object',
      properties: {
        conversationId: {
          type: 'string',
          description: 'The conversation ID to summarize',
        },
      },
      required: ['conversationId'],
    },
  },
  execute: async ({ conversationId }, context) => {
    if (!context.userId || context.userId === 'guest_user') {
      return { error: 'Authentication required to summarize conversations.' };
    }

    try {
      // Verify user is participant
      const isPart = await (prisma as any).participant.findFirst({
        where: { conversationId, userId: context.userId },
      });

      if (!isPart) {
        return { error: 'Access denied: You are not a participant in this conversation.' };
      }

      const messages = await (prisma as any).message.findMany({
        where: { conversationId },
        orderBy: { createdAt: 'desc' },
        take: 30,
        select: {
          content: true,
          createdAt: true,
          sender: { select: { username: true } },
        },
      });

      if (messages.length === 0) {
        return { summary: 'No messages found in this conversation.' };
      }

      const formatted = messages
        .reverse()
        .map((m: any) => `${m.sender?.username || 'User'}: ${m.content}`)
        .join('\n');

      return {
        messageCount: messages.length,
        transcriptSnippet: formatted,
      };
    } catch (err: any) {
      return { error: `Failed to summarize conversation: ${err.message}` };
    }
  },
});

// 7. Save Memory Tool
AIToolRegistry.registerTool({
  definition: {
    name: 'saveUserMemory',
    description: 'Persist a user preference or factual instruction for future conversations.',
    parameters: {
      type: 'object',
      properties: {
        content: {
          type: 'string',
          description: 'The preference or fact to remember, e.g. "Prefers responses in Telugu" or "Works as a Flutter developer"',
        },
        category: {
          type: 'string',
          enum: ['PREFERENCE', 'FACT', 'INSTRUCTION'],
          description: 'The category of memory',
        },
      },
      required: ['content'],
    },
  },
  execute: async ({ content, category }, context) => {
    if (!context.userId || context.userId === 'guest_user') {
      return { message: 'Memory not persisted for guest users.' };
    }

    const saved = await AIMemoryManager.saveMemory(
      context.userId,
      content,
      category || 'PREFERENCE',
      'TOOL_EXECUTION'
    );

    return { success: !!saved, memory: saved };
  },
});
