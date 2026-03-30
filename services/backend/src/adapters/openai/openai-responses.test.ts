import { afterEach, describe, expect, it, vi } from 'vitest';

import { createStreamingResponse } from './openai-responses.js';

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
});
