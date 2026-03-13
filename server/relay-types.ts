export const RELAY_HTTP_BASE_PATH = "/api/relay";
export const RELAY_SOCKET_PATH = "/api/socket.io";

export const DEFAULT_TERMINAL_TTL_MS = 30 * 60_000;
export const DEFAULT_JANITOR_INTERVAL_MS = 60_000;
export const DEFAULT_MAX_ACTIVE_RUNS = 200;
export const DEFAULT_MAX_EVENTS_PER_RUN = 20_000;
export const DEFAULT_MAX_EVENT_BYTES_PER_RUN = 16 * 1024 * 1024;

export const DEFAULT_FINAL_RESPONSE_INCLUDES = [
  "web_search_call.action.sources",
  "code_interpreter_call.outputs",
  "file_search_call.results",
] as const;

export type RelayRunStatus =
  | "starting"
  | "streaming"
  | "completed"
  | "incomplete"
  | "failed"
  | "cancelled";

export type ReasoningEffort = "none" | "minimal" | "low" | "medium" | "high" | "xhigh" | string;

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonValue[];
export type JsonObject = { [key: string]: JsonValue };

export type OpenAIStreamEvent = Record<string, unknown> & {
  type?: string;
  sequence_number?: number;
  response_id?: string;
  item_id?: string;
  output_index?: number;
  delta?: string;
  text?: string;
  response?: Record<string, unknown>;
  error?: Record<string, unknown> | string | null;
};

export type RelayErrorCode =
  | "missing_api_key"
  | "invalid_api_key"
  | "invalid_request"
  | "invalid_resume_token"
  | "not_found"
  | "cache_miss"
  | "rate_limited"
  | "forbidden"
  | "openai_auth_error"
  | "openai_bad_request"
  | "openai_not_found"
  | "openai_rate_limit"
  | "openai_upstream_error"
  | "openai_stream_dropped"
  | "cache_limit_exceeded"
  | "upload_failed"
  | "internal_error";

export interface CachedOpenAIEvent {
  sequenceNumber: number;
  type: string;
  raw: OpenAIStreamEvent;
  receivedAt: number;
  byteLength: number;
}

export interface RelaySnapshot {
  responseId?: string;
  status: RelayRunStatus;
  lastSequenceNumber: number;
  accumulatedText: string;
  accumulatedThinking: string;
  toolCalls: Record<string, unknown>;
  annotations: unknown[];
  finalError?: string;
}

export interface RelayRun {
  relayRunId: string;
  resumeToken: string;
  conversationId: string;
  clientRequestId: string;
  responseId?: string;
  model: string;
  reasoningEffort: string;
  vectorStoreIds: string[];
  status: RelayRunStatus;
  createdAt: number;
  updatedAt: number;
  expiresAt: number;
  eventLog: CachedOpenAIEvent[];
  eventIndexBySequence: Map<number, CachedOpenAIEvent>;
  eventLogBytes: number;
  snapshot: RelaySnapshot;
  sockets: Set<string>;
  abortController?: AbortController;
  openaiStreamActive: boolean;
  metadata?: Record<string, unknown>;
}

export interface RelayRunStartRequest {
  clientRequestId: string;
  conversationId: string;
  messages: unknown[];
  model: string;
  reasoningEffort?: string;
  vectorStoreIds?: string[];
  metadata?: Record<string, unknown>;
}

export interface RelayRunStartResponse {
  relayRunId: string;
  resumeToken: string;
  status: RelayRunStatus;
  responseId?: string;
}

export interface RelayCancelRequestBody {
  resumeToken: string;
}

export interface RelayCancelResponse {
  ok: true;
  relayRunId: string;
  status: RelayRunStatus;
  responseId?: string;
}

export interface RelayFileUploadResponse {
  fileId: string;
  filename: string;
  contentType: string;
  bytes?: number;
}

export interface RelayJoinPayload {
  relayRunId: string;
  resumeToken: string;
  lastSequenceNumber?: number;
  responseId?: string;
}

export interface RelayResumeOpenAIPayload {
  relayRunId: string;
  resumeToken: string;
  responseId: string;
  lastSequenceNumber?: number;
  apiKey: string;
}

export interface RelayLeavePayload {
  relayRunId: string;
}

export interface RelayCancelSocketPayload {
  relayRunId: string;
  resumeToken: string;
  apiKey: string;
}

export interface RelayJoinedPayload {
  relayRunId: string;
  responseId?: string;
  status: RelayRunStatus;
  serverLastSequenceNumber: number;
}

export interface RelayEventEnvelope {
  relayRunId: string;
  sequenceNumber: number;
  replay: boolean;
  event: OpenAIStreamEvent;
}

export interface RelayLivePayload {
  relayRunId: string;
  afterSequenceNumber: number;
}

export interface RelayDonePayload {
  relayRunId: string;
  status: RelayRunStatus;
  responseId?: string;
  lastSequenceNumber: number;
}

export interface RelayErrorPayload {
  relayRunId?: string;
  code: RelayErrorCode;
  message: string;
  retryable: boolean;
}

export interface RelayStatusResponse {
  relayRunId: string;
  conversationId: string;
  clientRequestId: string;
  responseId?: string;
  model: string;
  reasoningEffort: string;
  vectorStoreIds: string[];
  status: RelayRunStatus;
  createdAt: number;
  updatedAt: number;
  expiresAt: number;
  openaiStreamActive: boolean;
  lastSequenceNumber: number;
  snapshot: RelaySnapshot;
}

export interface CreateRelayRunInput {
  relayRunId: string;
  resumeToken: string;
  conversationId: string;
  clientRequestId: string;
  model: string;
  reasoningEffort: string;
  vectorStoreIds: string[];
  metadata?: Record<string, unknown>;
  responseId?: string;
  status?: RelayRunStatus;
}

export interface RelayStoreOptions {
  terminalTtlMs?: number;
  janitorIntervalMs?: number;
  maxActiveRuns?: number;
  maxEventsPerRun?: number;
  maxEventBytesPerRun?: number;
}

export interface RelayIngestResult {
  run: RelayRun;
  cachedEvent?: CachedOpenAIEvent;
  isDuplicate: boolean;
  becameTerminal: boolean;
}

export interface StartBackgroundStreamArgs {
  relayRunId: string;
  apiKey: string;
  request: RelayRunStartRequest;
}

export interface ResumeBackgroundStreamArgs {
  relayRunId: string;
  apiKey: string;
  responseId: string;
  startingAfter: number;
}

export interface CancelBackgroundRunArgs {
  relayRunId: string;
  apiKey: string;
}

export interface RetrieveFinalResponseArgs {
  apiKey: string;
  responseId: string;
  include?: readonly string[];
}

export interface UploadFileArgs {
  apiKey: string;
  filename: string;
  contentType: string;
  buffer: Buffer;
}

export function relayRunRoom(relayRunId: string): string {
  return `run:${relayRunId}`;
}

export function isTerminalStatus(status: RelayRunStatus): boolean {
  return (
    status === "completed" ||
    status === "incomplete" ||
    status === "failed" ||
    status === "cancelled"
  );
}
