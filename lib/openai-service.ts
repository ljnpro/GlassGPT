import {
  ImageAttachment,
  Message,
  ModelId,
  ReasoningEffort,
  ResponseUsage,
  normalizeReasoningEffort,
} from "./types";

const RESPONSES_API_URL = "https://api.openai.com/v1/responses";
const MODELS_API_URL = "https://api.openai.com/v1/models";
const DEFAULT_MAX_OUTPUT_TOKENS = 16000;

export interface StreamCompletionResult {
  outputText: string;
  reasoning: string;
  usage?: ResponseUsage;
  responseId?: string;
  error?: string;
}

interface StreamCallbacks {
  onToken: (text: string) => void;
  onReasoning?: (text: string) => void;
  onDone?: (result?: StreamCompletionResult) => void;
  onError: (error: string) => void;
}

interface SseBlock {
  event: string;
  data: string;
}

function normalizeUsage(value: unknown): ResponseUsage | undefined {
  if (!value || typeof value !== "object") {
    return undefined;
  }

  const usage = value as Record<string, unknown>;
  const outputTokenDetails =
    usage.output_tokens_details && typeof usage.output_tokens_details === "object"
      ? (usage.output_tokens_details as Record<string, unknown>)
      : undefined;
  const inputTokenDetails =
    usage.input_tokens_details && typeof usage.input_tokens_details === "object"
      ? (usage.input_tokens_details as Record<string, unknown>)
      : undefined;

  const normalized: ResponseUsage = {};

  if (typeof usage.input_tokens === "number") {
    normalized.inputTokens = usage.input_tokens;
  }

  if (typeof usage.output_tokens === "number") {
    normalized.outputTokens = usage.output_tokens;
  }

  if (typeof usage.total_tokens === "number") {
    normalized.totalTokens = usage.total_tokens;
  }

  if (typeof outputTokenDetails?.reasoning_tokens === "number") {
    normalized.reasoningTokens = outputTokenDetails.reasoning_tokens;
  } else if (typeof usage.reasoning_tokens === "number") {
    normalized.reasoningTokens = usage.reasoning_tokens;
  }

  if (typeof inputTokenDetails?.cached_tokens === "number") {
    normalized.cachedInputTokens = inputTokenDetails.cached_tokens;
  } else if (typeof usage.cached_input_tokens === "number") {
    normalized.cachedInputTokens = usage.cached_input_tokens;
  }

  if (
    normalized.inputTokens === undefined &&
    normalized.outputTokens === undefined &&
    normalized.totalTokens === undefined &&
    normalized.reasoningTokens === undefined &&
    normalized.cachedInputTokens === undefined
  ) {
    return undefined;
  }

  return normalized;
}

function normalizeError(error: unknown): string {
  if (typeof error === "string" && error.trim().length > 0) {
    return error.trim();
  }

  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message.trim();
  }

  return "Unknown error";
}

function imageToInputUrl(image: ImageAttachment): string {
  if (image.base64 && image.base64.length > 0) {
    const mimeType = image.mimeType || "image/jpeg";
    return `data:${mimeType};base64,${image.base64}`;
  }

  return image.uri;
}

function buildResponsesInput(messages: Message[]): Array<Record<string, unknown>> {
  const result: Array<Record<string, unknown>> = [];
  for (const message of messages) {
    if (message.role === "user" && message.images && message.images.length > 0) {
      const content: Array<Record<string, unknown>> = [];

      if (message.content.trim().length > 0) {
        content.push({
          type: "input_text",
          text: message.content,
        });
      }

      for (const image of message.images) {
        content.push({
          type: "input_image",
          image_url: imageToInputUrl(image),
        });
      }

      if (content.length > 0) {
        result.push({ role: "user", content });
      }
    } else if (message.content.trim().length > 0) {
      result.push({
        role: message.role as string,
        content: message.content,
      });
    }
  }
  return result;
}

function parseSseBlock(block: string): SseBlock | null {
  const lines = block.split("\n");
  let eventName = "";
  const dataLines: string[] = [];

  for (const rawLine of lines) {
    const line = rawLine.trimEnd();

    if (!line || line.startsWith(":")) {
      continue;
    }

    if (line.startsWith("event:")) {
      eventName = line.slice(6).trim();
      continue;
    }

    if (line.startsWith("data:")) {
      dataLines.push(line.slice(5).trimStart());
    }
  }

  if (!eventName && dataLines.length === 0) {
    return null;
  }

  return {
    event: eventName,
    data: dataLines.join("\n"),
  };
}

function extractResponseText(payload: unknown): string {
  if (!payload || typeof payload !== "object") {
    return "";
  }

  const record = payload as Record<string, unknown>;

  if (typeof record.output_text === "string") {
    return record.output_text;
  }

  if (!Array.isArray(record.output)) {
    return "";
  }

  const parts: string[] = [];

  for (const outputItem of record.output) {
    if (!outputItem || typeof outputItem !== "object") {
      continue;
    }

    const outputRecord = outputItem as Record<string, unknown>;

    if (!Array.isArray(outputRecord.content)) {
      continue;
    }

    for (const contentPart of outputRecord.content) {
      if (!contentPart || typeof contentPart !== "object") {
        continue;
      }

      const contentRecord = contentPart as Record<string, unknown>;
      const type = typeof contentRecord.type === "string" ? contentRecord.type : "";

      if ((type === "output_text" || type === "text") && typeof contentRecord.text === "string") {
        parts.push(contentRecord.text);
      }
    }
  }

  return parts.join("");
}

async function readErrorMessageFromResponse(response: Response): Promise<string> {
  try {
    const rawText = await response.text();

    if (!rawText) {
      return `API Error ${response.status}`;
    }

    try {
      const parsed = JSON.parse(rawText) as Record<string, unknown>;
      const errorObject =
        parsed.error && typeof parsed.error === "object"
          ? (parsed.error as Record<string, unknown>)
          : undefined;

      if (typeof errorObject?.message === "string" && errorObject.message.trim().length > 0) {
        return errorObject.message.trim();
      }

      if (typeof parsed.message === "string" && parsed.message.trim().length > 0) {
        return parsed.message.trim();
      }
    } catch {
      if (rawText.trim().length > 0) {
        return rawText.trim();
      }
    }
  } catch {
    return `API Error ${response.status}`;
  }

  return `API Error ${response.status}`;
}

function sanitizeGeneratedTitle(title: string): string {
  const singleLine = title
    .replace(/\s+/g, " ")
    .replace(/^["'`]+|["'`]+$/g, "")
    .trim();

  if (!singleLine) {
    return "New Chat";
  }

  if (singleLine.length <= 60) {
    return singleLine;
  }

  return `${singleLine.slice(0, 57).trim()}…`;
}

export async function streamChatCompletion(
  apiKey: string,
  messages: Message[],
  model: ModelId,
  effort: ReasoningEffort,
  callbacks: StreamCallbacks,
  abortSignal?: AbortSignal
): Promise<StreamCompletionResult> {
  const normalizedEffort = normalizeReasoningEffort(model, effort);
  const requestBody: Record<string, unknown> = {
    model,
    input: buildResponsesInput(messages),
    reasoning: { effort: normalizedEffort },
    stream: true,
    max_output_tokens: DEFAULT_MAX_OUTPUT_TOKENS,
  };

  const result: StreamCompletionResult = {
    outputText: "",
    reasoning: "",
  };

  let didFinish = false;
  let didError = false;

  const complete = () => {
    if (didFinish || didError) {
      return;
    }

    didFinish = true;
    callbacks.onDone?.(result);
  };

  const fail = (message: string) => {
    if (didFinish || didError) {
      return;
    }

    didError = true;
    result.error = message;
    callbacks.onError(message);
  };

  const handleSsePayload = (block: SseBlock): boolean => {
    const rawData = block.data;

    if (!rawData) {
      return false;
    }

    if (rawData === "[DONE]") {
      complete();
      return true;
    }

    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(rawData) as Record<string, unknown>;
    } catch {
      return false;
    }

    const eventName =
      block.event || (typeof parsed.type === "string" ? parsed.type : "");

    if (eventName === "response.output_text.delta" || eventName === "response.refusal.delta") {
      if (typeof parsed.delta === "string") {
        result.outputText += parsed.delta;
        callbacks.onToken(result.outputText);
      }
      return false;
    }

    if (
      eventName.startsWith("response.reasoning") ||
      eventName.startsWith("response.reasoning_summary_text")
    ) {
      if (typeof parsed.delta === "string") {
        result.reasoning += parsed.delta;
        callbacks.onReasoning?.(result.reasoning);
      }
      return false;
    }

    if (eventName === "response.completed") {
      const completedResponse =
        parsed.response && typeof parsed.response === "object"
          ? (parsed.response as Record<string, unknown>)
          : parsed;

      result.responseId =
        typeof completedResponse.id === "string" ? completedResponse.id : undefined;
      result.usage = normalizeUsage(completedResponse.usage);

      if (!result.outputText) {
        result.outputText = extractResponseText(completedResponse);
      }

      complete();
      return true;
    }

    if (eventName === "response.error" || eventName === "error") {
      const errorObject =
        parsed.error && typeof parsed.error === "object"
          ? (parsed.error as Record<string, unknown>)
          : undefined;

      const message =
        (typeof errorObject?.message === "string" && errorObject.message.trim().length > 0
          ? errorObject.message.trim()
          : typeof parsed.message === "string" && parsed.message.trim().length > 0
            ? parsed.message.trim()
            : "Unknown API error");

      fail(message);
      return true;
    }

    return false;
  };

  try {
    const response = await fetch(RESPONSES_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "text/event-stream",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(requestBody),
      signal: abortSignal,
    });

    if (!response.ok) {
      fail(await readErrorMessageFromResponse(response));
      return result;
    }

    const body = response.body;

    if (!body || typeof body.getReader !== "function") {
      const rawText = await response.text();
      const normalizedText = rawText.replace(/\r\n/g, "\n");
      const blocks = normalizedText.split("\n\n");

      for (const rawBlock of blocks) {
        const parsedBlock = parseSseBlock(rawBlock);
        if (!parsedBlock) {
          continue;
        }

        const shouldStop = handleSsePayload(parsedBlock);
        if (shouldStop) {
          break;
        }
      }

      if (!didFinish && !didError) {
        complete();
      }

      return result;
    }

    const reader = body.getReader();
    const decoder = new TextDecoder("utf-8");
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();

      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true }).replace(/\r\n/g, "\n");

      let separatorIndex = buffer.indexOf("\n\n");
      while (separatorIndex !== -1) {
        const rawBlock = buffer.slice(0, separatorIndex);
        buffer = buffer.slice(separatorIndex + 2);

        const parsedBlock = parseSseBlock(rawBlock);
        if (parsedBlock) {
          const shouldStop = handleSsePayload(parsedBlock);
          if (shouldStop) {
            try {
              await reader.cancel();
            } catch {
              return result;
            }
            return result;
          }
        }

        separatorIndex = buffer.indexOf("\n\n");
      }
    }

    const trailingBlock = parseSseBlock(buffer.trim());
    if (trailingBlock) {
      handleSsePayload(trailingBlock);
    }

    if (!didFinish && !didError) {
      complete();
    }

    return result;
  } catch (error) {
    if ((error as { name?: string })?.name === "AbortError") {
      complete();
      return result;
    }

    fail(normalizeError(error));
    return result;
  }
}

export async function validateApiKey(
  apiKey: string
): Promise<{ valid: boolean; error?: string }> {
  const normalizedApiKey = apiKey.trim();

  if (!normalizedApiKey) {
    return { valid: false, error: "API key is required" };
  }

  try {
    const response = await fetch(MODELS_API_URL, {
      headers: {
        Authorization: `Bearer ${normalizedApiKey}`,
      },
    });

    if (response.ok) {
      return { valid: true };
    }

    if (response.status === 401) {
      return { valid: false, error: "Invalid API key" };
    }

    return {
      valid: false,
      error: await readErrorMessageFromResponse(response),
    };
  } catch (error) {
    return {
      valid: false,
      error: normalizeError(error),
    };
  }
}

export async function generateTitle(apiKey: string, firstMessage: string): Promise<string> {
  const trimmedMessage = firstMessage.trim();

  if (!trimmedMessage) {
    return "New Chat";
  }

  try {
    const response = await fetch(RESPONSES_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-5.4",
        input: [
          {
            role: "system",
            content:
              "Generate a very short conversation title in 2 to 6 words. Return only the title, with no quotes or punctuation decoration.",
          },
          {
            role: "user",
            content: trimmedMessage,
          },
        ],
        reasoning: {
          effort: "none",
        },
        max_output_tokens: 24,
      }),
    });

    if (!response.ok) {
      return "New Chat";
    }

    const data = (await response.json()) as Record<string, unknown>;
    const title = extractResponseText(data);

    return sanitizeGeneratedTitle(title);
  } catch {
    return "New Chat";
  }
}
