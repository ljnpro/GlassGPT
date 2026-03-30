import { DurableObject } from 'cloudflare:workers';
import type { BackendEnv } from '../persistence/env.js';

interface ConversationHubSnapshot {
  readonly lastEventCursor: string;
  readonly updatedAt: string;
}

interface ConversationHubBufferedEvent {
  readonly frame: string;
  readonly id: string;
}

interface StreamDelta {
  readonly type:
    | 'citations_update'
    | 'delta'
    | 'done'
    | 'error'
    | 'file_path_annotations_update'
    | 'process_update'
    | 'stage'
    | 'status'
    | 'task_update'
    | 'thinking_delta'
    | 'thinking_done'
    | 'tool_call_update';
  readonly data: unknown;
}

const SNAPSHOT_STORAGE_KEY = 'snapshot';
const STREAM_HISTORY_LIMIT = 128;

export class ConversationEventHub extends DurableObject<Env> {
  private runClients: Map<string, Set<ReadableStreamDefaultController<Uint8Array>>> = new Map();
  private readonly encoder = new TextEncoder();

  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    const streamMatch = url.pathname.match(/\/stream\/([^/]+)$/);
    if (request.method === 'GET' && streamMatch && streamMatch[1]) {
      return this.handleSSEConnection(streamMatch[1], request.headers.get('Last-Event-ID'));
    }

    if (request.method === 'GET') {
      const snapshot =
        (await this.ctx.storage.get<ConversationHubSnapshot>(SNAPSHOT_STORAGE_KEY)) ?? null;
      return Response.json({ ok: true, snapshot });
    }

    // POST /events — cursor update (from persistProjectedEvent)
    if (request.method === 'POST' && url.pathname.endsWith('/events')) {
      const body = (await request.json()) as { cursor?: string };
      if (!body.cursor || typeof body.cursor !== 'string' || body.cursor.length > 64) {
        return Response.json({ error: 'cursor is required' }, { status: 400 });
      }

      const snapshot: ConversationHubSnapshot = {
        lastEventCursor: body.cursor,
        updatedAt: new Date().toISOString(),
      };
      await this.ctx.storage.put(SNAPSHOT_STORAGE_KEY, snapshot);
      return Response.json({ ok: true, snapshot }, { status: 202 });
    }

    // POST /stream-delta — real-time token broadcast (from workflow, bypasses D1)
    if (request.method === 'POST' && url.pathname.endsWith('/stream-delta')) {
      const delta = (await request.json()) as StreamDelta;
      await this.broadcastDelta(delta);
      return Response.json({ ok: true }, { status: 202 });
    }

    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  private handleSSEConnection(runId: string, lastEventID: string | null): Response {
    const heartbeatFrame = this.encoder.encode(': hb\n\n');
    let heartbeatTimer: ReturnType<typeof setInterval> | null = null;

    const stream = new ReadableStream<Uint8Array>({
      start: async (controller) => {
        let clients = this.runClients.get(runId);
        if (!clients) {
          clients = new Set();
          this.runClients.set(runId, clients);
        }
        clients.add(controller);
        const ping = this.encoder.encode(': connected\n\n');
        controller.enqueue(ping);
        await this.replayBufferedEvents(runId, lastEventID, controller);

        // High-frequency heartbeat pushes data through the internal
        // DO → Worker RPC buffer that holds small writes.
        heartbeatTimer = setInterval(() => {
          try {
            controller.enqueue(heartbeatFrame);
          } catch {
            if (heartbeatTimer !== null) {
              clearInterval(heartbeatTimer);
              heartbeatTimer = null;
            }
          }
        }, 100);
      },
      cancel: (controller) => {
        if (heartbeatTimer !== null) {
          clearInterval(heartbeatTimer);
          heartbeatTimer = null;
        }
        const clients = this.runClients.get(runId);
        if (clients) {
          clients.delete(controller as ReadableStreamDefaultController<Uint8Array>);
          if (clients.size === 0) {
            this.runClients.delete(runId);
          }
        }
      },
    });

    return new Response(stream, {
      headers: {
        'Cache-Control': 'no-cache',
        Connection: 'keep-alive',
        'Content-Type': 'text/event-stream',
      },
    });
  }

  private async replayBufferedEvents(
    runId: string,
    lastEventID: string | null,
    controller: ReadableStreamDefaultController<Uint8Array>,
  ): Promise<void> {
    if (!lastEventID) {
      return;
    }

    const history = await this.readBufferedEvents(runId);
    const replayStartIndex = history.findIndex((entry) => entry.id === lastEventID);
    if (replayStartIndex < 0) {
      return;
    }

    for (const entry of history.slice(replayStartIndex + 1)) {
      controller.enqueue(this.encoder.encode(entry.frame));
    }
  }

  private async readBufferedEvents(runId: string): Promise<ConversationHubBufferedEvent[]> {
    return (
      (await this.ctx.storage.get<ConversationHubBufferedEvent[]>(
        this.streamHistoryStorageKey(runId),
      )) ?? []
    );
  }

  private async nextBufferedEventID(runId: string): Promise<string> {
    const storageKey = this.streamSequenceStorageKey(runId);
    const nextSequence = ((await this.ctx.storage.get<number>(storageKey)) ?? 0) + 1;
    await this.ctx.storage.put(storageKey, nextSequence);
    return `stream_${runId}_${String(nextSequence).padStart(8, '0')}`;
  }

  private async appendBufferedEvent(
    runId: string,
    event: ConversationHubBufferedEvent,
  ): Promise<void> {
    const history = await this.readBufferedEvents(runId);
    history.push(event);
    const boundedHistory = history.slice(-STREAM_HISTORY_LIMIT);
    await this.ctx.storage.put(this.streamHistoryStorageKey(runId), boundedHistory);
  }

  private streamHistoryStorageKey(runId: string): string {
    return `stream-history:${runId}`;
  }

  private streamSequenceStorageKey(runId: string): string {
    return `stream-sequence:${runId}`;
  }

  private async broadcastDelta(delta: StreamDelta): Promise<void> {
    const snapshot =
      (await this.ctx.storage.get<ConversationHubSnapshot>(SNAPSHOT_STORAGE_KEY)) ?? null;
    const deltaData = delta.data as { runId?: string } | null;
    const targetRunId = deltaData?.runId;
    const eventID = targetRunId
      ? await this.nextBufferedEventID(targetRunId)
      : ((delta.data as { cursor?: string } | null)?.cursor ?? snapshot?.lastEventCursor ?? null);
    const frameText = `${eventID ? `id: ${eventID}\n` : ''}event: ${delta.type}\ndata: ${JSON.stringify(delta.data)}\n\n`;
    if (targetRunId && eventID) {
      await this.appendBufferedEvent(targetRunId, { frame: frameText, id: eventID });
    }
    const frame = this.encoder.encode(frameText);

    // If the delta has a runId, only broadcast to subscribers of that run
    const clientSets: Set<ReadableStreamDefaultController<Uint8Array>>[] = [];
    if (targetRunId) {
      const clients = this.runClients.get(targetRunId);
      if (clients) {
        clientSets.push(clients);
      }
    } else {
      // Fallback: broadcast to all runs
      for (const clients of this.runClients.values()) {
        clientSets.push(clients);
      }
    }

    for (const clients of clientSets) {
      const staleClients: ReadableStreamDefaultController<Uint8Array>[] = [];
      for (const client of clients) {
        try {
          client.enqueue(frame);
        } catch {
          staleClients.push(client);
        }
      }
      for (const client of staleClients) {
        clients.delete(client);
      }
    }
  }
}

export const publishConversationCursor = async (
  env: BackendEnv,
  conversationId: string,
  cursor: string,
): Promise<void> => {
  const durableObjectId = env.CONVERSATION_EVENT_HUB.idFromName(conversationId);
  const stub = env.CONVERSATION_EVENT_HUB.get(durableObjectId);
  await stub.fetch('https://conversation-event-hub/events', {
    body: JSON.stringify({ cursor }),
    headers: { 'content-type': 'application/json' },
    method: 'POST',
  });
};

export const broadcastStreamDelta = async (
  env: BackendEnv,
  conversationId: string,
  delta: {
    type:
      | 'citations_update'
      | 'delta'
      | 'done'
      | 'error'
      | 'file_path_annotations_update'
      | 'process_update'
      | 'stage'
      | 'status'
      | 'task_update'
      | 'thinking_delta'
      | 'thinking_done'
      | 'tool_call_update';
    data: unknown;
  },
): Promise<void> => {
  const durableObjectId = env.CONVERSATION_EVENT_HUB.idFromName(conversationId);
  const stub = env.CONVERSATION_EVENT_HUB.get(durableObjectId);
  await stub.fetch('https://conversation-event-hub/stream-delta', {
    body: JSON.stringify(delta),
    headers: { 'content-type': 'application/json' },
    method: 'POST',
  });
};
