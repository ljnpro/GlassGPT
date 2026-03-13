import express from 'express';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AddressInfo } from 'node:net';

import { applyEventToSnapshot, extractResponseId, extractSequenceNumber } from '../../server/openai-event-normalizer';
import { OpenAIRelayService } from '../../server/openai-relay';
import { registerRelayRoutes } from '../../server/relay-routes';
import { RelayStore } from '../../server/relay-store';
import { registerRelaySocketHandlers } from '../../server/relay-socket';
import {
  createIpRateLimitMiddleware,
  redactApiKey,
  requireBearerApiKey,
  validateCreateRunRequest,
} from '../../server/relay-security';
import { RELAY_HTTP_BASE_PATH, relayRunRoom } from '../../server/relay-types';

/**
 * Integration-oriented tests for the relay server system.
 *
 * These tests intentionally avoid supertest and instead:
 * 1. Mount the real Express router into a real Express app.
 * 2. Start an ephemeral local HTTP server and call it with fetch().
 * 3. Mock only true external boundaries, especially OpenAI fetch calls and Socket.IO objects.
 * 4. Exercise event normalization, route validation, socket handler registration,
 *    and streaming behavior independently.
 */

type RouteHarness = Awaited<ReturnType<typeof createRouteHarness>>;

const cleanupTasks: Array<() => Promise<void> | void> = [];

function registerCleanup(task: () => Promise<void> | void) {
  cleanupTasks.push(task);
}

async function flushPromises(times: number = 3): Promise<void> {
  for (let i = 0; i < times; i += 1) {
    await Promise.resolve();
  }
}

async function createRouteHarness() {
  const store = new RelayStore({
    terminalTtlMs: 60_000,
    janitorIntervalMs: 60_000,
  });

  const relay = {
    startBackgroundStream: vi.fn().mockResolvedValue(undefined),
    cancelRun: vi.fn(),
    uploadFile: vi.fn(),
  };

  const app = express();
  app.use(express.json());

  registerRelayRoutes(app, {
    store,
    relay: relay as any,
  });

  const server = await new Promise<import('node:http').Server>((resolve) => {
    const started = app.listen(0, () => resolve(started));
  });

  const address = server.address() as AddressInfo;
  const baseUrl = `http://127.0.0.1:${address.port}${RELAY_HTTP_BASE_PATH}`;

  const close = async () => {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
    store.dispose();
  };

  registerCleanup(close);

  return {
    app,
    server,
    baseUrl,
    store,
    relay,
    close,
  };
}

function createStreamingSSE(chunks: string[]): Response {
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(encoder.encode(chunk));
      }
      controller.close();
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      'Content-Type': 'text/event-stream',
    },
  });
}

function createBroadcastIoMock() {
  const emit = vi.fn();
  const io = {
    to: vi.fn(() => ({
      emit,
    })),
  };

  return {
    io: io as any,
    emit,
  };
}

function createSocketServerHarness() {
  let connectionHandler: ((socket: any) => void) | undefined;

  const io = {
    on: vi.fn((event: string, handler: (socket: any) => void) => {
      if (event === 'connection') {
        connectionHandler = handler;
      }
      return io;
    }),
    to: vi.fn(() => ({
      emit: vi.fn(),
    })),
  };

  function createSocket(id: string = 'socket_1') {
    const handlers = new Map<string, (...args: any[]) => void>();

    const socket = {
      id,
      data: {},
      on: vi.fn((event: string, handler: (...args: any[]) => void) => {
        handlers.set(event, handler);
        return socket;
      }),
      emit: vi.fn(),
      join: vi.fn().mockResolvedValue(undefined),
      leave: vi.fn().mockResolvedValue(undefined),
    };

    return {
      socket: socket as any,
      handlers,
    };
  }

  function connect(socket: any) {
    if (!connectionHandler) {
      throw new Error('Socket connection handler was not registered');
    }
    connectionHandler(socket);
  }

  return {
    io: io as any,
    createSocket,
    connect,
  };
}

function emittedPayloads(socket: { emit: ReturnType<typeof vi.fn> }, eventName: string) {
  return socket.emit.mock.calls
    .filter(([name]) => name === eventName)
    .map(([, payload]) => payload);
}

afterEach(async () => {
  while (cleanupTasks.length > 0) {
    const task = cleanupTasks.pop();
    await task?.();
  }

  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe('Relay HTTP routes', () => {
  it('POST /api/relay/runs should create a run and return relayRunId + resumeToken', async () => {
    const harness = await createRouteHarness();

    const requestBody = {
      clientRequestId: 'client_req_http_1',
      conversationId: 'conv_http_1',
      messages: [{ role: 'user', content: 'Hello relay' }],
      model: 'gpt-5.4',
      reasoningEffort: 'low',
      vectorStoreIds: ['vs_alpha'],
      metadata: { screen: 'composer' },
    };

    const response = await fetch(`${harness.baseUrl}/runs`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer sk-test-route',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    });

    const json = await response.json();

    expect(response.status).toBe(202);
    expect(json).toMatchObject({
      relayRunId: expect.stringMatching(/^relay_/),
      resumeToken: expect.stringMatching(/^secret_/),
      status: 'starting',
    });

    expect(harness.store.getRun(json.relayRunId)).toBeDefined();

    await flushPromises();

    expect(harness.relay.startBackgroundStream).toHaveBeenCalledTimes(1);
    expect(harness.relay.startBackgroundStream).toHaveBeenCalledWith({
      relayRunId: json.relayRunId,
      apiKey: 'sk-test-route',
      request: requestBody,
    });
  });

  it('POST /api/relay/runs/:id/cancel should cancel a run', async () => {
    const harness = await createRouteHarness();

    const run = harness.store.createRun({
      relayRunId: 'relay_cancel_1',
      resumeToken: 'secret_cancel_1',
      conversationId: 'conv_cancel_1',
      clientRequestId: 'client_cancel_1',
      model: 'gpt-5.4',
      reasoningEffort: 'none',
      vectorStoreIds: [],
      responseId: 'resp_cancel_1',
      status: 'streaming',
    });

    harness.relay.cancelRun.mockResolvedValue({
      relayRunId: run.relayRunId,
      status: 'cancelled',
      responseId: run.responseId,
    });

    const response = await fetch(`${harness.baseUrl}/runs/${run.relayRunId}/cancel`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer sk-test-cancel',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        resumeToken: 'secret_cancel_1',
      }),
    });

    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json).toEqual({
      ok: true,
      relayRunId: 'relay_cancel_1',
      status: 'cancelled',
      responseId: 'resp_cancel_1',
    });

    expect(harness.relay.cancelRun).toHaveBeenCalledWith({
      relayRunId: 'relay_cancel_1',
      apiKey: 'sk-test-cancel',
    });
  });

  it('GET /api/relay/runs/:id/status should return the current status', async () => {
    const harness = await createRouteHarness();

    harness.store.createRun({
      relayRunId: 'relay_status_1',
      resumeToken: 'secret_status_1',
      conversationId: 'conv_status_1',
      clientRequestId: 'client_status_1',
      model: 'gpt-5.4',
      reasoningEffort: 'minimal',
      vectorStoreIds: ['vs_status_1'],
      responseId: 'resp_status_1',
      status: 'starting',
    });

    harness.store.ingestOpenAIEvent('relay_status_1', {
      type: 'response.created',
      sequence_number: 1,
      response: {
        id: 'resp_status_1',
        status: 'in_progress',
      },
    });

    harness.store.ingestOpenAIEvent('relay_status_1', {
      type: 'response.output_text.delta',
      sequence_number: 2,
      response_id: 'resp_status_1',
      delta: 'Hello status',
    });

    const response = await fetch(
      `${harness.baseUrl}/runs/relay_status_1/status?resumeToken=secret_status_1`,
      {
        method: 'GET',
      },
    );

    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json).toMatchObject({
      relayRunId: 'relay_status_1',
      conversationId: 'conv_status_1',
      clientRequestId: 'client_status_1',
      responseId: 'resp_status_1',
      status: 'streaming',
      model: 'gpt-5.4',
      reasoningEffort: 'minimal',
      vectorStoreIds: ['vs_status_1'],
      lastSequenceNumber: 2,
      snapshot: {
        responseId: 'resp_status_1',
        status: 'streaming',
        accumulatedText: 'Hello status',
      },
    });
  });

  it('POST /api/relay/files should upload a file through the relay service', async () => {
    const harness = await createRouteHarness();

    harness.relay.uploadFile.mockResolvedValue({
      fileId: 'file_123',
      filename: 'notes.txt',
      contentType: 'text/plain',
      bytes: 5,
    });

    const form = new FormData();
    form.append('file', new Blob(['hello'], { type: 'text/plain' }), 'notes.txt');

    const response = await fetch(`${harness.baseUrl}/files`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer sk-test-upload',
      },
      body: form,
    });

    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json).toEqual({
      fileId: 'file_123',
      filename: 'notes.txt',
      contentType: 'text/plain',
      bytes: 5,
    });

    expect(harness.relay.uploadFile).toHaveBeenCalledTimes(1);
    expect(harness.relay.uploadFile).toHaveBeenCalledWith(
      expect.objectContaining({
        apiKey: 'sk-test-upload',
        filename: 'notes.txt',
        contentType: 'text/plain',
        buffer: expect.any(Buffer),
      }),
    );
  });

  it('should reject requests with a missing API key', async () => {
    const harness = await createRouteHarness();

    const response = await fetch(`${harness.baseUrl}/runs`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        clientRequestId: 'client_req_invalid',
        conversationId: 'conv_invalid',
        messages: [{ role: 'user', content: 'hello' }],
        model: 'gpt-5.4',
      }),
    });

    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json).toEqual({
      error: {
        code: 'missing_api_key',
        message: 'Missing Authorization bearer token',
        retryable: false,
        details: undefined,
      },
    });
  });

  it('should reject invalid run request bodies', async () => {
    const harness = await createRouteHarness();

    const response = await fetch(`${harness.baseUrl}/runs`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer sk-test-invalid-body',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        clientRequestId: 'client_req_invalid_body',
        conversationId: 'conv_invalid_body',
        messages: [],
        model: 'gpt-5.4',
      }),
    });

    const json = await response.json();

    expect(response.status).toBe(400);
    expect(json.error.code).toBe('invalid_request');
    expect(json.error.message).toContain('messages must be a non-empty array');
  });

  it('should reject blocked file types during upload validation', async () => {
    const harness = await createRouteHarness();

    const form = new FormData();
    form.append(
      'file',
      new Blob(['not really an exe'], { type: 'application/octet-stream' }),
      'malware.exe',
    );

    const response = await fetch(`${harness.baseUrl}/files`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer sk-test-blocked-file',
      },
      body: form,
    });

    const json = await response.json();

    expect(response.status).toBe(400);
    expect(json.error.code).toBe('invalid_request');
    expect(json.error.message).toContain('.exe');
  });
});

describe('OpenAIRelayService streaming integration', () => {
  it('should consume chunked SSE events, normalize them into the store, and emit relay events', async () => {
    const store = new RelayStore({
      terminalTtlMs: 60_000,
      janitorIntervalMs: 60_000,
    });
    registerCleanup(() => store.dispose());

    const { io, emit } = createBroadcastIoMock();
    const service = new OpenAIRelayService(store, io, {
      openAIBaseUrl: 'https://api.openai.example/v1',
      maxAutoResumeAttempts: 0,
    });

    store.createRun({
      relayRunId: 'relay_stream_1',
      resumeToken: 'secret_stream_1',
      conversationId: 'conv_stream_1',
      clientRequestId: 'client_stream_1',
      model: 'gpt-5.4',
      reasoningEffort: 'medium',
      vectorStoreIds: ['vs_stream_1'],
      status: 'starting',
    });

    const fetchMock = vi.fn().mockResolvedValue(
      createStreamingSSE([
        ': keepalive comment ignored by parser\n\n',
        'event: response.created\n',
        'data: {"sequence_number":1,"response":{"id":"resp_stream_1","status":"in_progress"}}\n\n',
        'data: {"type":"response.output_text.delta","sequence_number":2,"response_id":"resp_stream_1","delta":"Hello "}\n\n',
        'data: {"type":"response.completed","sequence_number":3,"response":{"id":"resp_stream_1","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Hello world"}]}]}}\n\n',
        'data: [DONE]\n\n',
      ]),
    );

    vi.stubGlobal('fetch', fetchMock);

    await service.startBackgroundStream({
      relayRunId: 'relay_stream_1',
      apiKey: 'sk-test-openai',
      request: {
        clientRequestId: 'client_stream_1',
        conversationId: 'conv_stream_1',
        messages: [{ role: 'user', content: 'say hi' }],
        model: 'gpt-5.4',
        reasoningEffort: 'medium',
        vectorStoreIds: ['vs_stream_1'],
        metadata: { source: 'integration-test' },
      },
    });

    const run = store.requireRun('relay_stream_1');

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledWith(
      'https://api.openai.example/v1/responses',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          Authorization: 'Bearer sk-test-openai',
          Accept: 'text/event-stream',
          'Content-Type': 'application/json',
          'X-Client-Request-Id': 'client_stream_1',
        }),
        signal: expect.any(AbortSignal),
      }),
    );

    expect(run.responseId).toBe('resp_stream_1');
    expect(run.status).toBe('completed');
    expect(run.snapshot.status).toBe('completed');
    expect(run.snapshot.lastSequenceNumber).toBe(3);
    expect(run.snapshot.accumulatedText).toBe('Hello world');
    expect(run.openaiStreamActive).toBe(false);

    expect(io.to).toHaveBeenCalledWith(relayRunRoom('relay_stream_1'));

    const emittedEventNames = emit.mock.calls.map(([eventName]) => eventName);
    expect(emittedEventNames).toContain('relay:event');
    expect(emittedEventNames).toContain('relay:done');

    const liveEvents = emit.mock.calls
      .filter(([eventName]) => eventName === 'relay:event')
      .map(([, payload]) => payload);

    expect(liveEvents).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          relayRunId: 'relay_stream_1',
          replay: false,
          sequenceNumber: 1,
          event: expect.objectContaining({
            type: 'response.created',
          }),
        }),
        expect.objectContaining({
          relayRunId: 'relay_stream_1',
          replay: false,
          sequenceNumber: 2,
          event: expect.objectContaining({
            type: 'response.output_text.delta',
            delta: 'Hello ',
          }),
        }),
      ]),
    );
  });
});

describe('OpenAI event normalization', () => {
  function createSnapshot() {
    return {
      status: 'starting' as const,
      lastSequenceNumber: 0,
      accumulatedText: '',
      accumulatedThinking: '',
      toolCalls: {},
      annotations: [] as unknown[],
      responseId: undefined as string | undefined,
      finalError: undefined as string | undefined,
    };
  }

  it('should extract responseId and sequence number from stream events', () => {
    const event = {
      type: 'response.created',
      sequence_number: 42,
      response: {
        id: 'resp_extract_42',
        status: 'in_progress',
      },
    };

    expect(extractSequenceNumber(event)).toBe(42);
    expect(extractResponseId(event)).toBe('resp_extract_42');

    expect(
      extractResponseId({
        response_id: 'resp_direct_1',
      }),
    ).toBe('resp_direct_1');
  });

  it('should accumulate text, reasoning, tool calls, and citations across streamed events', () => {
    const snapshot = createSnapshot();

    applyEventToSnapshot(snapshot, {
      type: 'response.created',
      sequence_number: 1,
      response: {
        id: 'resp_norm_1',
        status: 'in_progress',
      },
    });

    applyEventToSnapshot(snapshot, {
      type: 'response.output_text.delta',
      sequence_number: 2,
      response_id: 'resp_norm_1',
      delta: 'Hello ',
    });

    applyEventToSnapshot(snapshot, {
      type: 'response.reasoning_text.delta',
      sequence_number: 3,
      response_id: 'resp_norm_1',
      delta: 'Thinking...',
    });

    applyEventToSnapshot(snapshot, {
      type: 'response.web_search_call.searching',
      sequence_number: 4,
      response_id: 'resp_norm_1',
      item_id: 'web_call_1',
      query: 'relay testing best practices',
    } as any);

    applyEventToSnapshot(snapshot, {
      type: 'response.code_interpreter_call.interpreting',
      sequence_number: 5,
      response_id: 'resp_norm_1',
      item_id: 'code_call_1',
      input: 'print("hello")',
    } as any);

    applyEventToSnapshot(snapshot, {
      type: 'response.file_search_call.searching',
      sequence_number: 6,
      response_id: 'resp_norm_1',
      item_id: 'file_call_1',
      queries: ['relay design'],
    } as any);

    applyEventToSnapshot(snapshot, {
      type: 'response.output_text.annotation.added',
      sequence_number: 7,
      response_id: 'resp_norm_1',
      annotation: {
        type: 'url_citation',
        url: 'https://example.com/citation',
        title: 'Citation',
      },
    } as any);

    expect(snapshot.responseId).toBe('resp_norm_1');
    expect(snapshot.status).toBe('streaming');
    expect(snapshot.lastSequenceNumber).toBe(7);
    expect(snapshot.accumulatedText).toBe('Hello ');
    expect(snapshot.accumulatedThinking).toBe('Thinking...');
    expect(snapshot.toolCalls).toHaveProperty('web_call_1');
    expect(snapshot.toolCalls).toHaveProperty('code_call_1');
    expect(snapshot.toolCalls).toHaveProperty('file_call_1');
    expect(snapshot.annotations).toEqual([
      {
        type: 'url_citation',
        url: 'https://example.com/citation',
        title: 'Citation',
      },
    ]);
  });

  it('should mark response.completed as terminal and extract full output text', () => {
    const snapshot = createSnapshot();

    applyEventToSnapshot(snapshot, {
      type: 'response.completed',
      sequence_number: 99,
      response: {
        id: 'resp_completed_1',
        status: 'completed',
        output: [
          {
            type: 'message',
            content: [
              {
                type: 'output_text',
                text: 'Final answer',
                annotations: [{ type: 'url_citation', url: 'https://example.com/final' }],
              },
            ],
          },
          {
            type: 'reasoning',
            text: 'Final reasoning summary',
          },
          {
            type: 'web_search_call',
            id: 'tool_final_1',
            query: 'summary query',
          },
        ],
      },
    } as any);

    expect(snapshot.status).toBe('completed');
    expect(snapshot.responseId).toBe('resp_completed_1');
    expect(snapshot.lastSequenceNumber).toBe(99);
    expect(snapshot.accumulatedText).toBe('Final answer');
    expect(snapshot.accumulatedThinking).toBe('Final reasoning summary');
    expect(snapshot.toolCalls).toHaveProperty('tool_final_1');
    expect(snapshot.annotations).toEqual([
      {
        type: 'url_citation',
        url: 'https://example.com/final',
      },
    ]);
  });

  it('should mark response.failed as terminal and capture the error message', () => {
    const snapshot = createSnapshot();

    applyEventToSnapshot(snapshot, {
      type: 'response.failed',
      sequence_number: 12,
      response: {
        id: 'resp_failed_1',
        status: 'failed',
      },
      error: {
        message: 'OpenAI upstream failure',
      },
    });

    expect(snapshot.status).toBe('failed');
    expect(snapshot.responseId).toBe('resp_failed_1');
    expect(snapshot.lastSequenceNumber).toBe(12);
    expect(snapshot.finalError).toBe('OpenAI upstream failure');
  });
});

describe('Relay security helpers', () => {
  it('should extract a bearer API key from the Authorization header', () => {
    const apiKey = requireBearerApiKey({
      headers: {
        authorization: 'Bearer sk-secret-value',
      },
    } as any);

    expect(apiKey).toBe('sk-secret-value');
  });

  it('should redact API keys safely for logging', () => {
    expect(redactApiKey(undefined)).toBe('<empty>');
    expect(redactApiKey('shortkey')).toBe('sh***');
    expect(redactApiKey('sk-1234567890abcdef')).toBe('sk-1234...cdef');
  });

  it('should validate and normalize a create-run request body', () => {
    const parsed = validateCreateRunRequest({
      clientRequestId: ' client_req_1 ',
      conversationId: ' conv_1 ',
      messages: ['hello', { role: 'user', content: 'there' }],
      model: ' gpt-5.4 ',
      reasoningEffort: ' medium ',
      vectorStoreIds: [' vs_1 ', 'vs_2'],
      metadata: { platform: 'ios' },
    });

    expect(parsed).toEqual({
      clientRequestId: 'client_req_1',
      conversationId: 'conv_1',
      messages: ['hello', { role: 'user', content: 'there' }],
      model: 'gpt-5.4',
      reasoningEffort: 'medium',
      vectorStoreIds: ['vs_1', 'vs_2'],
      metadata: { platform: 'ios' },
    });
  });

  it('should enforce IP rate limiting and reset after the time window', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-03-13T00:00:00.000Z'));

    const limiter = createIpRateLimitMiddleware({
      windowMs: 1_000,
      maxRequests: 2,
    });

    const req = {
      headers: {
        'x-forwarded-for': '203.0.113.10',
      },
      ip: '203.0.113.10',
      socket: {
        remoteAddress: '203.0.113.10',
      },
    } as any;

    const res = {
      status: vi.fn().mockReturnThis(),
      json: vi.fn(),
    } as any;

    const next = vi.fn();

    limiter(req, res, next);
    limiter(req, res, next);
    limiter(req, res, next);

    expect(next).toHaveBeenCalledTimes(2);
    expect(res.status).toHaveBeenCalledWith(429);
    expect(res.json).toHaveBeenCalledWith({
      error: {
        code: 'rate_limited',
        message: 'Too many requests',
        retryable: true,
      },
    });

    vi.advanceTimersByTime(1_001);

    limiter(req, res, next);

    expect(next).toHaveBeenCalledTimes(3);
  });
});

describe('Relay socket handler integration', () => {
  it('should replay missed events on relay:join and emit terminal done payloads', async () => {
    const store = new RelayStore({
      terminalTtlMs: 60_000,
      janitorIntervalMs: 60_000,
    });
    registerCleanup(() => store.dispose());

    store.createRun({
      relayRunId: 'relay_socket_join_1',
      resumeToken: 'secret_socket_join_1',
      conversationId: 'conv_socket_join_1',
      clientRequestId: 'client_socket_join_1',
      model: 'gpt-5.4',
      reasoningEffort: 'low',
      vectorStoreIds: [],
      responseId: 'resp_socket_join_1',
      status: 'starting',
    });

    store.ingestOpenAIEvent('relay_socket_join_1', {
      type: 'response.created',
      sequence_number: 1,
      response: {
        id: 'resp_socket_join_1',
        status: 'in_progress',
      },
    });

    store.ingestOpenAIEvent('relay_socket_join_1', {
      type: 'response.output_text.delta',
      sequence_number: 2,
      response_id: 'resp_socket_join_1',
      delta: 'Hello',
    });

    store.ingestOpenAIEvent('relay_socket_join_1', {
      type: 'response.completed',
      sequence_number: 3,
      response: {
        id: 'resp_socket_join_1',
        status: 'completed',
        output: [
          {
            type: 'message',
            content: [{ type: 'output_text', text: 'Hello world' }],
          },
        ],
      },
    } as any);

    const relay = {
      resumeBackgroundStream: vi.fn().mockResolvedValue(undefined),
      cancelRun: vi.fn(),
    };

    const socketHarness = createSocketServerHarness();
    registerRelaySocketHandlers(socketHarness.io, {
      store,
      relay: relay as any,
    });

    const { socket, handlers } = socketHarness.createSocket('socket_join_1');
    socketHarness.connect(socket);

    const ack = vi.fn();

    handlers.get('relay:join')?.(
      {
        relayRunId: 'relay_socket_join_1',
        resumeToken: 'secret_socket_join_1',
        lastSequenceNumber: 1,
      },
      ack,
    );

    await flushPromises();

    expect(socket.join).toHaveBeenCalledWith('run:relay_socket_join_1');

    const emittedNames = socket.emit.mock.calls.map(([eventName]) => eventName);
    expect(emittedNames).toEqual(['relay:joined', 'relay:event', 'relay:event', 'relay:done']);

    const joinedPayload = emittedPayloads(socket, 'relay:joined')[0];
    expect(joinedPayload).toEqual({
      relayRunId: 'relay_socket_join_1',
      responseId: 'resp_socket_join_1',
      status: 'completed',
      serverLastSequenceNumber: 3,
    });

    const replayEvents = emittedPayloads(socket, 'relay:event');
    expect(replayEvents).toEqual([
      {
        relayRunId: 'relay_socket_join_1',
        sequenceNumber: 2,
        replay: true,
        event: expect.objectContaining({
          type: 'response.output_text.delta',
          delta: 'Hello',
        }),
      },
      {
        relayRunId: 'relay_socket_join_1',
        sequenceNumber: 3,
        replay: true,
        event: expect.objectContaining({
          type: 'response.completed',
        }),
      },
    ]);

    const donePayload = emittedPayloads(socket, 'relay:done')[0];
    expect(donePayload).toEqual({
      relayRunId: 'relay_socket_join_1',
      status: 'completed',
      responseId: 'resp_socket_join_1',
      lastSequenceNumber: 3,
    });

    expect(ack).toHaveBeenCalledWith({
      ok: true,
      replayed: 2,
      terminal: true,
    });
  });

  it('should create a transient run on relay:resume-openai and invoke background resume', async () => {
    const store = new RelayStore({
      terminalTtlMs: 60_000,
      janitorIntervalMs: 60_000,
    });
    registerCleanup(() => store.dispose());

    const relay = {
      resumeBackgroundStream: vi.fn().mockResolvedValue(undefined),
      cancelRun: vi.fn(),
    };

    const socketHarness = createSocketServerHarness();
    registerRelaySocketHandlers(socketHarness.io, {
      store,
      relay: relay as any,
    });

    const { socket, handlers } = socketHarness.createSocket('socket_resume_1');
    socketHarness.connect(socket);

    const ack = vi.fn();

    handlers.get('relay:resume-openai')?.(
      {
        relayRunId: 'relay_transient_1',
        resumeToken: 'secret_transient_1',
        responseId: 'resp_transient_1',
        lastSequenceNumber: 5,
        apiKey: 'sk-test-resume',
      },
      ack,
    );

    await flushPromises();

    const transientRun = store.requireRun('relay_transient_1');

    expect(transientRun.resumeToken).toBe('secret_transient_1');
    expect(transientRun.responseId).toBe('resp_transient_1');
    expect(transientRun.status).toBe('streaming');

    expect(socket.join).toHaveBeenCalledWith('run:relay_transient_1');

    const joinedPayload = emittedPayloads(socket, 'relay:joined')[0];
    expect(joinedPayload).toEqual({
      relayRunId: 'relay_transient_1',
      responseId: 'resp_transient_1',
      status: 'streaming',
      serverLastSequenceNumber: 0,
    });

    const livePayload = emittedPayloads(socket, 'relay:live')[0];
    expect(livePayload).toEqual({
      relayRunId: 'relay_transient_1',
      afterSequenceNumber: 0,
    });

    expect(relay.resumeBackgroundStream).toHaveBeenCalledWith({
      relayRunId: 'relay_transient_1',
      apiKey: 'sk-test-resume',
      responseId: 'resp_transient_1',
      startingAfter: 5,
    });

    expect(ack).toHaveBeenCalledWith({
      ok: true,
      replayed: 0,
      terminal: false,
    });
  });

  it('should emit a forbidden socket error payload when the resume token is invalid', async () => {
    const store = new RelayStore({
      terminalTtlMs: 60_000,
      janitorIntervalMs: 60_000,
    });
    registerCleanup(() => store.dispose());

    store.createRun({
      relayRunId: 'relay_socket_error_1',
      resumeToken: 'secret_valid_token',
      conversationId: 'conv_socket_error_1',
      clientRequestId: 'client_socket_error_1',
      model: 'gpt-5.4',
      reasoningEffort: 'none',
      vectorStoreIds: [],
      status: 'starting',
    });

    const relay = {
      resumeBackgroundStream: vi.fn().mockResolvedValue(undefined),
      cancelRun: vi.fn(),
    };

    const socketHarness = createSocketServerHarness();
    registerRelaySocketHandlers(socketHarness.io, {
      store,
      relay: relay as any,
    });

    const { socket, handlers } = socketHarness.createSocket('socket_error_1');
    socketHarness.connect(socket);

    const ack = vi.fn();

    handlers.get('relay:join')?.(
      {
        relayRunId: 'relay_socket_error_1',
        resumeToken: 'secret_wrong_token',
      },
      ack,
    );

    await flushPromises();

    const errorPayload = emittedPayloads(socket, 'relay:error')[0];
    expect(errorPayload).toEqual({
      relayRunId: 'relay_socket_error_1',
      code: 'forbidden',
      message: 'Invalid relay resume token',
      retryable: false,
    });

    expect(ack).toHaveBeenCalledWith({
      ok: false,
      relayRunId: 'relay_socket_error_1',
      code: 'forbidden',
      message: 'Invalid relay resume token',
      retryable: false,
    });
  });
});
