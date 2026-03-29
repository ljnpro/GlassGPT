import type {
  LiveCitation,
  LiveFilePathAnnotation,
  LiveStreamEvent,
  LiveToolCall,
  StreamingConversationMessage,
  StreamingConversationRequest,
} from '../../application/live-stream-model.js';
import { logError, sanitizeLogValue } from '../../observability/logger.js';
import { openAiCircuitBreakerKey, openAiCircuitBreakers } from './circuit-breaker.js';
import {
  extractCitations,
  extractErrorMessage,
  extractFilePathAnnotations,
  extractOutputText,
  extractReasoningText,
  extractToolCalls,
  mergeCitations,
  mergeFilePathAnnotations,
  mergeToolCalls,
  type ResponsesResponse,
} from './openai-response-extraction.js';

const DEFAULT_CHAT_MODEL = 'gpt-5.4';
const DEFAULT_REASONING_EFFORT = 'medium';
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 3;

const timeoutForModel = (model: string): number => {
  if (model.includes('pro') || model.includes('deep')) return 300_000;
  if (model.includes('mini') || model.includes('fast')) return 60_000;
  return DEFAULT_TIMEOUT_MS;
};
const RETRYABLE_STATUS_CODES = new Set([429, 500, 502, 503, 504]);

interface StreamEnvelope {
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

interface ResponsesApiBody extends ResponsesResponse {}

interface ResponsesApiInputMessage {
  readonly content:
    | string
    | ReadonlyArray<{
        readonly text: string;
        readonly type: 'input_text';
      }>;
  readonly role: StreamingConversationMessage['role'];
}

export class OpenAiApiError extends Error {
  constructor(
    message: string,
    readonly statusCode: number,
    readonly retryAfterSeconds: number | null,
  ) {
    super(message);
    this.name = 'OpenAiApiError';
  }

  get isRetryable(): boolean {
    return RETRYABLE_STATUS_CODES.has(this.statusCode);
  }
}

const parseRetryAfter = (response: Response): number | null => {
  const header = response.headers.get('retry-after');
  if (!header) return null;
  const seconds = Number.parseInt(header, 10);
  return Number.isFinite(seconds) && seconds > 0 ? seconds : null;
};

const backoffDelay = (attempt: number, retryAfterSeconds: number | null): number => {
  if (retryAfterSeconds !== null) {
    return retryAfterSeconds * 1000;
  }
  const baseMs = 1000 * 2 ** attempt;
  const jitter = Math.random() * 500;
  return baseMs + jitter;
};

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

const fetchWithRetry = async (
  url: string,
  init: RequestInit,
  breakerKey: string,
  timeoutMs: number,
): Promise<Response> => {
  const breaker = openAiCircuitBreakers.breakerFor(breakerKey);
  if (breaker.isOpen) {
    throw new OpenAiApiError('circuit_breaker_open', 503, null);
  }

  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const response = await fetch(url, { ...init, signal: controller.signal });
      clearTimeout(timeoutId);

      if (response.ok) {
        breaker.recordSuccess();
        return response;
      }

      const retryAfter = parseRetryAfter(response);
      const error = new OpenAiApiError(
        await response
          .text()
          .then((text) => (text.length > 0 ? text : `openai_status_${response.status}`)),
        response.status,
        retryAfter,
      );

      if (!error.isRetryable || attempt === MAX_RETRIES) {
        breaker.recordFailure();
        throw error;
      }

      lastError = error;
      await sleep(backoffDelay(attempt, retryAfter));
    } catch (error) {
      clearTimeout(timeoutId);

      if (error instanceof OpenAiApiError) {
        throw error;
      }

      if (attempt === MAX_RETRIES) {
        throw error instanceof Error ? error : new Error(String(error));
      }

      lastError = error instanceof Error ? error : new Error(String(error));
      await sleep(backoffDelay(attempt, null));
    }
  }

  throw lastError ?? new Error('openai_retry_exhausted');
};

const buildInputMessages = (
  input: string | readonly StreamingConversationMessage[],
): string | ResponsesApiInputMessage[] => {
  if (typeof input === 'string') {
    return input;
  }

  return input.map((message) => ({
    content: [{ text: message.content, type: 'input_text' }],
    role: message.role,
  }));
};

const buildRequestBody = (request: StreamingConversationRequest) => {
  return {
    input: buildInputMessages(request.input),
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

const parseSSELine = (line: string): { field: string; value: string } | null => {
  if (line.startsWith(':') || line.length === 0) return null;
  const colonIndex = line.indexOf(':');
  if (colonIndex === -1) return { field: line, value: '' };
  const field = line.slice(0, colonIndex);
  const value = line.slice(colonIndex + 1).replace(/^ /, '');
  return { field, value };
};

const substringByCharacterRange = (text: string, startIndex: number, endIndex: number): string => {
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

const updateToolCall = (
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

const resolveToolUpdate = (
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

export const createChatCompletion = async (
  apiKey: string,
  input: string | readonly StreamingConversationMessage[],
): Promise<string> => {
  const breakerKey = openAiCircuitBreakerKey({
    apiKey,
    model: DEFAULT_CHAT_MODEL,
    serviceTier: 'default',
  });
  const response = await fetchWithRetry(
    'https://api.openai.com/v1/responses',
    {
      body: JSON.stringify({
        ...buildRequestBody({ input }),
        stream: false,
      }),
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      method: 'POST',
    },
    breakerKey,
    timeoutForModel(DEFAULT_CHAT_MODEL),
  );

  const responseBody = (await response.json()) as ResponsesApiBody;
  const outputText = extractOutputText(responseBody);
  if (!outputText) {
    throw new Error('openai_response_missing_output_text');
  }

  return outputText;
};

export async function* createStreamingResponse(
  apiKey: string,
  request: StreamingConversationRequest,
): AsyncGenerator<LiveStreamEvent, void, undefined> {
  const breakerKey = openAiCircuitBreakerKey({
    apiKey,
    model: request.model ?? DEFAULT_CHAT_MODEL,
    serviceTier: request.serviceTier ?? 'default',
  });
  const response = await fetchWithRetry(
    'https://api.openai.com/v1/responses',
    {
      body: JSON.stringify(buildRequestBody(request)),
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      method: 'POST',
    },
    breakerKey,
    timeoutForModel(request.model ?? DEFAULT_CHAT_MODEL),
  );

  if (!response.body) {
    throw new Error('openai_streaming_no_body');
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let eventData = '';
  let currentOutputText = '';
  let currentThinkingText = '';
  let citations: LiveCitation[] = [];
  let filePathAnnotations: LiveFilePathAnnotation[] = [];
  let toolCalls: LiveToolCall[] = [];

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        const parsedLine = parseSSELine(line);
        if (!parsedLine) {
          if (line === '' && eventData.length > 0) {
            if (eventData === '[DONE]') {
              return;
            }

            try {
              const event = JSON.parse(eventData) as StreamEnvelope;
              switch (event.type) {
                case 'response.created': {
                  const responseId = event.response?.id;
                  if (typeof responseId === 'string' && responseId.length > 0) {
                    yield { kind: 'response_created', responseId };
                  }
                  break;
                }

                case 'response.output_text.delta': {
                  if (typeof event.delta === 'string' && event.delta.length > 0) {
                    currentOutputText += event.delta;
                    yield { kind: 'text_delta', textDelta: event.delta };
                  }
                  break;
                }

                case 'response.reasoning_summary_text.delta':
                case 'response.reasoning_text.delta': {
                  if (typeof event.delta === 'string' && event.delta.length > 0) {
                    currentThinkingText += event.delta;
                    yield { kind: 'thinking_delta', thinkingDelta: event.delta };
                  }
                  break;
                }

                case 'response.reasoning_summary_text.done':
                case 'response.reasoning_text.done':
                  yield { kind: 'thinking_finished' };
                  break;

                case 'response.output_text.annotation.added': {
                  const annotation = event.annotation;
                  if (!annotation) {
                    break;
                  }

                  if (
                    annotation.type === 'url_citation' &&
                    typeof annotation.url === 'string' &&
                    typeof annotation.title === 'string'
                  ) {
                    const citation: LiveCitation = {
                      endIndex: annotation.end_index ?? 0,
                      startIndex: annotation.start_index ?? 0,
                      title: annotation.title,
                      url: annotation.url,
                    };
                    citations = mergeCitations(citations, [citation]);
                    yield { citation, kind: 'citation_added' };
                    break;
                  }

                  if (
                    (annotation.type === 'file_path' ||
                      annotation.type === 'container_file_citation') &&
                    typeof annotation.file_id === 'string' &&
                    annotation.file_id.length > 0
                  ) {
                    const startIndex = annotation.start_index ?? 0;
                    const endIndex = annotation.end_index ?? 0;
                    const filePathAnnotation: LiveFilePathAnnotation = {
                      containerId: annotation.container_id ?? null,
                      endIndex,
                      fileId: annotation.file_id,
                      filename: annotation.filename ?? null,
                      sandboxPath: substringByCharacterRange(
                        currentOutputText,
                        startIndex,
                        endIndex,
                      ),
                      startIndex,
                    };
                    filePathAnnotations = mergeFilePathAnnotations(filePathAnnotations, [
                      filePathAnnotation,
                    ]);
                    yield { annotation: filePathAnnotation, kind: 'file_path_annotation_added' };
                  }
                  break;
                }

                case 'response.web_search_call.in_progress':
                case 'response.web_search_call.searching':
                case 'response.web_search_call.completed':
                case 'response.code_interpreter_call.in_progress':
                case 'response.code_interpreter_call.interpreting':
                case 'response.code_interpreter_call_code.delta':
                case 'response.code_interpreter_call_code.done':
                case 'response.code_interpreter_call.code.delta':
                case 'response.code_interpreter_call.code.done':
                case 'response.code_interpreter_call.completed':
                case 'response.file_search_call.in_progress':
                case 'response.file_search_call.searching':
                case 'response.file_search_call.completed': {
                  const toolCall = resolveToolUpdate(event.type, event, toolCalls);
                  if (!toolCall) {
                    break;
                  }
                  toolCalls = updateToolCall(toolCalls, toolCall);
                  yield { kind: 'tool_call_updated', toolCall };
                  break;
                }

                case 'response.completed':
                case 'response.incomplete': {
                  const terminalResponse = event.response ?? {};
                  currentOutputText = extractOutputText(terminalResponse) || currentOutputText;
                  currentThinkingText =
                    extractReasoningText(terminalResponse) ?? currentThinkingText;
                  citations = mergeCitations(citations, extractCitations(terminalResponse));
                  filePathAnnotations = mergeFilePathAnnotations(
                    filePathAnnotations,
                    extractFilePathAnnotations(terminalResponse),
                  );
                  toolCalls = mergeToolCalls(toolCalls, extractToolCalls(terminalResponse));

                  if (event.type === 'response.completed') {
                    yield {
                      citations,
                      filePathAnnotations,
                      kind: 'completed',
                      outputText: currentOutputText,
                      thinkingText: currentThinkingText || null,
                      toolCalls,
                    };
                    return;
                  }

                  yield {
                    citations,
                    errorMessage: extractErrorMessage(terminalResponse),
                    filePathAnnotations,
                    kind: 'incomplete',
                    outputText: currentOutputText,
                    thinkingText: currentThinkingText || null,
                    toolCalls,
                  };
                  return;
                }

                case 'response.failed':
                case 'error': {
                  const terminalMessage =
                    event.response?.error?.message ??
                    event.error?.message ??
                    event.message ??
                    'openai_stream_failed';
                  yield { errorMessage: terminalMessage, kind: 'failed' };
                  return;
                }

                default:
                  break;
              }
            } catch (error) {
              logError('openai_stream_event_decode_failed', {
                errorMessage:
                  error instanceof Error ? sanitizeLogValue(error.message) : 'unknown_error',
                rawEvent: sanitizeLogValue(eventData),
              });
            }

            eventData = '';
          }
          continue;
        }

        if (parsedLine.field === 'data') {
          eventData = parsedLine.value;
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}

export async function* createStreamingChatCompletion(
  apiKey: string,
  input: string | readonly StreamingConversationMessage[],
): AsyncGenerator<string, void, undefined> {
  let emittedTextDelta = false;

  for await (const event of createStreamingResponse(apiKey, { input })) {
    switch (event.kind) {
      case 'text_delta':
        emittedTextDelta = true;
        yield event.textDelta;
        break;

      case 'completed':
      case 'incomplete':
        if (!emittedTextDelta && event.outputText.length > 0) {
          yield event.outputText;
        }
        return;

      case 'failed':
        throw new Error(event.errorMessage);

      default:
        break;
    }
  }
}
