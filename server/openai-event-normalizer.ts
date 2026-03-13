import type { OpenAIStreamEvent, RelayRunStatus, RelaySnapshot } from "./relay-types";

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function maybeString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function maybeNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function toolKeyFromRecord(record: Record<string, unknown>): string {
  return (
    maybeString(record.id) ??
    maybeString(record.call_id) ??
    maybeString(record.item_id) ??
    (typeof record.output_index === "number" ? `output:${record.output_index}` : undefined) ??
    `tool:${Math.random().toString(36).slice(2)}`
  );
}

function pushUniqueAnnotation(annotations: unknown[], annotation: unknown): void {
  const serialized = safeStringify(annotation);
  if (!annotations.some((existing) => safeStringify(existing) === serialized)) {
    annotations.push(annotation);
  }
}

function safeStringify(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function extractErrorMessageFromEvent(event: OpenAIStreamEvent): string | undefined {
  const errorRecord = asRecord(event.error) ?? asRecord(event.response?.error);
  return (
    (errorRecord && maybeString(errorRecord.message)) ??
    maybeString(event.message) ??
    undefined
  );
}

function collectContentPart(
  part: Record<string, unknown>,
  textParts: string[],
  thinkingParts: string[],
  annotations: unknown[],
): void {
  const type = maybeString(part.type) ?? "";

  if (
    (type === "output_text" || type === "text" || type === "response.output_text") &&
    typeof part.text === "string"
  ) {
    textParts.push(part.text);
  }

  if (
    (type === "reasoning_text" || type === "reasoning_summary_text" || type === "reasoning") &&
    typeof part.text === "string"
  ) {
    thinkingParts.push(part.text);
  }

  for (const annotation of asArray(part.annotations)) {
    pushUniqueAnnotation(annotations, annotation);
  }
}

function collectResponseSummary(responseRecord: Record<string, unknown>): {
  text: string;
  thinking: string;
  annotations: unknown[];
  toolCalls: Record<string, unknown>;
} {
  const textParts: string[] = [];
  const thinkingParts: string[] = [];
  const annotations: unknown[] = [];
  const toolCalls: Record<string, unknown> = {};

  const directOutputText = maybeString(responseRecord.output_text);
  if (directOutputText) {
    textParts.push(directOutputText);
  }

  for (const outputItem of asArray(responseRecord.output)) {
    const item = asRecord(outputItem);
    if (!item) {
      continue;
    }

    const itemType = maybeString(item.type) ?? "";

    if (itemType === "message") {
      for (const contentItem of asArray(item.content)) {
        const part = asRecord(contentItem);
        if (!part) continue;
        collectContentPart(part, textParts, thinkingParts, annotations);
      }
      continue;
    }

    if (itemType === "reasoning") {
      if (typeof item.text === "string") {
        thinkingParts.push(item.text);
      }
      for (const summaryItem of asArray(item.summary)) {
        const part = asRecord(summaryItem);
        if (!part) continue;
        if (typeof part.text === "string") {
          thinkingParts.push(part.text);
        }
      }
      continue;
    }

    if (
      itemType.endsWith("_call") ||
      itemType === "function_call" ||
      itemType === "computer_call" ||
      itemType === "computer_use_call"
    ) {
      toolCalls[toolKeyFromRecord(item)] = item;
    }
  }

  return {
    text: textParts.join(""),
    thinking: thinkingParts.join(""),
    annotations,
    toolCalls,
  };
}

function statusFromOpenAIValue(value: string | undefined): RelayRunStatus | undefined {
  switch (value) {
    case "completed":
      return "completed";
    case "in_progress":
    case "queued":
      return "streaming";
    case "incomplete":
      return "incomplete";
    case "cancelled":
      return "cancelled";
    case "failed":
      return "failed";
    default:
      return undefined;
  }
}

export function extractSequenceNumber(event: OpenAIStreamEvent): number | undefined {
  return maybeNumber(event.sequence_number);
}

export function extractResponseId(event: OpenAIStreamEvent): string | undefined {
  const nestedResponse = asRecord(event.response);
  return maybeString(event.response_id) ?? maybeString(nestedResponse?.id);
}

export function isTerminalEvent(eventType: string | undefined): boolean {
  return (
    eventType === "response.completed" ||
    eventType === "response.failed" ||
    eventType === "response.incomplete" ||
    eventType === "response.cancelled" ||
    eventType === "response.done" ||
    eventType === "error"
  );
}

export function applyEventToSnapshot(snapshot: RelaySnapshot, event: OpenAIStreamEvent): void {
  const type = maybeString(event.type) ?? "";
  const nestedResponse = asRecord(event.response);
  const responseId = extractResponseId(event);
  const errorMessage = extractErrorMessageFromEvent(event);

  if (responseId) {
    snapshot.responseId = responseId;
  }

  const nestedStatus = statusFromOpenAIValue(maybeString(nestedResponse?.status));
  if (nestedStatus) {
    snapshot.status = nestedStatus;
  }

  switch (type) {
    case "response.created":
    case "response.in_progress":
      snapshot.status = "streaming";
      break;
    case "response.completed":
      snapshot.status = "completed";
      break;
    case "response.incomplete":
      snapshot.status = "incomplete";
      break;
    case "response.failed":
    case "error":
      snapshot.status = "failed";
      break;
    case "response.cancelled":
      snapshot.status = "cancelled";
      break;
    default:
      break;
  }

  if (type === "response.output_text.delta" && typeof event.delta === "string") {
    snapshot.accumulatedText += event.delta;
  }

  if (
    (type === "response.reasoning_summary_text.delta" || type === "response.reasoning_text.delta") &&
    typeof event.delta === "string"
  ) {
    snapshot.accumulatedThinking += event.delta;
  }

  if (
    (type === "response.reasoning_summary_text.done" || type === "response.reasoning_text.done") &&
    typeof event.text === "string" &&
    !snapshot.accumulatedThinking
  ) {
    snapshot.accumulatedThinking = event.text;
  }

  if (type === "response.output_text.annotation.added") {
    const annotation = asRecord(event.annotation) ?? asRecord(event.url_citation);
    if (annotation) {
      pushUniqueAnnotation(snapshot.annotations, annotation);
    }
  }

  const partRecord = asRecord(event.part);
  if (partRecord) {
    for (const annotation of asArray(partRecord.annotations)) {
      pushUniqueAnnotation(snapshot.annotations, annotation);
    }
    if (
      (maybeString(partRecord.type) === "reasoning_summary_text" ||
        maybeString(partRecord.type) === "reasoning_text") &&
      typeof partRecord.text === "string"
    ) {
      snapshot.accumulatedThinking += partRecord.text;
    }
  }

  const itemRecord = asRecord(event.item);
  if (itemRecord) {
    const itemType = maybeString(itemRecord.type) ?? "";
    if (
      itemType.endsWith("_call") ||
      itemType === "function_call" ||
      itemType === "computer_call" ||
      itemType === "computer_use_call"
    ) {
      snapshot.toolCalls[toolKeyFromRecord(itemRecord)] = itemRecord;
    }

    if (itemType === "message") {
      const collected = collectResponseSummary({
        output: [itemRecord],
      });
      for (const annotation of collected.annotations) {
        pushUniqueAnnotation(snapshot.annotations, annotation);
      }
      if (collected.text && !snapshot.accumulatedText) {
        snapshot.accumulatedText = collected.text;
      }
      if (collected.thinking && !snapshot.accumulatedThinking) {
        snapshot.accumulatedThinking = collected.thinking;
      }
    }
  }

  if (
    /^response\.(web_search_call|code_interpreter_call|file_search_call)\./.test(type) ||
    /^response\.(function_call_arguments|function_call)\./.test(type)
  ) {
    const key =
      maybeString(event.item_id) ??
      maybeString(event.call_id) ??
      (typeof event.output_index === "number" ? `output:${event.output_index}` : undefined) ??
      type;
    snapshot.toolCalls[key] = event;
  }

  if (nestedResponse) {
    const summary = collectResponseSummary(nestedResponse);
    if (summary.text) {
      snapshot.accumulatedText = summary.text;
    }
    if (summary.thinking) {
      snapshot.accumulatedThinking = summary.thinking;
    }
    for (const annotation of summary.annotations) {
      pushUniqueAnnotation(snapshot.annotations, annotation);
    }
    Object.assign(snapshot.toolCalls, summary.toolCalls);
  }

  if (errorMessage) {
    snapshot.finalError = errorMessage;
  }

  const sequenceNumber = extractSequenceNumber(event);
  if (typeof sequenceNumber === "number") {
    snapshot.lastSequenceNumber = Math.max(snapshot.lastSequenceNumber, sequenceNumber);
  }
}
