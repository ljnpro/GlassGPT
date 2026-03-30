import { describe, expect, it } from 'vitest';

import {
  extractCitations,
  extractErrorMessage,
  extractFilePathAnnotations,
  extractOutputText,
  extractReasoningText,
  extractToolCalls,
  mergeCitations,
  mergeFilePathAnnotations,
  mergeToolCalls,
  type ResponsesResponse,
} from './openai-response-extraction.js';

describe('openai response extraction', () => {
  it('extracts the supported response shapes and ignores invalid fragments', () => {
    const response = {
      output_text: '',
      output: [
        {
          content: [
            {
              annotations: [
                {
                  end_index: 4,
                  start_index: 1,
                  title: 'Example source',
                  type: 'url_citation',
                  url: 'https://example.com',
                },
              ],
              text: 'abcde',
              type: 'output_text',
            },
          ],
          type: 'message',
        },
        {
          content: [
            {
              annotations: [
                {
                  container_id: 'container-1',
                  end_index: 4,
                  filename: 'notes.txt',
                  file_id: 'file-1',
                  start_index: 1,
                  type: 'file_path',
                },
                {
                  container_id: 'container-2',
                  end_index: 7,
                  filename: 'ignored.txt',
                  file_id: 'file-2',
                  start_index: 2,
                  type: 'container_file_citation',
                },
                {
                  file_id: '',
                  type: 'file_path',
                },
              ],
              text: 'fgHIJ',
              type: 'output_text',
            },
          ],
          id: 'web-1',
          query: 'first query',
          type: 'web_search_call',
        },
        {
          code: 'print(1)',
          id: 'code-1',
          outputs: [{ output: 'stdout one' }],
          results: [{ output: 'result output' }, { text: 'result text' }, { logs: 'result logs' }],
          type: 'code_interpreter_call',
        },
        {
          id: 'file-3',
          queries: ['file query'],
          type: 'file_search_call',
        },
        {
          content: [{ text: 'content tail', type: 'output_text' }],
          summary: [{ text: 'step one' }],
          text: 'reasoning text',
          type: 'reasoning',
        },
      ],
      reasoning: {
        summary: [{ text: 'summary text' }],
        text: 'prefix ',
      },
    } satisfies ResponsesResponse;

    expect(extractOutputText(response)).toBe('abcdefgHIJcontent tail');
    expect(extractReasoningText(response)).toBe(
      'prefix summary textreasoning textstep onecontent tail',
    );
    expect(extractCitations(response)).toEqual([
      {
        endIndex: 4,
        startIndex: 1,
        title: 'Example source',
        url: 'https://example.com',
      },
    ]);
    expect(extractFilePathAnnotations(response)).toEqual([
      {
        containerId: 'container-1',
        endIndex: 4,
        fileId: 'file-1',
        filename: 'notes.txt',
        sandboxPath: 'bcd',
        startIndex: 1,
      },
      {
        containerId: 'container-2',
        endIndex: 7,
        fileId: 'file-2',
        filename: 'ignored.txt',
        sandboxPath: 'cdefg',
        startIndex: 2,
      },
    ]);
    expect(extractToolCalls(response)).toEqual([
      {
        code: null,
        id: 'web-1',
        queries: ['first query'],
        results: null,
        status: 'completed',
        type: 'web_search',
      },
      {
        code: 'print(1)',
        id: 'code-1',
        queries: null,
        results: ['result output', 'result text', 'result logs', 'stdout one'],
        status: 'completed',
        type: 'code_interpreter',
      },
      {
        code: null,
        id: 'file-3',
        queries: ['file query'],
        results: null,
        status: 'completed',
        type: 'file_search',
      },
    ]);
  });

  it('returns null and deduplicates merges by the adapter keys', () => {
    const emptyResponse = {} satisfies ResponsesResponse;

    expect(extractErrorMessage(emptyResponse)).toBeNull();
    expect(extractOutputText(emptyResponse)).toBe('');
    expect(extractReasoningText(emptyResponse)).toBeNull();
    expect(extractCitations(emptyResponse)).toEqual([]);
    expect(extractFilePathAnnotations(emptyResponse)).toEqual([]);
    expect(extractToolCalls(emptyResponse)).toEqual([]);

    expect(
      extractErrorMessage({
        error: { message: 'primary failure' },
        message: 'secondary failure',
      } satisfies ResponsesResponse),
    ).toBe('primary failure');
    expect(extractErrorMessage({ message: 'fallback failure' } satisfies ResponsesResponse)).toBe(
      'fallback failure',
    );

    expect(
      mergeToolCalls(
        [
          {
            code: null,
            id: 'tool-1',
            queries: ['original'],
            results: null,
            status: 'in_progress',
            type: 'web_search',
          },
        ],
        [
          {
            code: 'updated',
            id: 'tool-1',
            queries: ['replacement'],
            results: ['done'],
            status: 'completed',
            type: 'code_interpreter',
          },
        ],
      ),
    ).toEqual([
      {
        code: 'updated',
        id: 'tool-1',
        queries: ['replacement'],
        results: ['done'],
        status: 'completed',
        type: 'code_interpreter',
      },
    ]);

    expect(
      mergeCitations(
        [
          {
            endIndex: 2,
            startIndex: 1,
            title: 'First',
            url: 'https://example.com/a',
          },
        ],
        [
          {
            endIndex: 2,
            startIndex: 1,
            title: 'Duplicate title is ignored by key',
            url: 'https://example.com/a',
          },
          {
            endIndex: 4,
            startIndex: 3,
            title: 'Second',
            url: 'https://example.com/b',
          },
        ],
      ),
    ).toEqual([
      {
        endIndex: 2,
        startIndex: 1,
        title: 'Duplicate title is ignored by key',
        url: 'https://example.com/a',
      },
      {
        endIndex: 4,
        startIndex: 3,
        title: 'Second',
        url: 'https://example.com/b',
      },
    ]);

    expect(
      mergeFilePathAnnotations(
        [
          {
            containerId: null,
            endIndex: 2,
            fileId: 'file-1',
            filename: null,
            sandboxPath: 'ab',
            startIndex: 0,
          },
        ],
        [
          {
            containerId: 'container-2',
            endIndex: 2,
            fileId: 'file-1',
            filename: 'changed.txt',
            sandboxPath: 'cd',
            startIndex: 0,
          },
          {
            containerId: 'container-3',
            endIndex: 5,
            fileId: 'file-2',
            filename: 'notes.txt',
            sandboxPath: 'efg',
            startIndex: 3,
          },
        ],
      ),
    ).toEqual([
      {
        containerId: 'container-2',
        endIndex: 2,
        fileId: 'file-1',
        filename: 'changed.txt',
        sandboxPath: 'cd',
        startIndex: 0,
      },
      {
        containerId: 'container-3',
        endIndex: 5,
        fileId: 'file-2',
        filename: 'notes.txt',
        sandboxPath: 'efg',
        startIndex: 3,
      },
    ]);
  });
});
