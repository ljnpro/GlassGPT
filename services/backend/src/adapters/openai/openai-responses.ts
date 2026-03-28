const DEFAULT_CHAT_MODEL = 'gpt-5.4';
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 3;
const RETRYABLE_STATUS_CODES = new Set([429, 500, 502, 503, 504]);

interface ResponsesApiBody {
  readonly output?: ReadonlyArray<{
    readonly content?: ReadonlyArray<{
      readonly text?: string;
      readonly type?: string;
    }>;
    readonly type?: string;
  }>;
  readonly output_text?: string;
}

interface StreamEvent {
  readonly type: string;
  readonly data?: string;
  readonly delta?: string;
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

const extractOutputText = (body: ResponsesApiBody): string | null => {
  if (typeof body.output_text === 'string' && body.output_text.length > 0) {
    return body.output_text;
  }

  const parts =
    body.output?.flatMap((item) => {
      return (
        item.content?.flatMap((contentPart) => {
          return typeof contentPart.text === 'string' && contentPart.text.length > 0
            ? [contentPart.text]
            : [];
        }) ?? []
      );
    }) ?? [];

  return parts.length > 0 ? parts.join('') : null;
};

const fetchWithRetry = async (
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> => {
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const response = await fetch(url, { ...init, signal: controller.signal });
      clearTimeout(timeoutId);

      if (response.ok) {
        return response;
      }

      const retryAfter = parseRetryAfter(response);
      const error = new OpenAiApiError(
        await response.text().then((t) => (t.length > 0 ? t : `openai_status_${response.status}`)),
        response.status,
        retryAfter,
      );

      if (!error.isRetryable || attempt === MAX_RETRIES) {
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

export const createChatCompletion = async (apiKey: string, input: string): Promise<string> => {
  const response = await fetchWithRetry(
    'https://api.openai.com/v1/responses',
    {
      body: JSON.stringify({
        input,
        model: DEFAULT_CHAT_MODEL,
      }),
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      method: 'POST',
    },
    DEFAULT_TIMEOUT_MS,
  );

  const responseBody = (await response.json()) as ResponsesApiBody;
  const outputText = extractOutputText(responseBody);
  if (!outputText) {
    throw new Error('openai_response_missing_output_text');
  }

  return outputText;
};

const parseSSELine = (line: string): { field: string; value: string } | null => {
  if (line.startsWith(':') || line.length === 0) return null;
  const colonIndex = line.indexOf(':');
  if (colonIndex === -1) return { field: line, value: '' };
  const field = line.slice(0, colonIndex);
  const value = line.slice(colonIndex + 1).replace(/^ /, '');
  return { field, value };
};

export async function* createStreamingChatCompletion(
  apiKey: string,
  input: string,
): AsyncGenerator<string, void, undefined> {
  const response = await fetchWithRetry(
    'https://api.openai.com/v1/responses',
    {
      body: JSON.stringify({
        input,
        model: DEFAULT_CHAT_MODEL,
        stream: true,
      }),
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      method: 'POST',
    },
    DEFAULT_TIMEOUT_MS,
  );

  if (!response.body) {
    throw new Error('openai_streaming_no_body');
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let eventData = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        const parsed = parseSSELine(line);
        if (!parsed) {
          if (line === '' && eventData.length > 0) {
            if (eventData === '[DONE]') return;

            try {
              const event = JSON.parse(eventData) as StreamEvent;
              if (event.type === 'response.output_text.delta' && event.delta) {
                yield event.delta;
              }
            } catch {
              // Skip unparseable events
            }
            eventData = '';
          }
          continue;
        }

        if (parsed.field === 'data') {
          eventData = parsed.value;
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}
