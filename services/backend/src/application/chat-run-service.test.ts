import { describe, expect, it, vi } from 'vitest';
import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunEventInsertRecord, RunEventRecord } from '../domain/run-event-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import { createChatRunService } from './chat-run-service.js';
import { formatCursorSequence } from './ids.js';
import type { WorkflowStarter } from './run-projection.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const now = new Date('2026-03-27T12:00:00.000Z');

const testEnv = {
  AGENT_RUN_WORKFLOW: {} as Env['AGENT_RUN_WORKFLOW'],
  APPLE_AUDIENCE: 'com.glassgpt.app',
  APPLE_BUNDLE_ID: 'com.glassgpt.app',
  APP_ENV: 'beta',
  CHAT_RUN_WORKFLOW: {
    create: async (options: { id: string }) => ({ id: options.id }),
  } as Env['CHAT_RUN_WORKFLOW'],
  CONVERSATION_EVENT_HUB: {} as Env['CONVERSATION_EVENT_HUB'],
  CREDENTIAL_ENCRYPTION_KEY: '00',
  CREDENTIAL_ENCRYPTION_KEY_VERSION: 'v1',
  GLASSGPT_ARTIFACTS: {} as R2Bucket,
  GLASSGPT_DB: {} as D1Database,
  R2_BUCKET_NAME: 'glassgpt-beta-artifacts',
  REFRESH_TOKEN_SIGNING_KEY: '11',
  SESSION_SIGNING_KEY: '22',
} as BackendRuntimeContext;

const conversationFixture: ConversationRecord = {
  createdAt: now.toISOString(),
  id: 'conv_01',
  lastRunId: null,
  lastSyncCursor: null,
  mode: 'chat',
  title: 'Glass Conversation',
  updatedAt: now.toISOString(),
  userId: 'usr_01',
};

const credentialFixture: ProviderCredentialRecord = {
  checkedAt: now.toISOString(),
  ciphertext: 'ciphertext',
  createdAt: now.toISOString(),
  id: 'cred_01',
  keyVersion: 'v1',
  lastErrorSummary: null,
  nonce: 'nonce',
  provider: 'openai',
  status: 'valid',
  updatedAt: now.toISOString(),
  userId: 'usr_01',
};

interface ServiceHarness {
  readonly conversations: Map<string, ConversationRecord>;
  readonly cursorPublishes: Array<{ conversationId: string; cursor: string }>;
  readonly events: RunEventRecord[];
  readonly messages: MessageRecord[];
  readonly runs: Map<string, RunRecord>;
  readonly service: ReturnType<typeof createChatRunService>;
  readonly workflow: WorkflowStarter<{
    readonly content: string;
    readonly conversationId: string;
    readonly runId: string;
    readonly userId: string;
  }>;
  readonly workflowCreate: ReturnType<typeof vi.fn>;
}

const createServiceHarness = (options?: {
  readonly createChatCompletion?: (apiKey: string, input: string) => Promise<string>;
  readonly publishConversationCursor?: (
    env: BackendRuntimeContext,
    conversationId: string,
    cursor: string,
  ) => Promise<void>;
  readonly workflowCreate?: (options: { id: string }) => Promise<{ id: string }>;
}): ServiceHarness => {
  const conversations = new Map<string, ConversationRecord>([
    [conversationFixture.id, conversationFixture],
  ]);
  const messages: MessageRecord[] = [];
  const runs = new Map<string, RunRecord>();
  const events: RunEventRecord[] = [];
  const cursorPublishes: Array<{ conversationId: string; cursor: string }> = [];
  let nextCursorSequence = 1;

  const workflowCreate = vi.fn(
    options?.workflowCreate ??
      (async (workflowInput: { id: string }) => {
        return { id: workflowInput.id };
      }),
  );

  const service = createChatRunService({
    createChatCompletion:
      options?.createChatCompletion ??
      (async () => {
        return 'Assistant reply';
      }),
    createStreamingChatCompletion:
      async function* () {
        yield 'Assistant reply';
      },
    decryptSecret: async () => 'sk-user-key',
    findConversationByIdForUser: async (_env, conversationId, userId) => {
      const conversation = conversations.get(conversationId) ?? null;
      return conversation?.userId === userId ? conversation : null;
    },
    findProviderCredential: async () => credentialFixture,
    findRunById: async (_env, runId) => runs.get(runId) ?? null,
    findRunByIdForUser: async (_env, runId, userId) => {
      const run = runs.get(runId) ?? null;
      return run?.userId === userId ? run : null;
    },
    findUserMessageByRunId: async (_env, runId) => {
      return messages.find((message) => message.runId === runId && message.role === 'user') ?? null;
    },
    insertMessage: async (_env, message) => {
      messages.push(message);
    },
    insertRun: async (_env, run) => {
      runs.set(run.id, run);
    },
    insertRunEvent: async (_env, event: RunEventInsertRecord) => {
      const persistedEvent: RunEventRecord = {
        artifact: null,
        artifactId: event.artifactId,
        conversation: null,
        conversationId: event.conversationId,
        createdAt: event.createdAt,
        cursor: formatCursorSequence(nextCursorSequence),
        id: event.id,
        kind: event.kind,
        message: null,
        progressLabel: event.progressLabel,
        run: null,
        runId: event.runId,
        stage: event.stage,
        textDelta: event.textDelta,
      };
      nextCursorSequence += 1;
      events.push(persistedEvent);
      return persistedEvent;
    },
    now: () => now,
    publishConversationCursor:
      options?.publishConversationCursor ??
      (async (_env, conversationId, cursor) => {
        cursorPublishes.push({ conversationId, cursor });
      }),
    updateConversationPointers: async (_env, input) => {
      const existing = conversations.get(input.conversationId);
      if (!existing) {
        return;
      }

      conversations.set(input.conversationId, {
        ...existing,
        lastRunId: input.lastRunId,
        lastSyncCursor: input.lastSyncCursor,
        updatedAt: input.updatedAt,
      });
    },
    updateMessageServerCursor: async (_env, messageId, serverCursor) => {
      const messageIndex = messages.findIndex((message) => message.id === messageId);
      if (messageIndex < 0) {
        return;
      }

      const existingMessage = messages[messageIndex];
      if (!existingMessage) {
        return;
      }

      messages[messageIndex] = {
        ...existingMessage,
        serverCursor,
      };
    },
    updateRun: async (_env, run) => {
      runs.set(run.id, run);
    },
    updateRunEventSnapshots: async (_env, event) => {
      const eventIndex = events.findIndex((candidate) => candidate.id === event.id);
      if (eventIndex < 0) {
        return;
      }

      events[eventIndex] = event;
    },
  });

  return {
    conversations,
    cursorPublishes,
    events,
    messages,
    runs,
    service,
    workflow: { create: workflowCreate } satisfies WorkflowStarter<{
      readonly content: string;
      readonly conversationId: string;
      readonly runId: string;
      readonly userId: string;
    }>,
    workflowCreate,
  };
};

describe('createChatRunService', () => {
  it('queues a server-owned chat run and emits projection-complete sync events', async () => {
    const harness = createServiceHarness();

    const run = await harness.service.queueChatRun(testEnv, harness.workflow, {
      content: 'Hello from the user',
      conversationId: conversationFixture.id,
      userId: conversationFixture.userId,
    });

    expect(run.kind).toBe('chat');
    expect(run.status).toBe('queued');
    expect(harness.workflowCreate).toHaveBeenCalledTimes(1);
    expect(harness.messages).toHaveLength(1);
    expect(harness.messages[0]?.content).toBe('Hello from the user');
    expect(harness.messages[0]?.serverCursor).toBe(formatCursorSequence(1));
    expect(harness.events.map((event) => event.kind)).toEqual(['message_created', 'run_queued']);
    expect(harness.events[0]?.message?.content).toBe('Hello from the user');
    expect(harness.events[1]?.run?.status).toBe('queued');
    expect(harness.events[1]?.conversation?.lastSyncCursor).toBe(formatCursorSequence(2));
  });

  it('executes a queued chat run with monotonic event cursors and non-duplicated completion payloads', async () => {
    const harness = createServiceHarness();
    const queuedRun = await harness.service.queueChatRun(testEnv, harness.workflow, {
      content: 'Generate a response',
      conversationId: conversationFixture.id,
      userId: conversationFixture.userId,
    });

    await harness.service.executeQueuedRun(testEnv, {
      content: 'Generate a response',
      conversationId: conversationFixture.id,
      runId: queuedRun.id,
      userId: conversationFixture.userId,
    });

    expect(harness.events.map((event) => event.kind)).toEqual([
      'message_created',
      'run_queued',
      'run_started',
      'run_progress',
      'assistant_delta',
      'assistant_completed',
      'run_completed',
    ]);
    expect(harness.events.map((event) => event.cursor)).toEqual([
      formatCursorSequence(1),
      formatCursorSequence(2),
      formatCursorSequence(3),
      formatCursorSequence(4),
      formatCursorSequence(5),
      formatCursorSequence(6),
      formatCursorSequence(7),
    ]);
    expect(harness.events[4]?.textDelta).toBe('Assistant reply');
    expect(harness.events[5]?.textDelta).toBeNull();
    expect(harness.events[6]?.run?.status).toBe('completed');
    expect(harness.messages.at(-1)?.role).toBe('assistant');
    expect(harness.messages.at(-1)?.serverCursor).toBe(formatCursorSequence(6));
    expect(harness.runs.get(queuedRun.id)?.status).toBe('completed');
    expect(harness.cursorPublishes).toHaveLength(7);
  });

  it('keeps authoritative state when live cursor fanout fails', async () => {
    const harness = createServiceHarness({
      publishConversationCursor: async () => {
        throw new Error('durable_object_unavailable');
      },
    });
    const queuedRun = await harness.service.queueChatRun(testEnv, harness.workflow, {
      content: 'Cancel me',
      conversationId: conversationFixture.id,
      userId: conversationFixture.userId,
    });

    const cancelledRun = await harness.service.cancelRun(
      testEnv,
      conversationFixture.userId,
      queuedRun.id,
    );

    expect(cancelledRun.status).toBe('cancelled');
    expect(harness.events.at(-1)?.kind).toBe('run_cancelled');
    expect(harness.runs.get(queuedRun.id)?.status).toBe('cancelled');
    expect(harness.conversations.get(conversationFixture.id)?.lastSyncCursor).toBe(
      formatCursorSequence(3),
    );
  });

  it('retries a chat run by using the injected workflow starter', async () => {
    const harness = createServiceHarness();
    const queuedRun = await harness.service.queueChatRun(testEnv, harness.workflow, {
      content: 'Retry source',
      conversationId: conversationFixture.id,
      userId: conversationFixture.userId,
    });

    const retryWorkflowCreate = vi.fn(async (workflowInput: { id: string }) => {
      return { id: workflowInput.id };
    });

    const retriedRun = await harness.service.retryRun(
      testEnv,
      { create: retryWorkflowCreate },
      conversationFixture.userId,
      queuedRun.id,
    );

    expect(retriedRun.id).not.toBe(queuedRun.id);
    expect(retryWorkflowCreate).toHaveBeenCalledTimes(1);
    expect(harness.events.at(-1)?.kind).toBe('run_queued');
  });
});
