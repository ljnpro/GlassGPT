import { DurableObject } from 'cloudflare:workers';
import type { BackendEnv } from '../persistence/env.js';

interface ConversationHubSnapshot {
  readonly lastEventCursor: string;
  readonly updatedAt: string;
}

export class ConversationEventHub extends DurableObject<Env> {
  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'GET') {
      const snapshot = (await this.ctx.storage.get<ConversationHubSnapshot>('snapshot')) ?? null;
      return Response.json({
        ok: true,
        snapshot,
      });
    }

    if (request.method === 'POST' && url.pathname.endsWith('/events')) {
      const body = (await request.json()) as { cursor?: string };
      if (!body.cursor) {
        return Response.json({ error: 'cursor is required' }, { status: 400 });
      }

      const snapshot: ConversationHubSnapshot = {
        lastEventCursor: body.cursor,
        updatedAt: new Date().toISOString(),
      };

      await this.ctx.storage.put('snapshot', snapshot);

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
