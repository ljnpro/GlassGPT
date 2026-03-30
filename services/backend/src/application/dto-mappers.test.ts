import { describe, expect, it } from 'vitest';

import type { MessageRecord } from '../domain/message-model.js';
import { buildMessageDTO } from './dto-mappers.js';

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
  thinking: null,
  toolCallsJSON: null,
  ...overrides,
});

describe('buildMessageDTO', () => {
  it('normalizes persisted tool call JSON with legacy null optionals', () => {
    const dto = buildMessageDTO(
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

    expect(dto.toolCalls).toEqual([
      {
        id: 'tool_legacy',
        status: 'completed',
        type: 'web_search',
      },
    ]);
  });
});
