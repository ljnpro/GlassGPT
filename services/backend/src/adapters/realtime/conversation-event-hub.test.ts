import { describe, expect, it, vi } from 'vitest';

vi.mock('cloudflare:workers', () => ({
  DurableObject: class {
    protected readonly ctx: unknown;
    protected readonly env: unknown;

    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  },
}));

const { ConversationEventHub } = await import('./conversation-event-hub.js');

class FakeDurableObjectStorage {
  private readonly store = new Map<string, unknown>();

  async get<T>(key: string): Promise<T | undefined> {
    return this.store.get(key) as T | undefined;
  }

  async put(key: string, value: unknown): Promise<void> {
    this.store.set(key, value);
  }
}

const createHub = () => {
  const storage = new FakeDurableObjectStorage();
  const state = { storage } as unknown as DurableObjectState;
  const hub = new ConversationEventHub(state, {} as Env);
  return { hub, storage };
};

const readChunks = async (response: Response, count: number): Promise<string> => {
  const reader = response.body?.getReader();
  if (!reader) {
    return '';
  }

  const decoder = new TextDecoder();
  const chunks: string[] = [];
  for (let index = 0; index < count; index += 1) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    if (value) {
      chunks.push(decoder.decode(value));
    }
  }
  await reader.cancel();
  return chunks.join('');
};

describe('ConversationEventHub', () => {
  it('buffers live run deltas with generated stream event ids', async () => {
    const { hub, storage } = createHub();

    await hub.fetch(
      new Request('https://conversation-event-hub/stream-delta', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          type: 'delta',
          data: { runId: 'run_1', textDelta: 'first' },
        }),
      }),
    );

    const history = await storage.get<Array<{ id: string; frame: string }>>('stream-history:run_1');
    expect(history?.length).toBe(1);
    expect(history?.[0]?.id).toBe('stream_run_1_00000001');
    expect(history?.[0]?.frame).toContain('"textDelta":"first"');
  });

  it('replays buffered deltas after the supplied last-event-id', async () => {
    const { hub, storage } = createHub();

    await hub.fetch(
      new Request('https://conversation-event-hub/stream-delta', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          type: 'delta',
          data: { runId: 'run_1', textDelta: 'first' },
        }),
      }),
    );
    await hub.fetch(
      new Request('https://conversation-event-hub/stream-delta', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          type: 'delta',
          data: { runId: 'run_1', textDelta: 'second' },
        }),
      }),
    );

    const history = await storage.get<Array<{ id: string }>>('stream-history:run_1');
    const firstEventID = history?.[0]?.id;
    expect(firstEventID).toBe('stream_run_1_00000001');

    const response = await hub.fetch(
      new Request('https://conversation-event-hub/stream/run_1', {
        headers: {
          'Last-Event-ID': firstEventID ?? '',
        },
      }),
    );
    const body = await readChunks(response, 2);

    expect(body).toContain(': connected');
    expect(body).not.toContain('"textDelta":"first"');
    expect(body).toContain('"textDelta":"second"');
    expect(body).toContain('id: stream_run_1_00000002');
  });

  it('does not replay buffered events when the supplied last-event-id is unknown', async () => {
    const { hub } = createHub();

    await hub.fetch(
      new Request('https://conversation-event-hub/stream-delta', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          type: 'delta',
          data: { runId: 'run_1', textDelta: 'first' },
        }),
      }),
    );

    const response = await hub.fetch(
      new Request('https://conversation-event-hub/stream/run_1', {
        headers: {
          'Last-Event-ID': 'stream_run_1_99999999',
        },
      }),
    );
    const body = await readChunks(response, 1);

    expect(body).toContain(': connected');
    expect(body).not.toContain('"textDelta":"first"');
  });
});
