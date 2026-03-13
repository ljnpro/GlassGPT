import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  RelayRunLimitError,
  RelayRunNotFoundError,
  RelayStore,
  RelayStoreError,
} from '../../server/relay-store';

describe('RelayStore', () => {
  const stores: RelayStore[] = [];

  function createStore(options?: ConstructorParameters<typeof RelayStore>[0]): RelayStore {
    const store = new RelayStore({
      terminalTtlMs: 5_000,
      janitorIntervalMs: 1_000,
      maxActiveRuns: 10,
      maxEventsPerRun: 100,
      maxEventBytesPerRun: 1024 * 1024,
      ...options,
    });
    stores.push(store);
    return store;
  }

  function createRun(store: RelayStore, overrides?: Partial<Parameters<RelayStore['createRun']>[0]>) {
    return store.createRun({
      relayRunId: 'relay_run_1',
      resumeToken: 'secret_resume_1',
      conversationId: 'conv_1',
      clientRequestId: 'client_req_1',
      model: 'gpt-5.4',
      reasoningEffort: 'medium',
      vectorStoreIds: ['vs_1'],
      metadata: { source: 'test' },
      ...overrides,
    });
  }

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-03-13T12:00:00.000Z'));
  });

  afterEach(() => {
    for (const store of stores) {
      store.dispose();
    }
    stores.length = 0;

    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('should create a relay run with valid input and index it by clientRequestId', () => {
    const store = createStore();

    const run = createRun(store);

    expect(run.relayRunId).toBe('relay_run_1');
    expect(run.resumeToken).toBe('secret_resume_1');
    expect(run.conversationId).toBe('conv_1');
    expect(run.clientRequestId).toBe('client_req_1');
    expect(run.model).toBe('gpt-5.4');
    expect(run.reasoningEffort).toBe('medium');
    expect(run.vectorStoreIds).toEqual(['vs_1']);
    expect(run.status).toBe('starting');
    expect(run.responseId).toBeUndefined();
    expect(run.snapshot).toEqual({
      status: 'starting',
      lastSequenceNumber: 0,
      accumulatedText: '',
      accumulatedThinking: '',
      toolCalls: {},
      annotations: [],
      responseId: undefined,
    });
    expect(run.createdAt).toBe(Date.now());
    expect(run.updatedAt).toBe(Date.now());
    expect(run.expiresAt).toBe(Date.now() + 5_000);
    expect(run.eventLog).toEqual([]);
    expect(run.eventIndexBySequence.size).toBe(0);
    expect(run.eventLogBytes).toBe(0);
    expect(run.sockets.size).toBe(0);
    expect(run.openaiStreamActive).toBe(false);
    expect(run.metadata).toEqual({ source: 'test' });

    expect(store.getRun('relay_run_1')).toBe(run);
    expect(store.getRunByClientRequestId('client_req_1')).toBe(run);
  });

  it('should enforce the max active runs limit and allow new runs after terminal transition', () => {
    const store = createStore({ maxActiveRuns: 1 });

    createRun(store, {
      relayRunId: 'relay_active_1',
      clientRequestId: 'client_active_1',
    });

    expect(() =>
      createRun(store, {
        relayRunId: 'relay_active_2',
        clientRequestId: 'client_active_2',
      }),
    ).toThrow(RelayRunLimitError);

    store.markTerminal('relay_active_1', 'completed');

    const replacement = createRun(store, {
      relayRunId: 'relay_active_2',
      clientRequestId: 'client_active_2',
    });

    expect(replacement.relayRunId).toBe('relay_active_2');
    expect(replacement.status).toBe('starting');
  });

  it('should ingest events, track sequence numbers, set responseId, and detect duplicates', () => {
    const store = createStore();
    createRun(store);

    const created = store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.created',
      sequence_number: 1,
      response: {
        id: 'resp_abc123',
        status: 'in_progress',
      },
    });

    expect(created.isDuplicate).toBe(false);
    expect(created.becameTerminal).toBe(false);
    expect(created.cachedEvent?.sequenceNumber).toBe(1);
    expect(created.run.responseId).toBe('resp_abc123');
    expect(created.run.status).toBe('streaming');
    expect(created.run.snapshot.responseId).toBe('resp_abc123');
    expect(created.run.snapshot.lastSequenceNumber).toBe(1);

    const delta = store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.output_text.delta',
      sequence_number: 2,
      delta: 'Hello',
      response_id: 'resp_abc123',
    });

    expect(delta.isDuplicate).toBe(false);
    expect(delta.cachedEvent?.sequenceNumber).toBe(2);
    expect(delta.run.snapshot.accumulatedText).toBe('Hello');
    expect(delta.run.snapshot.lastSequenceNumber).toBe(2);
    expect(delta.run.eventLog).toHaveLength(2);

    const duplicate = store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.output_text.delta',
      sequence_number: 2,
      delta: 'SHOULD_NOT_BE_APPLIED',
      response_id: 'resp_abc123',
    });

    expect(duplicate.isDuplicate).toBe(true);
    expect(duplicate.becameTerminal).toBe(false);
    expect(duplicate.cachedEvent?.sequenceNumber).toBe(2);
    expect(duplicate.run.snapshot.accumulatedText).toBe('Hello');
    expect(duplicate.run.eventLog).toHaveLength(2);
  });

  it.each([
    ['response.completed', 'completed'],
    ['response.incomplete', 'incomplete'],
    ['response.failed', 'failed'],
    ['response.cancelled', 'cancelled'],
  ] as const)(
    'should detect %s as a terminal event and detach stream state',
    (eventType, expectedStatus) => {
      const store = createStore();
      createRun(store, { responseId: 'resp_terminal_1' });

      store.setOpenAIStreamActive('relay_run_1', true);
      store.setAbortController('relay_run_1', new AbortController());

      const result = store.ingestOpenAIEvent('relay_run_1', {
        type: eventType,
        sequence_number: 10,
        response: {
          id: 'resp_terminal_1',
          status:
            expectedStatus === 'completed'
              ? 'completed'
              : expectedStatus === 'incomplete'
                ? 'incomplete'
                : expectedStatus === 'cancelled'
                  ? 'cancelled'
                  : 'failed',
        },
        error:
          expectedStatus === 'failed'
            ? { message: 'Upstream failed' }
            : undefined,
      });

      expect(result.isDuplicate).toBe(false);
      expect(result.becameTerminal).toBe(true);
      expect(result.run.status).toBe(expectedStatus);
      expect(result.run.snapshot.status).toBe(expectedStatus);
      expect(result.run.openaiStreamActive).toBe(false);
      expect(result.run.abortController).toBeUndefined();
      expect(result.run.expiresAt).toBe(Date.now() + 5_000);

      if (expectedStatus === 'failed') {
        expect(result.run.snapshot.finalError).toBe('Upstream failed');
      }
    },
  );

  it('should build snapshots from ingested events with text and reasoning accumulation', () => {
    const store = createStore();
    createRun(store);

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.created',
      sequence_number: 1,
      response: {
        id: 'resp_snapshot_1',
        status: 'in_progress',
      },
    });

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.output_text.delta',
      sequence_number: 2,
      delta: 'Hello ',
      response_id: 'resp_snapshot_1',
    });

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.output_text.delta',
      sequence_number: 3,
      delta: 'world',
      response_id: 'resp_snapshot_1',
    });

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.reasoning_text.delta',
      sequence_number: 4,
      delta: 'Thinking...',
      response_id: 'resp_snapshot_1',
    });

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.output_text.annotation.added',
      sequence_number: 5,
      response_id: 'resp_snapshot_1',
      annotation: {
        type: 'url_citation',
        url: 'https://example.com',
        title: 'Example Source',
      },
    } as any);

    const run = store.requireRun('relay_run_1');

    expect(run.responseId).toBe('resp_snapshot_1');
    expect(run.status).toBe('streaming');
    expect(run.snapshot.status).toBe('streaming');
    expect(run.snapshot.lastSequenceNumber).toBe(5);
    expect(run.snapshot.accumulatedText).toBe('Hello world');
    expect(run.snapshot.accumulatedThinking).toBe('Thinking...');
    expect(run.snapshot.annotations).toEqual([
      {
        type: 'url_citation',
        url: 'https://example.com',
        title: 'Example Source',
      },
    ]);
  });

  it('should list replay events after a given sequence number for reconnection', () => {
    const store = createStore();
    createRun(store);

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.created',
      sequence_number: 1,
      response: { id: 'resp_replay_1', status: 'in_progress' },
    });

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.output_text.delta',
      sequence_number: 2,
      delta: 'A',
      response_id: 'resp_replay_1',
    });

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.output_text.delta',
      sequence_number: 3,
      delta: 'B',
      response_id: 'resp_replay_1',
    });

    const replayAfterZero = store.listReplayEventsAfter('relay_run_1', 0);
    const replayAfterOne = store.listReplayEventsAfter('relay_run_1', 1);
    const replayAfterThree = store.listReplayEventsAfter('relay_run_1', 3);

    expect(replayAfterZero.map((event) => event.sequenceNumber)).toEqual([1, 2, 3]);
    expect(replayAfterOne.map((event) => event.sequenceNumber)).toEqual([2, 3]);
    expect(replayAfterThree).toEqual([]);
  });

  it('should attach and detach sockets from runs', () => {
    const store = createStore();
    createRun(store);

    store.attachSocket('relay_run_1', 'socket_1');
    store.attachSocket('relay_run_1', 'socket_2');

    let run = store.requireRun('relay_run_1');
    expect([...run.sockets]).toEqual(['socket_1', 'socket_2']);

    store.detachSocket('relay_run_1', 'socket_1');
    run = store.requireRun('relay_run_1');
    expect([...run.sockets]).toEqual(['socket_2']);

    store.detachSocketFromAll('socket_2');
    run = store.requireRun('relay_run_1');
    expect(run.sockets.size).toBe(0);
  });

  it('should let the TTL janitor clean up expired terminal runs while preserving active runs', () => {
    const store = createStore({
      terminalTtlMs: 1_000,
      janitorIntervalMs: 500,
    });

    createRun(store, {
      relayRunId: 'relay_terminal',
      clientRequestId: 'client_terminal',
    });
    createRun(store, {
      relayRunId: 'relay_active',
      clientRequestId: 'client_active',
    });

    store.markTerminal('relay_terminal', 'completed');

    expect(store.getRun('relay_terminal')).toBeDefined();
    expect(store.getRun('relay_active')).toBeDefined();

    vi.advanceTimersByTime(1_600);

    expect(store.getRun('relay_terminal')).toBeUndefined();
    expect(store.getRun('relay_active')).toBeDefined();
  });

  it('should return a defensive RelayStatusResponse shape', () => {
    const store = createStore();
    createRun(store, {
      responseId: 'resp_status_1',
      vectorStoreIds: ['vs_1', 'vs_2'],
    });

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.web_search_call.searching',
      sequence_number: 1,
      response_id: 'resp_status_1',
      item_id: 'web_1',
      query: 'relay status',
    } as any);

    store.ingestOpenAIEvent('relay_run_1', {
      type: 'response.output_text.annotation.added',
      sequence_number: 2,
      response_id: 'resp_status_1',
      annotation: {
        type: 'url_citation',
        url: 'https://example.com/status',
      },
    } as any);

    const status = store.toStatusResponse('relay_run_1');

    expect(status).toMatchObject({
      relayRunId: 'relay_run_1',
      conversationId: 'conv_1',
      clientRequestId: 'client_req_1',
      responseId: 'resp_status_1',
      model: 'gpt-5.4',
      reasoningEffort: 'medium',
      vectorStoreIds: ['vs_1', 'vs_2'],
      status: 'starting',
      openaiStreamActive: false,
      lastSequenceNumber: 2,
    });
    expect(status.snapshot.toolCalls).toHaveProperty('web_1');
    expect(status.snapshot.annotations).toHaveLength(1);

    status.vectorStoreIds.push('mutated');
    (status.snapshot.toolCalls as Record<string, unknown>).mutated = true;
    status.snapshot.annotations.push({ mutated: true });

    const original = store.requireRun('relay_run_1');
    expect(original.vectorStoreIds).toEqual(['vs_1', 'vs_2']);
    expect((original.snapshot.toolCalls as Record<string, unknown>).mutated).toBeUndefined();
    expect(original.snapshot.annotations).toHaveLength(1);
  });

  it('should throw meaningful errors for missing runs and duplicate run IDs', () => {
    const store = createStore();

    expect(() => store.requireRun('missing_run')).toThrow(RelayRunNotFoundError);

    createRun(store);

    expect(() =>
      createRun(store, {
        relayRunId: 'relay_run_1',
        clientRequestId: 'client_req_duplicate',
      }),
    ).toThrow(RelayStoreError);

    expect(() =>
      store.ingestOpenAIEvent('missing_run', {
        type: 'response.created',
        sequence_number: 1,
      }),
    ).toThrow(RelayRunNotFoundError);
  });
});
