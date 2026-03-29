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
  private sseClients: Set<ReadableStreamDefaultController<Uint8Array>> = new Set();
  private readonly encoder = new TextEncoder();

  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname.endsWith('/stream')) {
      return this.handleSSEConnection();
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

  private handleSSEConnection(): Response {
    const stream = new ReadableStream<Uint8Array>({
      start: (controller) => {
        this.sseClients.add(controller);
        const ping = this.encoder.encode(': connected\n\n');
        controller.enqueue(ping);
      },
      cancel: (controller) => {
        this.sseClients.delete(controller as ReadableStreamDefaultController<Uint8Array>);
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
    const staleClients: ReadableStreamDefaultController<Uint8Array>[] = [];

    for (const client of this.sseClients) {
      try {
        client.enqueue(frame);
      } catch {
        staleClients.push(client);
      }
    }

    for (const client of staleClients) {
      this.sseClients.delete(client);
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
