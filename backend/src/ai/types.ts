export type Role = 'system' | 'user' | 'assistant' | 'tool';

export interface ChatMessage {
  role: Role;
  content: string;
  name?: string | undefined;
  tool_call_id?: string | undefined;
  tool_calls?: ToolCall[] | undefined;
}

export interface ToolCall {
  id: string;
  type: 'function';
  function: {
    name: string;
    arguments: string;
  };
}

export interface ToolDefinition {
  name: string;
  description: string;
  parameters: {
    type: 'object';
    properties: Record<string, any>;
    required?: string[] | undefined;
  };
}

export interface ToolExecutionContext {
  userId: string;
  username?: string | undefined;
  conversationId?: string | undefined;
}

export interface AIToolResult {
  toolName: string;
  success: boolean;
  result: any;
  error?: string | undefined;
}

export interface AIProviderConfig {
  name: string;
  apiKey?: string | undefined;
  baseURL?: string | undefined;
  model: string;
  visionModel?: string | undefined;
  imageModel?: string | undefined;
  temperature?: number | undefined;
  maxTokens?: number | undefined;
}

export interface AIStreamCallbacks {
  onToken: (token: string) => void;
  onToolCall?: ((toolName: string, args: any) => void) | undefined;
  onComplete: (fullText: string, metadata?: Record<string, any> | undefined) => void;
  onError: (error: Error) => void;
}

export interface AIResponsePayload {
  text: string;
  model: string;
  tokens: number;
  toolResults?: AIToolResult[] | undefined;
  metadata?: Record<string, any> | undefined;
}

export interface AIConversationMetadata {
  id: string;
  userId: string;
  title: string;
  mode: string;
  createdAt: string;
  updatedAt: string;
  lastMessageSnippet?: string | undefined;
}

export interface AIMemoryItem {
  id: string;
  userId: string;
  content: string;
  category: 'PREFERENCE' | 'FACT' | 'INSTRUCTION';
  source: string;
  createdAt: Date;
}
