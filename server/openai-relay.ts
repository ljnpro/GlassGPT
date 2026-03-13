import { setTimeout as sleep } from "node:timers/promises";
import type { Server } from "socket.io";
import {
  DEFAULT_FINAL_RESPONSE_INCLUDES,
  type CancelBackgroundRunArgs,
  type OpenAIStreamEvent,
  type RelayErrorCode,
  type RelayErrorPayload,
  type RelayEventEnvelope,
  type RelayFileUploadResponse,
  type RelayRun,
  type RelayRunStartRequest,
  type ResumeBackgroundStreamArgs,
  type RetrieveFinalResponseArgs,
  type StartBackgroundStreamArgs,
  type UploadFileArgs,
  isTerminalStatus,
  relayRunRoom,
} from "./relay-types";
import { RelayRunLimitError, RelayStore, RelayStoreError } from "./relay-store";
import { extractResponseId } from "./openai-event-normalizer";

type ParsedSSEMessage = {
  event?: string;
  data: string;
};

type StreamMode = "start" | "resume";

type StreamLoopState =
  | {
      mode: "start";
      apiKey: string;
      relayRunId: string;
      request: RelayRunStartRequest;
    }
  | {
      mode: "resume";
      apiKey: string;
      relayRunId: string;
      responseId: string;
      startingAfter: number;
    };

type ConsumeOutcome = {
  sawTerminalEvent: boolean;
};

type ParsedOpenAIError = {
  status: number;
  code: RelayErrorCode;
  message: string;
  retryable: boolean;
};

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

function isRetryableResumeStatus(status: number): boolean {
  return status === 408 || status === 409 || status === 425 || status === 429 || status >= 500;
}

function isRetryableFetchError(error: unknown): boolean {
  return error instanceof TypeError;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function stringifyUnknown(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function normalizeMessage(value: string): string {
  return value.trim() || "Unknown upstream error";
}

function buildResponseCreatePayload(request: RelayRunStartRequest): Record<string, unknown> {
  const tools: Record<string, unknown>[] = [
    { type: "web_search_preview" },
    {
      type: "code_interpreter",
      container: { type: "auto" },
    },
  ];

  if (request.vectorStoreIds && request.vectorStoreIds.length > 0) {
    tools.push({
      type: "file_search",
      vector_store_ids: request.vectorStoreIds,
    });
  }

  const payload: Record<string, unknown> = {
    model: request.model,
    input: request.messages,
    stream: true,
    background: true,
    store: true,
    tools,
  };

  if (request.reasoningEffort && request.reasoningEffort !== "none") {
    payload.reasoning = {
      effort: request.reasoningEffort,
      summary: "auto",
    };
  }

  if (request.metadata && Object.keys(request.metadata).length > 0) {
    payload.metadata = request.metadata;
  }

  return payload;
}

async function parseOpenAIError(response: Response): Promise<ParsedOpenAIError> {
  let responseBody: unknown;
  let rawText = "";

  try {
    rawText = await response.text();
    responseBody = rawText ? JSON.parse(rawText) : undefined;
  } catch {
    responseBody = rawText;
  }

  const bodyRecord = asRecord(responseBody);
  const errorRecord =
    asRecord(bodyRecord?.error) ??
    (typeof responseBody === "string" ? null : bodyRecord);

  const upstreamMessage =
    (errorRecord && typeof errorRecord.message === "string" ? errorRecord.message : undefined) ??
    (typeof responseBody === "string" ? responseBody : undefined) ??
    response.statusText ??
    "OpenAI request failed";

  if (response.status === 401 || response.status === 403) {
    return {
      status: response.status,
      code: "openai_auth_error",
      message: normalizeMessage(upstreamMessage),
      retryable: false,
    };
  }

  if (response.status === 404) {
    return {
      status: response.status,
      code: "openai_not_found",
      message: normalizeMessage(upstreamMessage),
      retryable: false,
    };
  }

  if (response.status === 429) {
    return {
      status: response.status,
      code: "openai_rate_limit",
      message: normalizeMessage(upstreamMessage),
      retryable: true,
    };
  }

  if (response.status >= 400 && response.status < 500) {
    return {
      status: response.status,
      code: "openai_bad_request",
      message: normalizeMessage(upstreamMessage),
      retryable: false,
    };
  }

  return {
    status: response.status,
    code: "openai_upstream_error",
    message: normalizeMessage(upstreamMessage),
    retryable: true,
  };
}

async function parseSSEStream(
  body: ReadableStream<Uint8Array>,
  onMessage: (message: ParsedSSEMessage) => Promise<void> | void,
): Promise<void> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let eventName = "";
  let dataLines: string[] = [];

  const flush = async () => {
    if (!eventName && dataLines.length === 0) {
      return;
    }

    const data = dataLines.join("\n");
    const message: ParsedSSEMessage = {
      event: eventName || undefined,
      data,
    };

    eventName = "";
    dataLines = [];
    await onMessage(message);
  };

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true });

      while (true) {
        const newlineIndex = buffer.indexOf("\n");
        if (newlineIndex === -1) {
          break;
        }

        let line = buffer.slice(0, newlineIndex);
        buffer = buffer.slice(newlineIndex + 1);

        if (line.endsWith("\r")) {
          line = line.slice(0, -1);
        }

        if (line === "") {
          await flush();
          continue;
        }

        if (line.startsWith(":")) {
          continue;
        }

        const colonIndex = line.indexOf(":");
        const field = colonIndex === -1 ? line : line.slice(0, colonIndex);
        let valuePart = colonIndex === -1 ? "" : line.slice(colonIndex + 1);
        if (valuePart.startsWith(" ")) {
          valuePart = valuePart.slice(1);
        }

        switch (field) {
          case "event":
            eventName = valuePart;
            break;
          case "data":
            dataLines.push(valuePart);
            break;
          default:
            break;
        }
      }
    }

    buffer += decoder.decode();
    if (buffer.length > 0) {
      const trailing = buffer.trim();
      if (trailing.length > 0) {
        dataLines.push(trailing);
      }
    }

    await flush();
  } finally {
    reader.releaseLock();
  }
}

export class OpenAIRelayService {
  private readonly openAIBaseUrl: string;
  private readonly maxAutoResumeAttempts: number;

  constructor(
    private readonly store: RelayStore,
    private readonly io: Server,
    options?: {
      openAIBaseUrl?: string;
      maxAutoResumeAttempts?: number;
    },
  ) {
    this.openAIBaseUrl = (options?.openAIBaseUrl ?? process.env.OPENAI_API_BASE_URL ?? "https://api.openai.com/v1").replace(/\/+$/, "");
    this.maxAutoResumeAttempts = options?.maxAutoResumeAttempts ?? 1;
  }

  public async uploadFile(args: UploadFileArgs): Promise<RelayFileUploadResponse> {
    const formData = new FormData();
    formData.append("purpose", "user_data");
    formData.append(
      "file",
      new Blob([new Uint8Array(args.buffer)], { type: args.contentType || "application/octet-stream" }),
      args.filename,
    );

    const response = await fetch(`${this.openAIBaseUrl}/files`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${args.apiKey}`,
      },
      body: formData,
    });

    if (!response.ok) {
      const parsed = await parseOpenAIError(response);
      throw new RelayStoreError(parsed.code, parsed.message);
    }

    const json = (await response.json()) as Record<string, unknown>;
    return {
      fileId: typeof json.id === "string" ? json.id : "",
      filename: typeof json.filename === "string" ? json.filename : args.filename,
      contentType: args.contentType,
      bytes: typeof json.bytes === "number" ? json.bytes : undefined,
    };
  }

  public async startBackgroundStream(args: StartBackgroundStreamArgs): Promise<void> {
    await this.openStreamLoop({
      mode: "start",
      apiKey: args.apiKey,
      relayRunId: args.relayRunId,
      request: args.request,
    });
  }

  public async resumeBackgroundStream(args: ResumeBackgroundStreamArgs): Promise<void> {
    const run = this.store.getRun(args.relayRunId);
    if (run && isTerminalStatus(run.status)) {
      return;
    }

    await this.openStreamLoop({
      mode: "resume",
      apiKey: args.apiKey,
      relayRunId: args.relayRunId,
      responseId: args.responseId,
      startingAfter: args.startingAfter,
    });
  }

  public async cancelRun(args: CancelBackgroundRunArgs): Promise<RelayRun> {
    const run = this.store.requireRun(args.relayRunId);

    if (isTerminalStatus(run.status)) {
      return run;
    }

    if (run.responseId) {
      try {
        await this.cancelResponse(args.apiKey, run.responseId);
      } catch (error) {
        console.warn("[relay] OpenAI cancel failed", {
          relayRunId: run.relayRunId,
          responseId: run.responseId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    run.abortController?.abort();
    const updated = this.store.markTerminal(run.relayRunId, "cancelled");
    this.emitRelayDone(updated);
    return updated;
  }

  public async retrieveFinalResponse(args: RetrieveFinalResponseArgs): Promise<Record<string, unknown>> {
    const url = new URL(`${this.openAIBaseUrl}/responses/${encodeURIComponent(args.responseId)}`);
    for (const includeValue of args.include ?? DEFAULT_FINAL_RESPONSE_INCLUDES) {
      url.searchParams.append("include", includeValue);
    }

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${args.apiKey}`,
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      const parsed = await parseOpenAIError(response);
      throw new RelayStoreError(parsed.code, parsed.message);
    }

    return (await response.json()) as Record<string, unknown>;
  }

  public async cancelResponse(apiKey: string, responseId: string): Promise<Record<string, unknown>> {
    const response = await fetch(
      `${this.openAIBaseUrl}/responses/${encodeURIComponent(responseId)}/cancel`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
      },
    );

    if (!response.ok) {
      const parsed = await parseOpenAIError(response);
      throw new RelayStoreError(parsed.code, parsed.message);
    }

    return (await response.json()) as Record<string, unknown>;
  }

  private async openStreamLoop(initialState: StreamLoopState): Promise<void> {
    const existing = this.store.getRun(initialState.relayRunId);
    if (!existing) {
      throw new RelayStoreError("not_found", `Relay run not found: ${initialState.relayRunId}`);
    }
    if (existing.openaiStreamActive) {
      return;
    }
    if (isTerminalStatus(existing.status)) {
      return;
    }

    const abortController = new AbortController();
    this.store.setAbortController(initialState.relayRunId, abortController);
    this.store.setOpenAIStreamActive(initialState.relayRunId, true);

    let state = initialState;
    let autoResumeAttemptsRemaining = this.maxAutoResumeAttempts;

    try {
      while (true) {
        const currentRun = this.store.getRun(state.relayRunId);
        if (!currentRun || isTerminalStatus(currentRun.status)) {
          return;
        }

        if (state.mode === "resume") {
          this.store.setResponseId(state.relayRunId, state.responseId);
          this.store.markStatus(
            state.relayRunId,
            currentRun.status === "starting" ? "streaming" : currentRun.status,
          );
        }

        try {
          const response =
            state.mode === "start"
              ? await this.fetchCreateStream(state, abortController.signal)
              : await this.fetchResumeStream(state, abortController.signal);

          const consumeOutcome = await this.consumeSSEResponse(state.relayRunId, response);

          const latest = this.store.getRun(state.relayRunId);
          if (!latest) {
            return;
          }

          if (isTerminalStatus(latest.status)) {
            this.emitRelayDone(latest);
            return;
          }

          if (consumeOutcome.sawTerminalEvent) {
            this.emitRelayDone(latest);
            return;
          }

          if (!latest.responseId) {
            const failed = this.store.markTerminal(
              latest.relayRunId,
              "failed",
              "OpenAI stream ended before a response ID was received.",
            );
            this.emitRelayError({
              relayRunId: latest.relayRunId,
              code: "openai_stream_dropped",
              message: failed.snapshot.finalError ?? "OpenAI stream ended unexpectedly.",
              retryable: false,
            });
            this.emitRelayDone(failed);
            return;
          }

          if (autoResumeAttemptsRemaining <= 0) {
            this.store.markStreamDetached(
              latest.relayRunId,
              "OpenAI stream detached before a terminal event. Client may resume from OpenAI.",
            );
            this.emitRelayError({
              relayRunId: latest.relayRunId,
              code: "openai_stream_dropped",
              message: "OpenAI stream detached before a terminal event. Client may resume from OpenAI.",
              retryable: true,
            });
            return;
          }

          autoResumeAttemptsRemaining -= 1;
          state = {
            mode: "resume",
            apiKey: state.apiKey,
            relayRunId: latest.relayRunId,
            responseId: latest.responseId,
            startingAfter: latest.snapshot.lastSequenceNumber,
          };
          await sleep(250);
        } catch (error) {
          const latest = this.store.getRun(state.relayRunId);

          if (isAbortError(error)) {
            if (latest && latest.status === "cancelled") {
              this.emitRelayDone(latest);
            }
            return;
          }

          if (!latest) {
            throw error;
          }

          if (
            state.mode === "resume" &&
            latest.responseId &&
            autoResumeAttemptsRemaining > 0 &&
            isRetryableFetchError(error)
          ) {
            autoResumeAttemptsRemaining -= 1;
            state = {
              mode: "resume",
              apiKey: state.apiKey,
              relayRunId: latest.relayRunId,
              responseId: latest.responseId,
              startingAfter: latest.snapshot.lastSequenceNumber,
            };
            await sleep(500);
            continue;
          }

          if (state.mode === "start" && latest.responseId && autoResumeAttemptsRemaining > 0) {
            autoResumeAttemptsRemaining -= 1;
            state = {
              mode: "resume",
              apiKey: state.apiKey,
              relayRunId: latest.relayRunId,
              responseId: latest.responseId,
              startingAfter: latest.snapshot.lastSequenceNumber,
            };
            await sleep(250);
            continue;
          }

          if (state.mode === "start" && !latest.responseId) {
            const message =
              error instanceof Error ? error.message : "Failed to start OpenAI background stream.";
            const failed = this.store.markTerminal(latest.relayRunId, "failed", message);
            this.emitRelayError({
              relayRunId: failed.relayRunId,
              code: "openai_upstream_error",
              message,
              retryable: false,
            });
            this.emitRelayDone(failed);
            return;
          }

          this.store.markStreamDetached(
            latest.relayRunId,
            error instanceof Error ? error.message : "OpenAI stream detached unexpectedly.",
          );
          this.emitRelayError({
            relayRunId: latest.relayRunId,
            code: "openai_stream_dropped",
            message:
              error instanceof Error
                ? error.message
                : "OpenAI stream detached unexpectedly.",
            retryable: true,
          });
          return;
        }
      }
    } finally {
      const run = this.store.getRun(initialState.relayRunId);
      if (run?.abortController === abortController) {
        this.store.setAbortController(initialState.relayRunId, undefined);
      }
      if (this.store.getRun(initialState.relayRunId)) {
        this.store.setOpenAIStreamActive(initialState.relayRunId, false);
      }
    }
  }

  private async fetchCreateStream(
    state: Extract<StreamLoopState, { mode: "start" }>,
    signal: AbortSignal,
  ): Promise<Response> {
    const response = await fetch(`${this.openAIBaseUrl}/responses`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${state.apiKey}`,
        "Content-Type": "application/json",
        Accept: "text/event-stream",
        "X-Client-Request-Id": state.request.clientRequestId,
      },
      body: JSON.stringify(buildResponseCreatePayload(state.request)),
      signal,
    });

    if (!response.ok) {
      const parsed = await parseOpenAIError(response);
      throw new RelayStoreError(parsed.code, parsed.message);
    }

    return response;
  }

  private async fetchResumeStream(
    state: Extract<StreamLoopState, { mode: "resume" }>,
    signal: AbortSignal,
  ): Promise<Response> {
    const url = new URL(
      `${this.openAIBaseUrl}/responses/${encodeURIComponent(state.responseId)}`,
    );
    url.searchParams.set("stream", "true");
    url.searchParams.set("starting_after", String(Math.max(0, state.startingAfter)));

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${state.apiKey}`,
        "Content-Type": "application/json",
        Accept: "text/event-stream",
        "X-Client-Request-Id": `resume:${state.relayRunId}:${state.startingAfter}`,
      },
      signal,
    });

    if (!response.ok) {
      const parsed = await parseOpenAIError(response);
      if (isRetryableResumeStatus(parsed.status)) {
        throw new RelayStoreError(parsed.code, parsed.message);
      }

      const run = this.store.getRun(state.relayRunId);
      if (run) {
        this.emitRelayError({
          relayRunId: run.relayRunId,
          code: parsed.code,
          message: parsed.message,
          retryable: parsed.retryable,
        });
        this.store.markStreamDetached(run.relayRunId, parsed.message);
      }
      throw new RelayStoreError(parsed.code, parsed.message);
    }

    return response;
  }

  private async consumeSSEResponse(relayRunId: string, response: Response): Promise<ConsumeOutcome> {
    if (!response.body) {
      throw new Error("OpenAI returned an empty response body for a streaming request.");
    }

    let sawTerminalEvent = false;

    await parseSSEStream(response.body, async (message) => {
      if (!message.data || message.data === "[DONE]") {
        return;
      }

      let parsed: OpenAIStreamEvent;
      try {
        parsed = JSON.parse(message.data) as OpenAIStreamEvent;
      } catch (error) {
        console.warn("[relay] failed to parse SSE JSON", {
          relayRunId,
          error: error instanceof Error ? error.message : String(error),
          payloadPreview: message.data.slice(0, 200),
        });
        return;
      }

      if (!parsed.type && message.event) {
        parsed.type = message.event;
      }

      const type = typeof parsed.type === "string" ? parsed.type : "unknown";
      const responseId = extractResponseId(parsed);
      if (responseId) {
        this.store.setResponseId(relayRunId, responseId);
      }

      if (type === "error") {
        const rawError = parsed.error ?? parsed;
        const messageText =
          (asRecord(rawError) && typeof asRecord(rawError)?.message === "string"
            ? (asRecord(rawError)!.message as string)
            : undefined) ??
          (typeof parsed.message === "string" ? parsed.message : undefined) ??
          "OpenAI streamed an error event.";

        const failed = this.store.markTerminal(relayRunId, "failed", messageText);
        this.emitRelayError({
          relayRunId,
          code: "openai_upstream_error",
          message: messageText,
          retryable: false,
        });
        this.emitRelayDone(failed);
        sawTerminalEvent = true;
        return;
      }

      try {
        const result = this.store.ingestOpenAIEvent(relayRunId, parsed);
        if (result.isDuplicate) {
          return;
        }

        const liveEnvelope: RelayEventEnvelope = {
          relayRunId,
          sequenceNumber: result.cachedEvent?.sequenceNumber ?? result.run.snapshot.lastSequenceNumber ?? 0,
          replay: false,
          event: parsed,
        };

        this.io.to(relayRunRoom(relayRunId)).emit("relay:event", liveEnvelope);

        if (result.becameTerminal || isTerminalStatus(result.run.status)) {
          sawTerminalEvent = true;
          this.emitRelayDone(result.run);
        }
      } catch (error) {
        if (error instanceof RelayRunLimitError) {
          const failed = this.store.markTerminal(relayRunId, "failed", error.message);
          this.emitRelayError({
            relayRunId,
            code: "cache_limit_exceeded",
            message: error.message,
            retryable: false,
          });
          this.emitRelayDone(failed);
          sawTerminalEvent = true;
          return;
        }
        throw error;
      }
    });

    return { sawTerminalEvent };
  }

  private emitRelayDone(run: RelayRun): void {
    this.io.to(relayRunRoom(run.relayRunId)).emit("relay:done", {
      relayRunId: run.relayRunId,
      status: run.status,
      responseId: run.responseId,
      lastSequenceNumber: run.snapshot.lastSequenceNumber,
    });
  }

  private emitRelayError(payload: RelayErrorPayload): void {
    if (!payload.relayRunId) {
      return;
    }
    this.io.to(relayRunRoom(payload.relayRunId)).emit("relay:error", payload);
  }
}
