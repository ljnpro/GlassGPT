import { describe, expect, it } from 'vitest';

import type { MessageRecord } from '../domain/message-model.js';
import { applyLiveStateToMessage, parseMessageLiveState } from './live-payload-codec.js';

const messageFixture = (overrides: Partial<MessageRecord> = {}): MessageRecord => ({
  agentTraceJSON: null,
  annotationsJSON: null,
  completedAt: null,
  content: 'assistant reply',
  conversationId: 'conv_01',
  createdAt: '2026-03-29T15:00:00.000Z',
  filePathAnnotationsJSON: null,
  id: 'msg_01',
  role: 'assistant',
  runId: 'run_01',
  serverCursor: null,
  thinking: 'thinking',
  toolCallsJSON: null,
  ...overrides,
});

describe('parseMessageLiveState', () => {
  it('falls back to empty collections when persisted JSON is malformed', () => {
    const state = parseMessageLiveState(
      messageFixture({
        annotationsJSON: 'not-json',
        filePathAnnotationsJSON: JSON.stringify([{ fileId: 12 }]),
        toolCallsJSON: JSON.stringify([{ id: 'tool_01', type: 'bad' }]),
      }),
    );

    expect(state.citations).toEqual([]);
    expect(state.filePathAnnotations).toEqual([]);
    expect(state.toolCalls).toEqual([]);
  });

  it('returns validated live payloads when persisted JSON is well-formed', () => {
    const state = parseMessageLiveState(
      messageFixture({
        annotationsJSON: JSON.stringify([
          {
            endIndex: 4,
            startIndex: 0,
            title: 'Citation',
            url: 'https://example.com',
          },
        ]),
        filePathAnnotationsJSON: JSON.stringify([
          {
            containerId: null,
            endIndex: 12,
            fileId: 'file_01',
            filename: 'report.md',
            sandboxPath: '/sandbox/report.md',
            startIndex: 0,
          },
        ]),
        toolCallsJSON: JSON.stringify([
          {
            code: null,
            id: 'tool_01',
            queries: ['latest benchmark'],
            results: ['result'],
            status: 'completed',
            type: 'web_search',
          },
        ]),
      }),
    );

    expect(state.citations).toHaveLength(1);
    expect(state.filePathAnnotations).toHaveLength(1);
    expect(state.toolCalls).toHaveLength(1);
  });

  it('accepts legacy tool call payloads with null optional fields', () => {
    const state = parseMessageLiveState(
      messageFixture({
        toolCallsJSON: JSON.stringify([
          {
            code: null,
            id: 'tool_legacy',
            queries: null,
            results: null,
            status: 'completed',
            type: 'web_search',
          },
        ]),
      }),
    );

    expect(state.toolCalls).toEqual([
      {
        code: null,
        id: 'tool_legacy',
        queries: null,
        results: null,
        status: 'completed',
        type: 'web_search',
      },
    ]);
  });

  it('writes tool call JSON without contract-incompatible null optionals', () => {
    const message = applyLiveStateToMessage(messageFixture(), {
      citations: [],
      content: 'assistant reply',
      filePathAnnotations: [],
      thinking: null,
      toolCalls: [
        {
          code: null,
          id: 'tool_01',
          queries: null,
          results: null,
          status: 'completed',
          type: 'web_search',
        },
      ],
    });

    expect(message.toolCallsJSON).toBe(
      JSON.stringify([
        {
          id: 'tool_01',
          status: 'completed',
          type: 'web_search',
        },
      ]),
    );
  });
});
