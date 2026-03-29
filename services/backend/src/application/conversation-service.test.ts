import { describe, expect, it } from 'vitest';
import type { ConversationRecord } from '../domain/conversation-model.js';
import type { ConversationListCursor } from './conversation-list-pagination.js';
import { createConversationService } from './conversation-service.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const now = new Date('2026-03-27T12:00:00.000Z');
const testEnv = {} as BackendRuntimeContext;

interface ConversationServiceHarness {
  readonly conversations: Map<string, ConversationRecord>;
  readonly updates: Array<{
    readonly agentWorkerReasoningEffort: ConversationRecord['agentWorkerReasoningEffort'];
    readonly conversationId: string;
    readonly model: ConversationRecord['model'];
    readonly reasoningEffort: ConversationRecord['reasoningEffort'];
    readonly serviceTier: ConversationRecord['serviceTier'];
    readonly updatedAt: string;
  }>;
  readonly service: ReturnType<typeof createConversationService>;
}

const createHarness = (
  initialConversations: readonly ConversationRecord[] = [],
): ConversationServiceHarness => {
  const conversations = new Map(
    initialConversations.map((conversation) => [conversation.id, conversation]),
  );
  const updates: ConversationServiceHarness['updates'] = [];

  const service = createConversationService({
    findConversationByIdForUser: async (_env, conversationId, userId) => {
      const conversation = conversations.get(conversationId) ?? null;
      return conversation?.userId === userId ? conversation : null;
    },
    insertConversation: async (_env, conversation) => {
      conversations.set(conversation.id, conversation);
    },
    listConversationsForUser: async (_env, userId, input) => {
      const ordered = [...conversations.values()]
        .filter((conversation) => conversation.userId === userId)
        .sort((left, right) => {
          if (left.updatedAt !== right.updatedAt) {
            return right.updatedAt.localeCompare(left.updatedAt);
          }
          return right.id.localeCompare(left.id);
        });
      const filtered = input.cursor
        ? ordered.filter((conversation) => {
            return (
              conversation.updatedAt < input.cursor.updatedAt ||
              (conversation.updatedAt === input.cursor.updatedAt &&
                conversation.id < input.cursor.id)
            );
          })
        : ordered;
      const items = filtered.slice(0, input.limit);
      const hasMore = filtered.length > input.limit;
      const lastItem = items.at(-1) ?? null;
      const nextCursor: ConversationListCursor | null =
        hasMore && lastItem
          ? {
              id: lastItem.id,
              updatedAt: lastItem.updatedAt,
            }
          : null;
      return {
        hasMore,
        items,
        nextCursor,
      };
    },
    listMessagesForConversation: async () => [],
    listRunsForConversation: async () => [],
    now: () => now,
    updateConversationConfiguration: async (_env, input) => {
      updates.push(input);
      const existing = conversations.get(input.conversationId);
      if (!existing) {
        return;
      }

      conversations.set(input.conversationId, {
        ...existing,
        agentWorkerReasoningEffort: input.agentWorkerReasoningEffort,
        model: input.model,
        reasoningEffort: input.reasoningEffort,
        serviceTier: input.serviceTier,
        updatedAt: input.updatedAt,
      });
    },
  });

  return { conversations, service, updates };
};

describe('createConversationService', () => {
  it('creates chat conversations with authoritative configuration defaults', async () => {
    const harness = createHarness();

    const conversation = await harness.service.createConversation(testEnv, 'usr_01', {
      agentWorkerReasoningEffort: null,
      mode: 'chat',
      model: null,
      reasoningEffort: null,
      serviceTier: null,
      title: 'Configured chat',
    });

    const persisted = [...harness.conversations.values()][0];
    expect(persisted).toMatchObject({
      agentWorkerReasoningEffort: null,
      mode: 'chat',
      model: 'gpt-5.4',
      reasoningEffort: 'high',
      serviceTier: 'default',
      title: 'Configured chat',
      userId: 'usr_01',
    });
    expect(conversation).toMatchObject({
      agentWorkerReasoningEffort: undefined,
      mode: 'chat',
      model: 'gpt-5.4',
      reasoningEffort: 'high',
      serviceTier: 'default',
      title: 'Configured chat',
    });
  });

  it('creates agent conversations with agent-specific authoritative defaults', async () => {
    const harness = createHarness();

    const conversation = await harness.service.createConversation(testEnv, 'usr_01', {
      agentWorkerReasoningEffort: null,
      mode: 'agent',
      model: 'gpt-5.4-pro',
      reasoningEffort: null,
      serviceTier: null,
      title: 'Configured agent',
    });

    const persisted = [...harness.conversations.values()][0];
    expect(persisted).toMatchObject({
      agentWorkerReasoningEffort: 'low',
      mode: 'agent',
      model: null,
      reasoningEffort: 'high',
      serviceTier: 'default',
      title: 'Configured agent',
      userId: 'usr_01',
    });
    expect(conversation).toMatchObject({
      agentWorkerReasoningEffort: 'low',
      mode: 'agent',
      model: undefined,
      reasoningEffort: 'high',
      serviceTier: 'default',
      title: 'Configured agent',
    });
  });

  it('updates chat configuration and ignores agent-only worker effort overrides', async () => {
    const harness = createHarness([
      {
        agentWorkerReasoningEffort: null,
        createdAt: now.toISOString(),
        id: 'conv_chat_01',
        lastRunId: null,
        lastSyncCursor: null,
        mode: 'chat',
        model: 'gpt-5.4',
        reasoningEffort: 'high',
        serviceTier: 'default',
        title: 'Chat conversation',
        updatedAt: now.toISOString(),
        userId: 'usr_01',
      },
    ]);

    const updated = await harness.service.updateConversationConfiguration(
      testEnv,
      'usr_01',
      'conv_chat_01',
      {
        agentWorkerReasoningEffort: 'xhigh',
        model: 'gpt-5.4-pro',
        reasoningEffort: 'medium',
        serviceTier: 'flex',
      },
    );

    expect(harness.updates).toEqual([
      {
        agentWorkerReasoningEffort: null,
        conversationId: 'conv_chat_01',
        model: 'gpt-5.4-pro',
        reasoningEffort: 'medium',
        serviceTier: 'flex',
        updatedAt: now.toISOString(),
      },
    ]);
    expect(updated).toMatchObject({
      agentWorkerReasoningEffort: undefined,
      id: 'conv_chat_01',
      model: 'gpt-5.4-pro',
      reasoningEffort: 'medium',
      serviceTier: 'flex',
    });
  });

  it('updates agent configuration and ignores chat-only model overrides', async () => {
    const harness = createHarness([
      {
        agentWorkerReasoningEffort: 'low',
        createdAt: now.toISOString(),
        id: 'conv_agent_01',
        lastRunId: null,
        lastSyncCursor: null,
        mode: 'agent',
        model: null,
        reasoningEffort: 'high',
        serviceTier: 'default',
        title: 'Agent conversation',
        updatedAt: now.toISOString(),
        userId: 'usr_01',
      },
    ]);

    const updated = await harness.service.updateConversationConfiguration(
      testEnv,
      'usr_01',
      'conv_agent_01',
      {
        agentWorkerReasoningEffort: 'medium',
        model: 'gpt-5.4-pro',
        reasoningEffort: 'xhigh',
        serviceTier: 'flex',
      },
    );

    expect(harness.updates).toEqual([
      {
        agentWorkerReasoningEffort: 'medium',
        conversationId: 'conv_agent_01',
        model: null,
        reasoningEffort: 'xhigh',
        serviceTier: 'flex',
        updatedAt: now.toISOString(),
      },
    ]);
    expect(updated).toMatchObject({
      agentWorkerReasoningEffort: 'medium',
      id: 'conv_agent_01',
      model: undefined,
      reasoningEffort: 'xhigh',
      serviceTier: 'flex',
    });
  });

  it('lists conversations through a cursor-paginated envelope', async () => {
    const harness = createHarness([
      {
        agentWorkerReasoningEffort: null,
        createdAt: now.toISOString(),
        id: 'conv_c',
        lastRunId: null,
        lastSyncCursor: null,
        mode: 'chat',
        model: 'gpt-5.4',
        reasoningEffort: 'high',
        serviceTier: 'default',
        title: 'Conversation C',
        updatedAt: '2026-03-27T12:00:03.000Z',
        userId: 'usr_01',
      },
      {
        agentWorkerReasoningEffort: null,
        createdAt: now.toISOString(),
        id: 'conv_b',
        lastRunId: null,
        lastSyncCursor: null,
        mode: 'chat',
        model: 'gpt-5.4',
        reasoningEffort: 'high',
        serviceTier: 'default',
        title: 'Conversation B',
        updatedAt: '2026-03-27T12:00:02.000Z',
        userId: 'usr_01',
      },
      {
        agentWorkerReasoningEffort: null,
        createdAt: now.toISOString(),
        id: 'conv_a',
        lastRunId: null,
        lastSyncCursor: null,
        mode: 'chat',
        model: 'gpt-5.4',
        reasoningEffort: 'high',
        serviceTier: 'default',
        title: 'Conversation A',
        updatedAt: '2026-03-27T12:00:01.000Z',
        userId: 'usr_01',
      },
    ]);

    const firstPage = await harness.service.listConversations(testEnv, 'usr_01', {
      cursor: undefined,
      limit: 2,
    });

    expect(firstPage.hasMore).toBe(true);
    expect(firstPage.items.map((conversation) => conversation.id)).toEqual(['conv_c', 'conv_b']);
    expect(firstPage.nextCursor).toBeTruthy();

    const secondPage = await harness.service.listConversations(testEnv, 'usr_01', {
      cursor: firstPage.nextCursor,
      limit: 2,
    });

    expect(secondPage.hasMore).toBe(false);
    expect(secondPage.items.map((conversation) => conversation.id)).toEqual(['conv_a']);
    expect(secondPage.nextCursor).toBeUndefined();
  });
});
