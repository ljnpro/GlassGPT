export type ModelId = "gpt-5.4" | "gpt-5.4-pro";

export type ReasoningEffort = "none" | "low" | "medium" | "high" | "xhigh";

export type MessageRole = "user" | "assistant" | "system";

export type AppTheme = "light" | "dark" | "system";

export interface ModelConfig {
  id: ModelId;
  label: string;
  description: string;
  reasoningEfforts: ReadonlyArray<ReasoningEffort>;
  defaultEffort: ReasoningEffort;
}

export const MODELS: ModelConfig[] = [
  {
    id: "gpt-5.4",
    label: "GPT-5.4",
    description: "Fast and flexible for everyday work, writing, analysis, and multimodal tasks.",
    reasoningEfforts: ["none", "low", "medium", "high", "xhigh"],
    defaultEffort: "high",
  },
  {
    id: "gpt-5.4-pro",
    label: "GPT-5.4 Pro",
    description: "Most capable model for advanced reasoning, deep analysis, and complex problem solving.",
    reasoningEfforts: ["medium", "high", "xhigh"],
    defaultEffort: "xhigh",
  },
];

export const DEFAULT_MODEL: ModelId = "gpt-5.4-pro";
export const DEFAULT_EFFORT: ReasoningEffort = "xhigh";

export interface ImageAttachment {
  uri: string;
  base64?: string;
  width?: number;
  height?: number;
  mimeType?: string;
  fileName?: string;
}

export interface MessageContent {
  type: "text" | "image_url" | "input_text" | "input_image";
  text?: string;
  image_url?: string | { url: string; detail?: "auto" | "low" | "high" };
}

export interface ResponseUsage {
  inputTokens?: number;
  outputTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  cachedInputTokens?: number;
}

export interface Message {
  id: string;
  role: MessageRole;
  content: string;
  images?: ImageAttachment[];
  reasoning?: string;
  model?: ModelId;
  effort?: ReasoningEffort;
  usage?: ResponseUsage;
  error?: string;
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
  theme: AppTheme;
}

export const DEFAULT_SETTINGS: AppSettings = {
  apiKey: "",
  defaultModel: DEFAULT_MODEL,
  defaultEffort: DEFAULT_EFFORT,
  theme: "system",
};

export function isModelId(value: unknown): value is ModelId {
  return value === "gpt-5.4" || value === "gpt-5.4-pro";
}

export function isReasoningEffort(value: unknown): value is ReasoningEffort {
  return (
    value === "none" ||
    value === "low" ||
    value === "medium" ||
    value === "high" ||
    value === "xhigh"
  );
}

export function normalizeModelId(value: unknown): ModelId {
  return isModelId(value) ? value : DEFAULT_MODEL;
}

export function getModelConfig(modelId: ModelId): ModelConfig {
  const config = MODELS.find((item) => item.id === modelId);
  return config ?? MODELS.find((item) => item.id === DEFAULT_MODEL)!;
}

export function isEffortSupported(modelId: ModelId, effort: unknown): effort is ReasoningEffort {
  if (!isReasoningEffort(effort)) {
    return false;
  }

  return getModelConfig(modelId).reasoningEfforts.includes(effort);
}

export function normalizeReasoningEffort(
  modelId: ModelId,
  effort: unknown
): ReasoningEffort {
  if (isEffortSupported(modelId, effort)) {
    return effort;
  }

  return getModelConfig(modelId).defaultEffort;
}
