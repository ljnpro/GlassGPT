import type { Server, Socket } from "socket.io";
import type { OpenAIRelayService } from "./openai-relay";
import type { RelayStore } from "./relay-store";
import {
  type RelayCancelSocketPayload,
  type RelayErrorPayload,
  type RelayJoinPayload,
  type RelayLeavePayload,
  type RelayResumeOpenAIPayload,
  isTerminalStatus,
  relayRunRoom,
} from "./relay-types";
import {
  RelayHttpError,
  isRecord,
  readOptionalFiniteNumber,
  readOptionalString,
  requireNonEmptyString,
} from "./relay-security";

type AckFn = (payload: Record<string, unknown>) => void;

type RelaySocketDeps = {
  store: RelayStore;
  relay: OpenAIRelayService;
};

function getSocketRunSet(socket: Socket): Set<string> {
  const existing = socket.data.relayRunIds;
  if (existing instanceof Set) {
    return existing as Set<string>;
  }
  const created = new Set<string>();
  socket.data.relayRunIds = created;
  return created;
}

function toSocketErrorPayload(relayRunId: string | undefined, error: unknown): RelayErrorPayload {
  if (error instanceof RelayHttpError) {
    return {
      relayRunId,
      code: error.code,
      message: error.message,
      retryable: error.retryable,
    };
  }

  if (error instanceof Error) {
    return {
      relayRunId,
      code: "internal_error",
      message: error.message,
      retryable: false,
    };
  }

  return {
    relayRunId,
    code: "internal_error",
    message: "Unexpected socket error",
    retryable: false,
  };
}

function parseJoinPayload(payload: unknown): RelayJoinPayload {
  if (!isRecord(payload)) {
    throw new RelayHttpError(400, "invalid_request", "Invalid relay:join payload", false);
  }

  return {
    relayRunId: requireNonEmptyString(payload, "relayRunId"),
    resumeToken: requireNonEmptyString(payload, "resumeToken"),
    lastSequenceNumber: readOptionalFiniteNumber(payload, "lastSequenceNumber"),
    responseId: readOptionalString(payload, "responseId"),
  };
}

function parseResumePayload(payload: unknown): RelayResumeOpenAIPayload {
  if (!isRecord(payload)) {
    throw new RelayHttpError(400, "invalid_request", "Invalid relay:resume-openai payload", false);
  }

  return {
    relayRunId: requireNonEmptyString(payload, "relayRunId"),
    resumeToken: requireNonEmptyString(payload, "resumeToken"),
    responseId: requireNonEmptyString(payload, "responseId"),
    lastSequenceNumber: readOptionalFiniteNumber(payload, "lastSequenceNumber"),
    apiKey: requireNonEmptyString(payload, "apiKey"),
  };
}

function parseLeavePayload(payload: unknown): RelayLeavePayload {
  if (!isRecord(payload)) {
    throw new RelayHttpError(400, "invalid_request", "Invalid relay:leave payload", false);
  }

  return {
    relayRunId: requireNonEmptyString(payload, "relayRunId"),
  };
}

function parseCancelPayload(payload: unknown): RelayCancelSocketPayload {
  if (!isRecord(payload)) {
    throw new RelayHttpError(400, "invalid_request", "Invalid relay:cancel payload", false);
  }

  return {
    relayRunId: requireNonEmptyString(payload, "relayRunId"),
    resumeToken: requireNonEmptyString(payload, "resumeToken"),
    apiKey: requireNonEmptyString(payload, "apiKey"),
  };
}

async function handleJoin(socket: Socket, deps: RelaySocketDeps, payload: unknown, ack?: AckFn): Promise<void> {
  const parsed = parseJoinPayload(payload);
  const run = deps.store.getRun(parsed.relayRunId);

  if (!run) {
    const errorPayload: RelayErrorPayload = {
      relayRunId: parsed.relayRunId,
      code: "cache_miss",
      message: "Relay run is not present in local cache.",
      retryable: true,
    };
    socket.emit("relay:error", errorPayload);
    ack?.({ ok: false, ...errorPayload });
    return;
  }

  if (run.resumeToken !== parsed.resumeToken) {
    throw new RelayHttpError(403, "forbidden", "Invalid relay resume token", false);
  }

  if (!run.responseId && parsed.responseId) {
    deps.store.setResponseId(run.relayRunId, parsed.responseId);
  }

  const room = relayRunRoom(run.relayRunId);
  await socket.join(room);
  deps.store.attachSocket(run.relayRunId, socket.id);
  getSocketRunSet(socket).add(run.relayRunId);

  const lastSequenceNumber = Math.max(0, parsed.lastSequenceNumber ?? 0);
  const replayEvents = deps.store.listReplayEventsAfter(run.relayRunId, lastSequenceNumber);

  socket.emit("relay:joined", {
    relayRunId: run.relayRunId,
    responseId: run.responseId,
    status: run.status,
    serverLastSequenceNumber: run.snapshot.lastSequenceNumber,
  });

  for (const cachedEvent of replayEvents) {
    socket.emit("relay:event", {
      relayRunId: run.relayRunId,
      sequenceNumber: cachedEvent.sequenceNumber,
      replay: true,
      event: cachedEvent.raw,
    });
  }

  if (run.snapshot.finalError) {
    socket.emit("relay:error", {
      relayRunId: run.relayRunId,
      code: run.status === "failed" ? "openai_upstream_error" : "internal_error",
      message: run.snapshot.finalError,
      retryable: false,
    } satisfies RelayErrorPayload);
  }

  if (isTerminalStatus(run.status)) {
    socket.emit("relay:done", {
      relayRunId: run.relayRunId,
      status: run.status,
      responseId: run.responseId,
      lastSequenceNumber: run.snapshot.lastSequenceNumber,
    });
    ack?.({ ok: true, replayed: replayEvents.length, terminal: true });
    return;
  }

  socket.emit("relay:live", {
    relayRunId: run.relayRunId,
    afterSequenceNumber: run.snapshot.lastSequenceNumber,
  });
  ack?.({ ok: true, replayed: replayEvents.length, terminal: false });
}

async function handleResumeOpenAI(
  socket: Socket,
  deps: RelaySocketDeps,
  payload: unknown,
  ack?: AckFn,
): Promise<void> {
  const parsed = parseResumePayload(payload);

  let run = deps.store.getRun(parsed.relayRunId);
  if (run && run.resumeToken !== parsed.resumeToken) {
    throw new RelayHttpError(403, "forbidden", "Invalid relay resume token", false);
  }

  if (!run) {
    run = deps.store.upsertTransientRun({
      relayRunId: parsed.relayRunId,
      resumeToken: parsed.resumeToken,
      conversationId: `transient:${parsed.relayRunId}`,
      clientRequestId: `transient:${parsed.responseId}`,
      responseId: parsed.responseId,
      status: "streaming",
    });
  } else if (!run.responseId) {
    deps.store.setResponseId(run.relayRunId, parsed.responseId);
  }

  const room = relayRunRoom(run.relayRunId);
  await socket.join(room);
  deps.store.attachSocket(run.relayRunId, socket.id);
  getSocketRunSet(socket).add(run.relayRunId);

  socket.emit("relay:joined", {
    relayRunId: run.relayRunId,
    responseId: run.responseId,
    status: run.status,
    serverLastSequenceNumber: run.snapshot.lastSequenceNumber,
  });

  const replayEvents = deps.store.listReplayEventsAfter(
    run.relayRunId,
    Math.max(0, parsed.lastSequenceNumber ?? 0),
  );
  for (const cachedEvent of replayEvents) {
    socket.emit("relay:event", {
      relayRunId: run.relayRunId,
      sequenceNumber: cachedEvent.sequenceNumber,
      replay: true,
      event: cachedEvent.raw,
    });
  }

  if (!run.openaiStreamActive && !isTerminalStatus(run.status)) {
    void deps.relay
      .resumeBackgroundStream({
        relayRunId: run.relayRunId,
        apiKey: parsed.apiKey,
        responseId: parsed.responseId,
        startingAfter: Math.max(run.snapshot.lastSequenceNumber, parsed.lastSequenceNumber ?? 0),
      })
      .catch((error) => {
        const payload = toSocketErrorPayload(run?.relayRunId, error);
        socket.emit("relay:error", payload);
      });
  }

  if (isTerminalStatus(run.status)) {
    socket.emit("relay:done", {
      relayRunId: run.relayRunId,
      status: run.status,
      responseId: run.responseId,
      lastSequenceNumber: run.snapshot.lastSequenceNumber,
    });
    ack?.({ ok: true, replayed: replayEvents.length, terminal: true });
    return;
  }

  socket.emit("relay:live", {
    relayRunId: run.relayRunId,
    afterSequenceNumber: run.snapshot.lastSequenceNumber,
  });
  ack?.({ ok: true, replayed: replayEvents.length, terminal: false });
}

async function handleLeave(socket: Socket, deps: RelaySocketDeps, payload: unknown, ack?: AckFn): Promise<void> {
  const parsed = parseLeavePayload(payload);
  deps.store.detachSocket(parsed.relayRunId, socket.id);
  getSocketRunSet(socket).delete(parsed.relayRunId);
  await socket.leave(relayRunRoom(parsed.relayRunId));
  ack?.({ ok: true });
}

async function handleCancel(socket: Socket, deps: RelaySocketDeps, payload: unknown, ack?: AckFn): Promise<void> {
  const parsed = parseCancelPayload(payload);
  const run = deps.store.getRun(parsed.relayRunId);
  if (!run) {
    throw new RelayHttpError(404, "not_found", "Relay run not found", false);
  }
  if (run.resumeToken !== parsed.resumeToken) {
    throw new RelayHttpError(403, "forbidden", "Invalid relay resume token", false);
  }

  const cancelled = await deps.relay.cancelRun({
    relayRunId: run.relayRunId,
    apiKey: parsed.apiKey,
  });

  ack?.({
    ok: true,
    relayRunId: cancelled.relayRunId,
    status: cancelled.status,
    responseId: cancelled.responseId,
  });
}

export function registerRelaySocketHandlers(io: Server, deps: RelaySocketDeps): void {
  io.on("connection", (socket) => {
    getSocketRunSet(socket);

    socket.on("relay:join", (payload: unknown, ack?: AckFn) => {
      void handleJoin(socket, deps, payload, ack).catch((error) => {
        const relayRunId =
          isRecord(payload) && typeof payload.relayRunId === "string" ? payload.relayRunId : undefined;
        const errorPayload = toSocketErrorPayload(relayRunId, error);
        socket.emit("relay:error", errorPayload);
        ack?.({ ok: false, ...errorPayload });
      });
    });

    socket.on("relay:resume-openai", (payload: unknown, ack?: AckFn) => {
      void handleResumeOpenAI(socket, deps, payload, ack).catch((error) => {
        const relayRunId =
          isRecord(payload) && typeof payload.relayRunId === "string" ? payload.relayRunId : undefined;
        const errorPayload = toSocketErrorPayload(relayRunId, error);
        socket.emit("relay:error", errorPayload);
        ack?.({ ok: false, ...errorPayload });
      });
    });

    socket.on("relay:leave", (payload: unknown, ack?: AckFn) => {
      void handleLeave(socket, deps, payload, ack).catch((error) => {
        const relayRunId =
          isRecord(payload) && typeof payload.relayRunId === "string" ? payload.relayRunId : undefined;
        const errorPayload = toSocketErrorPayload(relayRunId, error);
        socket.emit("relay:error", errorPayload);
        ack?.({ ok: false, ...errorPayload });
      });
    });

    socket.on("relay:cancel", (payload: unknown, ack?: AckFn) => {
      void handleCancel(socket, deps, payload, ack).catch((error) => {
        const relayRunId =
          isRecord(payload) && typeof payload.relayRunId === "string" ? payload.relayRunId : undefined;
        const errorPayload = toSocketErrorPayload(relayRunId, error);
        socket.emit("relay:error", errorPayload);
        ack?.({ ok: false, ...errorPayload });
      });
    });

    socket.on("disconnect", () => {
      deps.store.detachSocketFromAll(socket.id);
      getSocketRunSet(socket).clear();
    });
  });
}
