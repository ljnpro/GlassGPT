import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  createChatCompletion,
  createStreamingChatCompletion,
  createStreamingResponse,
} from './openai-responses.js';

const makeStreamingResponse = (payload: unknown): Response => {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(`data: ${JSON.stringify(payload)}\n\n`));
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream' },
    status: 200,
  });
};

const makeSSEStream = (payloads: Array<unknown | '[DONE]'>): Response => {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const payload of payloads) {
        const data = payload === '[DONE]' ? '[DONE]' : JSON.stringify(payload);
        controller.enqueue(encoder.encode(`data: ${data}\n\n`));
      }
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream' },
    status: 200,
  });
};

describe('createStreamingResponse request body', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('includes an input_image data URL when imageBase64 is provided', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      makeStreamingResponse({
        response: {
          output: [
            {
              content: [{ text: 'Image summary', type: 'output_text' }],
              role: 'assistant',
              type: 'message',
            },
          ],
          output_text: 'Image summary',
        },
        type: 'response.completed',
      }),
    );

    const iterator = createStreamingResponse('sk-image', {
      imageBase64: 'ZmFrZS1pbWFnZQ==',
      input: 'Describe the image',
    });

    await iterator.next();

    const init = fetchMock.mock.calls[0]?.[1] as RequestInit | undefined;
    const body = JSON.parse(String(init?.body));
    expect(body.input).toEqual([
      {
        content: [
          { text: 'Describe the image', type: 'input_text' },
          {
            image_url: 'data:image/jpeg;base64,ZmFrZS1pbWFnZQ==',
            type: 'input_image',
          },
        ],
        role: 'user',
      },
    ]);
  });

  it('includes input_file parts without forcing an empty input_text part', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      makeStreamingResponse({
        response: {
          output: [
            {
              content: [{ text: 'File summary', type: 'output_text' }],
              role: 'assistant',
              type: 'message',
            },
          ],
          output_text: 'File summary',
        },
        type: 'response.completed',
      }),
    );

    const iterator = createStreamingResponse('sk-file', {
      fileIds: ['file_123'],
      input: '',
    });

    await iterator.next();

    const init = fetchMock.mock.calls[0]?.[1] as RequestInit | undefined;
    const body = JSON.parse(String(init?.body));
    expect(body.input).toEqual([
      {
        content: [{ file_id: 'file_123', type: 'input_file' }],
        role: 'user',
      },
    ]);
  });

  it('maps array input and only attaches files and images to the final user message', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      makeStreamingResponse({
        response: {
          output: [
            {
              content: [{ text: 'Array summary', type: 'output_text' }],
              role: 'assistant',
              type: 'message',
            },
          ],
          output_text: 'Array summary',
        },
        type: 'response.completed',
      }),
    );

    const iterator = createStreamingResponse('sk-array', {
      fileIds: ['file_a', 'file_b'],
      imageBase64: 'aGVsbG8=',
      input: [
        { content: 'Context message', role: 'system' },
        { content: 'Previous assistant reply', role: 'assistant' },
        { content: 'Last user prompt', role: 'user' },
      ],
      model: 'gpt-5.4-mini',
      reasoningEffort: 'high',
      serviceTier: 'flex',
    });

    await iterator.next();

    const init = fetchMock.mock.calls[0]?.[1] as RequestInit | undefined;
    const body = JSON.parse(String(init?.body));
    expect(body).toMatchObject({
      input: [
        {
          content: [{ text: 'Context message', type: 'input_text' }],
          role: 'system',
        },
        {
          content: [{ text: 'Previous assistant reply', type: 'output_text' }],
          role: 'assistant',
        },
        {
          content: [
            { text: 'Last user prompt', type: 'input_text' },
            { image_url: 'data:image/jpeg;base64,aGVsbG8=', type: 'input_image' },
            { file_id: 'file_a', type: 'input_file' },
            { file_id: 'file_b', type: 'input_file' },
          ],
          role: 'user',
        },
      ],
      model: 'gpt-5.4-mini',
      reasoning: {
        effort: 'high',
        summary: 'auto',
      },
      service_tier: 'flex',
    });
  });

  it('parses streamed deltas, annotations, tool updates, and terminal payloads', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      makeSSEStream([
        { type: 'response.created', response: { id: 'resp_1' } },
        { delta: 'Plan ', type: 'response.output_text.delta' },
        { delta: 'Thinking ', type: 'response.reasoning_summary_text.delta' },
        { type: 'response.reasoning_summary_text.done' },
        {
          annotation: {
            end_index: 4,
            start_index: 0,
            title: 'Source',
            type: 'url_citation',
            url: 'https://example.com/source',
          },
          type: 'response.output_text.annotation.added',
        },
        {
          annotation: {
            container_id: 'container_1',
            end_index: 4,
            file_id: 'file_1',
            filename: 'plan.md',
            start_index: 0,
            type: 'file_path',
          },
          type: 'response.output_text.annotation.added',
        },
        { item_id: 'tool_web', query: 'glassgpt', type: 'response.web_search_call.searching' },
        {
          delta: 'print(1)',
          item_id: 'tool_code',
          type: 'response.code_interpreter_call.code.delta',
        },
        {
          response: {
            output: [
              {
                content: [{ text: 'Plan complete', type: 'output_text' }],
                role: 'assistant',
                type: 'message',
              },
            ],
            output_text: 'Plan complete',
          },
          type: 'response.completed',
        },
      ]),
    );

    const events = [];
    for await (const event of createStreamingResponse('sk-stream', { input: 'Plan this' })) {
      events.push(event);
    }

    expect(events.map((event) => event.kind)).toEqual([
      'response_created',
      'text_delta',
      'thinking_delta',
      'thinking_finished',
      'citation_added',
      'file_path_annotation_added',
      'tool_call_updated',
      'tool_call_updated',
      'completed',
    ]);
    expect(events.at(-1)).toMatchObject({
      kind: 'completed',
      outputText: 'Plan complete',
      thinkingText: 'Thinking ',
    });
  });

  it('synthesizes a completed event on done sentinel and surfaces failures in streaming helpers', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      makeSSEStream([{ delta: 'Partial', type: 'response.output_text.delta' }, '[DONE]']),
    );

    const completionEvents = [];
    for await (const event of createStreamingResponse('sk-done', { input: 'Say hi' })) {
      completionEvents.push(event);
    }

    expect(completionEvents.at(-1)).toMatchObject({
      kind: 'completed',
      outputText: 'Partial',
    });

    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      makeSSEStream([
        {
          error: { message: 'bad_news' },
          type: 'response.failed',
        },
      ]),
    );

    await expect(async () => {
      for await (const _ of createStreamingChatCompletion('sk-fail', 'Hi')) {
        // no-op
      }
    }).rejects.toThrow('bad_news');
  });

  it('emits file search status updates and an incomplete terminal event', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      makeSSEStream([
        { item_id: 'web-1', type: 'response.web_search_call.in_progress' },
        { item_id: 'web-1', query: 'glassgpt', type: 'response.web_search_call.searching' },
        { item_id: 'file-1', type: 'response.file_search_call.in_progress' },
        { item_id: 'file-1', queries: ['alpha'], type: 'response.file_search_call.searching' },
        { item_id: 'file-1', queries: ['alpha'], type: 'response.file_search_call.completed' },
        { item_id: 'code-1', type: 'response.code_interpreter_call.in_progress' },
        { item_id: 'code-1', type: 'response.code_interpreter_call.interpreting' },
        {
          code: 'print("done")',
          item_id: 'code-1',
          type: 'response.code_interpreter_call.code.done',
        },
        { item_id: 'code-1', type: 'response.code_interpreter_call.completed' },
        {
          response: {
            error: { message: 'partial_stop' },
            output_text: 'Partial output',
          },
          type: 'response.incomplete',
        },
      ]),
    );

    const events = [];
    for await (const event of createStreamingResponse('sk-incomplete', { input: 'Stop early' })) {
      events.push(event);
    }

    expect(events.map((event) => event.kind)).toEqual([
      'tool_call_updated',
      'tool_call_updated',
      'tool_call_updated',
      'tool_call_updated',
      'tool_call_updated',
      'tool_call_updated',
      'tool_call_updated',
      'tool_call_updated',
      'tool_call_updated',
      'incomplete',
    ]);
    expect(events.at(-1)).toMatchObject({
      citations: [],
      errorMessage: 'partial_stop',
      filePathAnnotations: [],
      kind: 'incomplete',
      outputText: 'Partial output',
      thinkingText: null,
      toolCalls: [
        {
          code: null,
          id: 'web-1',
          queries: ['glassgpt'],
          results: null,
          status: 'searching',
          type: 'web_search',
        },
        {
          code: null,
          id: 'file-1',
          queries: ['alpha'],
          results: null,
          status: 'completed',
          type: 'file_search',
        },
        {
          code: 'print("done")',
          id: 'code-1',
          queries: null,
          results: null,
          status: 'completed',
          type: 'code_interpreter',
        },
      ],
    });
  });

  it('emits a failed event for the raw error terminal event', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      makeSSEStream([
        {
          error: { message: 'bad_gateway' },
          type: 'error',
        },
      ]),
    );

    const events = [];
    for await (const event of createStreamingResponse('sk-error', { input: 'Fail fast' })) {
      events.push(event);
    }

    expect(events).toEqual([{ errorMessage: 'bad_gateway', kind: 'failed' }]);
  });

  it('rejects when the streaming response does not include a body', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(null, {
        status: 200,
      }),
    );

    await expect(
      createStreamingResponse('sk-empty-body', { input: 'No body' }).next(),
    ).rejects.toThrow('openai_streaming_no_body');
  });

  it('retries transient API failures before succeeding', async () => {
    const setTimeoutSpy = vi.spyOn(globalThis, 'setTimeout').mockImplementation(((
      callback: TimerHandler,
    ) => {
      if (typeof callback === 'function') {
        callback();
      } else {
        // The timeout callback is always a function in this adapter.
      }
      return 0 as never;
    }) as typeof setTimeout);
    vi.spyOn(globalThis, 'clearTimeout').mockImplementation(() => undefined);

    const fetchMock = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(
        new Response('', {
          headers: { 'retry-after': '1' },
          status: 429,
        }),
      )
      .mockResolvedValueOnce(
        new Response('', {
          status: 503,
        }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            output_text: 'Recovered reply',
          }),
          {
            headers: { 'Content-Type': 'application/json' },
            status: 200,
          },
        ),
      );

    await expect(createChatCompletion('sk-retry', 'Hello')).resolves.toBe('Recovered reply');
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(setTimeoutSpy).toHaveBeenCalled();
  });

  it('fails fast on non-retryable API failures', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response('', {
        status: 400,
      }),
    );

    await expect(createChatCompletion('sk-bad', 'Hello')).rejects.toMatchObject({
      message: 'openai_status_400',
      name: 'OpenAiApiError',
      retryAfterSeconds: null,
      statusCode: 400,
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('yields the final text when streaming chat completion receives no deltas', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      makeStreamingResponse({
        response: {
          output: [
            {
              content: [{ text: 'Recovered stream reply', type: 'output_text' }],
              role: 'assistant',
              type: 'message',
            },
          ],
          output_text: 'Recovered stream reply',
        },
        type: 'response.completed',
      }),
    );

    const chunks: string[] = [];
    for await (const chunk of createStreamingChatCompletion('sk-stream-chat', 'Hello')) {
      chunks.push(chunk);
    }

    expect(chunks).toEqual(['Recovered stream reply']);
  });

  it('creates a non-streaming chat completion from output text', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({
          output_text: 'Chat reply',
        }),
        {
          headers: { 'Content-Type': 'application/json' },
          status: 200,
        },
      ),
    );

    await expect(createChatCompletion('sk-chat', 'Hello')).resolves.toBe('Chat reply');
  });
});
