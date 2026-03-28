import { DurableObject } from 'cloudflare:workers';
import type { BackendEnv } from '../persistence/env.js';

interface ConversationHubSnapshot {
  readonly lastEventCursor: string;
  readonly updatedAt: string;
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
      return Response.json({
        ok: true,
        snapshot,
      });
    }

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
      this.broadcastCursorUpdate(body.cursor);

      return Response.json(
        {
          ok: true,
          snapshot,
        },
        { status: 202 },
      );
    }

    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  private handleSSEConnection(): Response {
    const stream = new ReadableStream<Uint8Array>({
      start: (controller) => {
        this.sseClients.add(controller);

        // Send initial ping
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

  private broadcastCursorUpdate(cursor: string): void {
    const frame = this.encoder.encode(`event: cursor\ndata: ${JSON.stringify({ cursor })}\n\n`);
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
    headers: {
      'content-type': 'application/json',
    },
    method: 'POST',
  });
};
