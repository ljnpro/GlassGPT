import { DurableObject } from 'cloudflare:workers';
import type { BackendEnv } from '../persistence/env.js';

interface ConversationHubSnapshot {
  readonly lastEventCursor: string;
  readonly updatedAt: string;
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

export class ConversationEventHub extends DurableObject<Env> {
  private runClients: Map<string, Set<ReadableStreamDefaultController<Uint8Array>>> = new Map();
  private readonly encoder = new TextEncoder();

  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    const streamMatch = url.pathname.match(/\/stream\/([^/]+)$/);
    if (request.method === 'GET' && streamMatch && streamMatch[1]) {
      return this.handleSSEConnection(streamMatch[1]);
    }

    if (request.method === 'GET') {
      const snapshot = (await this.ctx.storage.get<ConversationHubSnapshot>('snapshot')) ?? null;
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
      await this.ctx.storage.put('snapshot', snapshot);
      return Response.json({ ok: true, snapshot }, { status: 202 });
    }

    // POST /stream-delta — real-time token broadcast (from workflow, bypasses D1)
    if (request.method === 'POST' && url.pathname.endsWith('/stream-delta')) {
      const delta = (await request.json()) as StreamDelta;
      this.broadcastDelta(delta);
      return Response.json({ ok: true }, { status: 202 });
    }

    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  private handleSSEConnection(runId: string): Response {
    const stream = new ReadableStream<Uint8Array>({
      start: (controller) => {
        let clients = this.runClients.get(runId);
        if (!clients) {
          clients = new Set();
          this.runClients.set(runId, clients);
        }
        clients.add(controller);
        const ping = this.encoder.encode(': connected\n\n');
        controller.enqueue(ping);
      },
      cancel: (controller) => {
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

  private broadcastDelta(delta: StreamDelta): void {
    const frame = this.encoder.encode(
      `event: ${delta.type}\ndata: ${JSON.stringify(delta.data)}\n\n`,
    );

    const deltaData = delta.data as { runId?: string } | null;
    const targetRunId = deltaData?.runId;

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
