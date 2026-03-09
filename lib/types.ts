export type ModelId = 'gpt-5.4' | 'gpt-5.4-pro';

export type ReasoningEffort = 'none' | 'low' | 'medium' | 'high' | 'xhigh';

export interface ModelConfig {
  id: ModelId;
  label: string;
  reasoningEfforts: ReasoningEffort[];
  defaultEffort: ReasoningEffort;
}

export const MODELS: ModelConfig[] = [
  {
    id: 'gpt-5.4',
    label: 'GPT-5.4',
    reasoningEfforts: ['none', 'low', 'medium', 'high', 'xhigh'],
    defaultEffort: 'high',
  },
  {
    id: 'gpt-5.4-pro',
    label: 'GPT-5.4 Pro',
    reasoningEfforts: ['medium', 'high', 'xhigh'],
    defaultEffort: 'xhigh',
  },
];

export const DEFAULT_MODEL: ModelId = 'gpt-5.4-pro';
export const DEFAULT_EFFORT: ReasoningEffort = 'xhigh';

export interface ImageAttachment {
  uri: string;
  base64?: string;
  width?: number;
  height?: number;
  mimeType?: string;
}

export interface MessageContent {
  type: 'text' | 'image_url';
  text?: string;
  image_url?: { url: string; detail?: 'auto' | 'low' | 'high' };
}

export interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  images?: ImageAttachment[];
  reasoning?: string;
  model?: ModelId;
  effort?: ReasoningEffort;
  createdAt: number;
  isStreaming?: boolean;
}

export interface Conversation {
  id: string;
  title: string;
  messages: Message[];
  model: ModelId;
  effort: ReasoningEffort;
  createdAt: number;
  updatedAt: number;
}

export interface AppSettings {
  apiKey: string;
  defaultModel: ModelId;
  defaultEffort: ReasoningEffort;
  theme: 'light' | 'dark' | 'system';
}

export const DEFAULT_SETTINGS: AppSettings = {
  apiKey: '',
  defaultModel: DEFAULT_MODEL,
  defaultEffort: DEFAULT_EFFORT,
  theme: 'system',
};
