import {
  DEFAULT_JANITOR_INTERVAL_MS,
  DEFAULT_MAX_ACTIVE_RUNS,
  DEFAULT_MAX_EVENTS_PER_RUN,
  DEFAULT_MAX_EVENT_BYTES_PER_RUN,
  DEFAULT_TERMINAL_TTL_MS,
  type CreateRelayRunInput,
  type CachedOpenAIEvent,
  type OpenAIStreamEvent,
  type RelayIngestResult,
  type RelayRun,
  type RelayRunStatus,
  type RelaySnapshot,
  type RelayStatusResponse,
  type RelayStoreOptions,
  isTerminalStatus,
} from "./relay-types";
import { applyEventToSnapshot, extractResponseId, extractSequenceNumber } from "./openai-event-normalizer";

export class RelayStoreError extends Error {
  public readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "RelayStoreError";
    this.code = code;
  }
}

export class RelayRunNotFoundError extends RelayStoreError {
  constructor(relayRunId: string) {
    super("not_found", `Relay run not found: ${relayRunId}`);
    this.name = "RelayRunNotFoundError";
  }
}

export class RelayRunLimitError extends RelayStoreError {
  constructor(message: string, code: string = "cache_limit_exceeded") {
    super(code, message);
    this.name = "RelayRunLimitError";
  }
}

function createEmptySnapshot(status: RelayRunStatus = "starting"): RelaySnapshot {
  return {
    status,
    lastSequenceNumber: 0,
    accumulatedText: "",
    accumulatedThinking: "",
    toolCalls: {},
    annotations: [],
  };
}

function safeEventSize(raw: unknown): number {
  try {
    return Buffer.byteLength(JSON.stringify(raw));
  } catch {
    return 0;
  }
}

export class RelayStore {
  private readonly runsById = new Map<string, RelayRun>();
  private readonly runIdByClientRequestId = new Map<string, string>();
  private readonly janitor: NodeJS.Timeout;
  private readonly options: Required<RelayStoreOptions>;

  constructor(options: RelayStoreOptions = {}) {
    this.options = {
      terminalTtlMs: options.terminalTtlMs ?? DEFAULT_TERMINAL_TTL_MS,
      janitorIntervalMs: options.janitorIntervalMs ?? DEFAULT_JANITOR_INTERVAL_MS,
      maxActiveRuns: options.maxActiveRuns ?? DEFAULT_MAX_ACTIVE_RUNS,
      maxEventsPerRun: options.maxEventsPerRun ?? DEFAULT_MAX_EVENTS_PER_RUN,
      maxEventBytesPerRun: options.maxEventBytesPerRun ?? DEFAULT_MAX_EVENT_BYTES_PER_RUN,
    };

    this.janitor = setInterval(() => {
      try {
        this.deleteExpiredRuns();
      } catch (error) {
        console.error("[relay-store] janitor error", error);
      }
    }, this.options.janitorIntervalMs);

    if (typeof this.janitor.unref === "function") {
      this.janitor.unref();
    }
  }

  public dispose(): void {
    clearInterval(this.janitor);
  }

  public getActiveRunCount(): number {
    return Array.from(this.runsById.values()).filter((run) => !isTerminalStatus(run.status)).length;
  }

  public createRun(input: CreateRelayRunInput, options?: { indexClientRequestId?: boolean }): RelayRun {
    if (this.runsById.has(input.relayRunId)) {
      throw new RelayStoreError("duplicate_run_id", `Relay run already exists: ${input.relayRunId}`);
    }

    const activeRuns = Array.from(this.runsById.values()).filter((run) => !isTerminalStatus(run.status)).length;
    if (activeRuns >= this.options.maxActiveRuns) {
      throw new RelayRunLimitError(
        `Relay active-run limit exceeded (${this.options.maxActiveRuns})`,
        "cache_limit_exceeded",
      );
    }

    const now = Date.now();
    const status = input.status ?? "starting";

    const run: RelayRun = {
      relayRunId: input.relayRunId,
      resumeToken: input.resumeToken,
      conversationId: input.conversationId,
      clientRequestId: input.clientRequestId,
      responseId: input.responseId,
      model: input.model,
      reasoningEffort: input.reasoningEffort,
      vectorStoreIds: [...input.vectorStoreIds],
      status,
      createdAt: now,
      updatedAt: now,
      expiresAt: now + this.options.terminalTtlMs,
      eventLog: [],
      eventIndexBySequence: new Map(),
      eventLogBytes: 0,
      snapshot: {
        ...createEmptySnapshot(status),
        responseId: input.responseId,
      },
      sockets: new Set(),
      openaiStreamActive: false,
      metadata: input.metadata ? { ...input.metadata } : undefined,
    };

    this.runsById.set(run.relayRunId, run);

    if ((options?.indexClientRequestId ?? true) && run.clientRequestId) {
      this.runIdByClientRequestId.set(run.clientRequestId, run.relayRunId);
    }

    return run;
  }

  public upsertTransientRun(
    input: Omit<CreateRelayRunInput, "model" | "reasoningEffort" | "vectorStoreIds" | "clientRequestId"> & {
      model?: string;
      reasoningEffort?: string;
      vectorStoreIds?: string[];
      clientRequestId?: string;
    },
  ): RelayRun {
    const existing = this.runsById.get(input.relayRunId);
    if (existing) {
      if (input.responseId && !existing.responseId) {
        this.setResponseId(existing.relayRunId, input.responseId);
      }
      return existing;
    }

    return this.createRun(
      {
        relayRunId: input.relayRunId,
        resumeToken: input.resumeToken,
        conversationId: input.conversationId,
        clientRequestId: input.clientRequestId ?? `transient:${input.relayRunId}`,
        model: input.model ?? "unknown",
        reasoningEffort: input.reasoningEffort ?? "unknown",
        vectorStoreIds: input.vectorStoreIds ?? [],
        metadata: input.metadata,
        responseId: input.responseId,
        status: input.status ?? "starting",
      },
      { indexClientRequestId: false },
    );
  }

  public getRun(relayRunId: string): RelayRun | undefined {
    return this.runsById.get(relayRunId);
  }

  public requireRun(relayRunId: string): RelayRun {
    const run = this.runsById.get(relayRunId);
    if (!run) {
      throw new RelayRunNotFoundError(relayRunId);
    }
    return run;
  }

  public getRunByClientRequestId(clientRequestId: string): RelayRun | undefined {
    const relayRunId = this.runIdByClientRequestId.get(clientRequestId);
    return relayRunId ? this.runsById.get(relayRunId) : undefined;
  }

  public ingestOpenAIEvent(relayRunId: string, rawEvent: OpenAIStreamEvent): RelayIngestResult {
    const run = this.requireRun(relayRunId);
    const sequenceNumber = extractSequenceNumber(rawEvent);

    if (typeof sequenceNumber === "number" && run.eventIndexBySequence.has(sequenceNumber)) {
      run.updatedAt = Date.now();
      return {
        run,
        cachedEvent: run.eventIndexBySequence.get(sequenceNumber),
        isDuplicate: true,
        becameTerminal: false,
      };
    }

    const beforeStatus = run.status;
    const responseId = extractResponseId(rawEvent);

    if (responseId && !run.responseId) {
      run.responseId = responseId;
      run.snapshot.responseId = responseId;
    }

    applyEventToSnapshot(run.snapshot, rawEvent);

    if (responseId && !run.snapshot.responseId) {
      run.snapshot.responseId = responseId;
    }
    if (run.snapshot.responseId && !run.responseId) {
      run.responseId = run.snapshot.responseId;
    }

    run.status = run.snapshot.status;
    run.updatedAt = Date.now();

    let cachedEvent: RelayIngestResult["cachedEvent"];
    if (typeof sequenceNumber === "number") {
      const byteLength = safeEventSize(rawEvent);
      this.assertEventCapacity(run, byteLength);

      cachedEvent = {
        sequenceNumber,
        type: typeof rawEvent.type === "string" ? rawEvent.type : "unknown",
        raw: rawEvent,
        receivedAt: Date.now(),
        byteLength,
      };

      run.eventLog.push(cachedEvent);
      run.eventIndexBySequence.set(sequenceNumber, cachedEvent);
      run.eventLogBytes += byteLength;
      run.snapshot.lastSequenceNumber = Math.max(run.snapshot.lastSequenceNumber, sequenceNumber);
    }

    const becameTerminal = !isTerminalStatus(beforeStatus) && isTerminalStatus(run.status);
    if (becameTerminal) {
      run.expiresAt = Date.now() + this.options.terminalTtlMs;
      run.openaiStreamActive = false;
      run.abortController = undefined;
    }

    return {
      run,
      cachedEvent,
      isDuplicate: false,
      becameTerminal,
    };
  }

  public listReplayEventsAfter(relayRunId: string, sequenceNumber: number): CachedOpenAIEvent[] {
    const run = this.requireRun(relayRunId);
    const normalized = Number.isFinite(sequenceNumber) ? sequenceNumber : 0;
    return run.eventLog.filter((event) => event.sequenceNumber > normalized);
  }

  public attachSocket(relayRunId: string, socketId: string): void {
    const run = this.requireRun(relayRunId);
    run.sockets.add(socketId);
    run.updatedAt = Date.now();
  }

  public detachSocket(relayRunId: string, socketId: string): void {
    const run = this.getRun(relayRunId);
    if (!run) {
      return;
    }
    run.sockets.delete(socketId);
    run.updatedAt = Date.now();
  }

  public detachSocketFromAll(socketId: string): void {
    for (const run of this.runsById.values()) {
      if (run.sockets.delete(socketId)) {
        run.updatedAt = Date.now();
      }
    }
  }

  public setAbortController(relayRunId: string, abortController: AbortController | undefined): void {
    const run = this.requireRun(relayRunId);
    run.abortController = abortController;
    run.updatedAt = Date.now();
  }

  public setOpenAIStreamActive(relayRunId: string, active: boolean): void {
    const run = this.requireRun(relayRunId);
    run.openaiStreamActive = active;
    run.updatedAt = Date.now();
  }

  public setResponseId(relayRunId: string, responseId: string): void {
    const run = this.requireRun(relayRunId);
    run.responseId = responseId;
    run.snapshot.responseId = responseId;
    run.updatedAt = Date.now();
  }

  public markStatus(relayRunId: string, status: RelayRunStatus): RelayRun {
    const run = this.requireRun(relayRunId);
    run.status = status;
    run.snapshot.status = status;
    run.updatedAt = Date.now();

    if (isTerminalStatus(status)) {
      run.expiresAt = Date.now() + this.options.terminalTtlMs;
      run.openaiStreamActive = false;
      run.abortController = undefined;
    }

    return run;
  }

  public markTerminal(relayRunId: string, status: Extract<RelayRunStatus, "completed" | "incomplete" | "failed" | "cancelled">, finalError?: string): RelayRun {
    const run = this.requireRun(relayRunId);
    run.status = status;
    run.snapshot.status = status;
    if (finalError) {
      run.snapshot.finalError = finalError;
    }
    run.updatedAt = Date.now();
    run.expiresAt = Date.now() + this.options.terminalTtlMs;
    run.openaiStreamActive = false;
    run.abortController = undefined;
    return run;
  }

  public markStreamDetached(relayRunId: string, message?: string): RelayRun {
    const run = this.requireRun(relayRunId);
    run.openaiStreamActive = false;
    run.abortController = undefined;
    run.updatedAt = Date.now();
    if (message) {
      run.snapshot.finalError = message;
    }
    return run;
  }

  public deleteExpiredRuns(now: number = Date.now()): number {
    let deleted = 0;

    for (const [relayRunId, run] of this.runsById.entries()) {
      if (!isTerminalStatus(run.status)) {
        continue;
      }
      if (run.expiresAt > now) {
        continue;
      }

      this.runsById.delete(relayRunId);
      if (run.clientRequestId) {
        this.runIdByClientRequestId.delete(run.clientRequestId);
      }
      deleted += 1;
    }

    return deleted;
  }

  public toStatusResponse(relayRunId: string): RelayStatusResponse {
    const run = this.requireRun(relayRunId);
    return {
      relayRunId: run.relayRunId,
      conversationId: run.conversationId,
      clientRequestId: run.clientRequestId,
      responseId: run.responseId,
      model: run.model,
      reasoningEffort: run.reasoningEffort,
      vectorStoreIds: [...run.vectorStoreIds],
      status: run.status,
      createdAt: run.createdAt,
      updatedAt: run.updatedAt,
      expiresAt: run.expiresAt,
      openaiStreamActive: run.openaiStreamActive,
      lastSequenceNumber: run.snapshot.lastSequenceNumber,
      snapshot: {
        ...run.snapshot,
        toolCalls: { ...run.snapshot.toolCalls },
        annotations: [...run.snapshot.annotations],
      },
    };
  }

  private assertEventCapacity(run: RelayRun, nextEventBytes: number): void {
    if (run.eventLog.length + 1 > this.options.maxEventsPerRun) {
      throw new RelayRunLimitError(
        `Relay run ${run.relayRunId} exceeded max event count (${this.options.maxEventsPerRun})`,
      );
    }
    if (run.eventLogBytes + nextEventBytes > this.options.maxEventBytesPerRun) {
      throw new RelayRunLimitError(
        `Relay run ${run.relayRunId} exceeded max event bytes (${this.options.maxEventBytesPerRun})`,
      );
    }
  }
}
