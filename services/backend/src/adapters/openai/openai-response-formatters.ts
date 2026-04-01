import type {
  LiveToolCall,
  StreamingConversationMessage,
  StreamingConversationRequest,
} from '../../application/live-stream-model.js';
import { mergeToolCalls, type ResponsesResponse } from './openai-response-extraction.js';

export const DEFAULT_CHAT_MODEL = 'gpt-5.4';
export const DEFAULT_REASONING_EFFORT = 'medium';
export const DEFAULT_TIMEOUT_MS = 120_000;
export const MAX_RETRIES = 3;

export const timeoutForModel = (model: string): number => {
  if (model.includes('pro') || model.includes('deep')) return 300_000;
  if (model.includes('mini') || model.includes('fast')) return 60_000;
  return DEFAULT_TIMEOUT_MS;
};

export const RETRYABLE_STATUS_CODES = new Set([429, 500, 502, 503, 504]);

export interface StreamEnvelope {
  readonly annotation?: {
    readonly container_id?: string;
    readonly end_index?: number;
    readonly file_id?: string;
    readonly filename?: string;
    readonly start_index?: number;
    readonly title?: string;
    readonly type: string;
    readonly url?: string;
  };
  readonly code?: string;
  readonly delta?: string;
  readonly error?: {
    readonly message?: string;
  };
  readonly item_id?: string;
  readonly message?: string;
  readonly queries?: readonly string[];
  readonly query?: string;
  readonly response?: ResponsesResponse;
  readonly type: string;
}

export interface ResponsesApiBody extends ResponsesResponse {}

export interface ResponsesApiInputMessage {
  readonly content: string | ReadonlyArray<Record<string, unknown>>;
  readonly role: StreamingConversationMessage['role'];
}

export const parseRetryAfter = (response: Response): number | null => {
  const header = response.headers.get('retry-after');
  if (!header) return null;
  const seconds = Number.parseInt(header, 10);
  return Number.isFinite(seconds) && seconds > 0 ? seconds : null;
};

export const backoffDelay = (attempt: number, retryAfterSeconds: number | null): number => {
  if (retryAfterSeconds !== null) {
    return retryAfterSeconds * 1000;
  }
  const baseMs = 1000 * 2 ** attempt;
  const jitter = Math.random() * 500;
  return baseMs + jitter;
};

export const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

export const buildInputMessages = (
  input: string | readonly StreamingConversationMessage[],
  imageBase64?: string,
  fileIds?: readonly string[],
): string | ResponsesApiInputMessage[] => {
  const hasAttachments =
    (imageBase64 != null && imageBase64.length > 0) || (fileIds != null && fileIds.length > 0);

  if (typeof input === 'string') {
    if (!hasAttachments) {
      return input;
    }
    const parts: Array<Record<string, unknown>> = [];
    if (input.length > 0) {
      parts.push({ text: input, type: 'input_text' });
    }
    if (imageBase64) {
      parts.push({ image_url: `data:image/jpeg;base64,${imageBase64}`, type: 'input_image' });
    }
    for (const fileId of fileIds ?? []) {
      parts.push({ file_id: fileId, type: 'input_file' });
    }
    return [{ content: parts, role: 'user' as const }];
  }

  return input.map((message, index) => {
    const isLastUser = message.role === 'user' && index === input.length - 1;
    const contentType = message.role === 'assistant' ? 'output_text' : 'input_text';
    const parts: Array<Record<string, unknown>> = [];
    if (message.content.length > 0) {
      parts.push({ text: message.content, type: contentType });
    }
    if (isLastUser && imageBase64) {
      parts.push({ image_url: `data:image/jpeg;base64,${imageBase64}`, type: 'input_image' });
    }
    if (isLastUser) {
      for (const fileId of fileIds ?? []) {
        parts.push({ file_id: fileId, type: 'input_file' });
      }
    }
    return { content: parts, role: message.role };
  });
};

export const buildRequestBody = (request: StreamingConversationRequest) => {
  return {
    input: buildInputMessages(request.input, request.imageBase64, request.fileIds),
    model: request.model ?? DEFAULT_CHAT_MODEL,
    reasoning: {
      effort: request.reasoningEffort ?? DEFAULT_REASONING_EFFORT,
      summary: 'auto',
    },
    service_tier: request.serviceTier,
    store: true,
    stream: true,
    tools: [
      { type: 'web_search_preview' },
      {
        container: { type: 'auto' },
        type: 'code_interpreter',
      },
    ],
  };
};

export const parseSSELine = (line: string): { field: string; value: string } | null => {
  if (line.startsWith(':') || line.length === 0) return null;
  const colonIndex = line.indexOf(':');
  if (colonIndex === -1) return { field: line, value: '' };
  const field = line.slice(0, colonIndex);
  const value = line.slice(colonIndex + 1).replace(/^ /, '');
  return { field, value };
};

export const substringByCharacterRange = (
  text: string,
  startIndex: number,
  endIndex: number,
): string => {
  if (text.length === 0 || startIndex < 0 || endIndex <= startIndex) {
    return '';
  }

  const characters = [...text];
  if (startIndex >= characters.length) {
    return '';
  }

  const safeEndIndex = Math.min(endIndex, characters.length);
  if (safeEndIndex <= startIndex) {
    return '';
  }

  return characters.slice(startIndex, safeEndIndex).join('');
};

export const updateToolCall = (
  toolCalls: readonly LiveToolCall[],
  input: LiveToolCall,
): LiveToolCall[] => {
  return mergeToolCalls(toolCalls, [input]);
};

const toolQueriesFromEnvelope = (
  envelope: Pick<StreamEnvelope, 'queries' | 'query'>,
): readonly string[] | null => {
  if (typeof envelope.query === 'string' && envelope.query.length > 0) {
    return [envelope.query];
  }
  if (envelope.queries && envelope.queries.length > 0) {
    return [...envelope.queries];
  }
  return null;
};

export const resolveToolUpdate = (
  eventType: string,
  envelope: StreamEnvelope,
  currentToolCalls: readonly LiveToolCall[],
): LiveToolCall | null => {
  const itemId = envelope.item_id;
  if (typeof itemId !== 'string' || itemId.length === 0) {
    return null;
  }

  const current = currentToolCalls.find((toolCall) => toolCall.id === itemId) ?? {
    code: null,
    id: itemId,
    queries: toolQueriesFromEnvelope(envelope),
    results: null,
    status: 'in_progress',
    type: 'web_search',
  };

  switch (eventType) {
    case 'response.web_search_call.in_progress':
      return { ...current, status: 'in_progress', type: 'web_search' };
    case 'response.web_search_call.searching':
      return {
        ...current,
        queries: toolQueriesFromEnvelope(envelope) ?? current.queries,
        status: 'searching',
        type: 'web_search',
      };
    case 'response.web_search_call.completed':
      return {
        ...current,
        queries: toolQueriesFromEnvelope(envelope) ?? current.queries,
        status: 'completed',
        type: 'web_search',
      };

    case 'response.code_interpreter_call.in_progress':
      return { ...current, status: 'in_progress', type: 'code_interpreter' };
    case 'response.code_interpreter_call.interpreting':
      return { ...current, status: 'interpreting', type: 'code_interpreter' };
    case 'response.code_interpreter_call_code.delta':
    case 'response.code_interpreter_call.code.delta':
      return {
        ...current,
        code: `${current.code ?? ''}${envelope.delta ?? ''}`,
        status: 'interpreting',
        type: 'code_interpreter',
      };
    case 'response.code_interpreter_call_code.done':
    case 'response.code_interpreter_call.code.done':
      return {
        ...current,
        code: envelope.code ?? current.code,
        status: 'interpreting',
        type: 'code_interpreter',
      };
    case 'response.code_interpreter_call.completed':
      return { ...current, status: 'completed', type: 'code_interpreter' };

    case 'response.file_search_call.in_progress':
      return { ...current, status: 'in_progress', type: 'file_search' };
    case 'response.file_search_call.searching':
      return {
        ...current,
        queries: toolQueriesFromEnvelope(envelope) ?? current.queries,
        status: 'file_searching',
        type: 'file_search',
      };
    case 'response.file_search_call.completed':
      return {
        ...current,
        queries: toolQueriesFromEnvelope(envelope) ?? current.queries,
        status: 'completed',
        type: 'file_search',
      };
    default:
      return null;
  }
};
