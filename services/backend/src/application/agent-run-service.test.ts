import { describe, expect, it, vi } from 'vitest';

import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunEventInsertRecord, RunEventRecord } from '../domain/run-event-model.js';
import type { RunRecord } from '../domain/run-model.js';
import { createAgentRunService } from './agent-run-service.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import { formatCursorSequence } from './ids.js';
import type { WorkflowStarter } from './run-projection.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const now = new Date('2026-03-27T12:00:00.000Z');

const testEnv = {
  AGENT_RUN_WORKFLOW: {} as Env['AGENT_RUN_WORKFLOW'],
  APPLE_AUDIENCE: 'com.glassgpt.app',
  APPLE_BUNDLE_ID: 'com.glassgpt.app',
  APP_ENV: 'beta',
  CHAT_RUN_WORKFLOW: {} as Env['CHAT_RUN_WORKFLOW'],
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
  id: 'conv_agent_01',
  lastRunId: null,
  lastSyncCursor: null,
  mode: 'agent',
  title: 'Agent Conversation',
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
  readonly service: ReturnType<typeof createAgentRunService>;
  readonly workflow: WorkflowStarter<{
    readonly conversationId: string;
    readonly prompt: string;
    readonly runId: string;
    readonly userId: string;
  }>;
  readonly workflowCreate: ReturnType<typeof vi.fn>;
}

const createServiceHarness = (options?: {
  readonly createChatCompletion?: (apiKey: string, input: string) => Promise<string>;
  readonly initialMessages?: MessageRecord[];
  readonly publishConversationCursor?: (
    env: BackendRuntimeContext,
    conversationId: string,
    cursor: string,
  ) => Promise<void>;
  readonly workflowCreate?: (options: {
    id: string;
    params: {
      readonly conversationId: string;
      readonly prompt: string;
      readonly runId: string;
      readonly userId: string;
    };
  }) => Promise<{ id: string }>;
}): ServiceHarness => {
  const conversations = new Map<string, ConversationRecord>([
    [conversationFixture.id, conversationFixture],
  ]);
  const messages = [...(options?.initialMessages ?? [])];
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

  const service = createAgentRunService({
    createChatCompletion:
      options?.createChatCompletion ??
      (() => {
        const responses = ['Leader plan', 'Worker report', 'Leader review', 'Final answer'];
        return async () => {
          const nextResponse = responses.shift();
          if (!nextResponse) {
            throw new Error('unexpected_completion_call');
          }

          return nextResponse;
        };
      })(),
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
      return messages.find((message) => message.role === 'user' && message.runId === runId) ?? null;
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
    listMessagesForConversation: async (_env, conversationId) => {
      return messages.filter((message) => message.conversationId === conversationId);
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
      readonly conversationId: string;
      readonly prompt: string;
      readonly runId: string;
      readonly userId: string;
    }>,
    workflowCreate,
  };
};

describe('createAgentRunService', () => {
  it('queues a server-owned agent run and emits projection-complete sync events', async () => {
    const harness = createServiceHarness();

    const run = await harness.service.queueAgentRun(testEnv, harness.workflow, {
      conversationId: conversationFixture.id,
      prompt: 'Investigate the codebase',
      userId: conversationFixture.userId,
    });

    expect(run.kind).toBe('agent');
    expect(run.stage).toBe('leader_planning');
    expect(run.status).toBe('queued');
    expect(harness.workflowCreate).toHaveBeenCalledTimes(1);
    expect(harness.workflowCreate.mock.calls[0]?.[0].params.prompt).toBe(
      'Investigate the codebase',
    );
    expect(harness.messages).toHaveLength(1);
    expect(harness.messages[0]?.content).toBe('Investigate the codebase');
    expect(harness.messages[0]?.serverCursor).toBe(formatCursorSequence(1));
    expect(harness.events.map((event) => event.kind)).toEqual(['message_created', 'run_queued']);
    expect(harness.events[1]?.run?.kind).toBe('agent');
  });

  it('executes all agent stages with monotonic event cursors and a final assistant message', async () => {
    const harness = createServiceHarness();
    const queuedRun = await harness.service.queueAgentRun(testEnv, harness.workflow, {
      conversationId: conversationFixture.id,
      prompt: 'Audit the implementation',
      userId: conversationFixture.userId,
    });

    await harness.service.startQueuedRun(testEnv, {
      runId: queuedRun.id,
      userId: conversationFixture.userId,
    });
    const leaderPlan = await harness.service.executeLeaderPlanning(testEnv, {
      prompt: 'Audit the implementation',
      runId: queuedRun.id,
      userId: conversationFixture.userId,
    });
    const workerReport = await harness.service.executeWorkerWave(testEnv, {
      leaderPlan: leaderPlan ?? 'missing',
      runId: queuedRun.id,
      userId: conversationFixture.userId,
      userPrompt: 'Audit the implementation',
    });
    const leaderReview = await harness.service.executeLeaderReview(testEnv, {
      leaderPlan: leaderPlan ?? 'missing',
      runId: queuedRun.id,
      userId: conversationFixture.userId,
      userPrompt: 'Audit the implementation',
      workerReport: workerReport ?? 'missing',
    });
    const finalText = await harness.service.executeFinalSynthesis(testEnv, {
      leaderPlan: leaderPlan ?? 'missing',
      leaderReview: leaderReview ?? 'missing',
      runId: queuedRun.id,
      userId: conversationFixture.userId,
      userPrompt: 'Audit the implementation',
      workerReport: workerReport ?? 'missing',
    });
    await harness.service.completeRun(testEnv, {
      finalText: finalText ?? 'missing',
      runId: queuedRun.id,
      userId: conversationFixture.userId,
    });

    expect(harness.events.map((event) => event.kind)).toEqual([
      'message_created',
      'run_queued',
      'run_started',
      'run_progress',
      'run_progress',
      'stage_changed',
      'run_progress',
      'stage_changed',
      'run_progress',
      'stage_changed',
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
      formatCursorSequence(8),
      formatCursorSequence(9),
      formatCursorSequence(10),
      formatCursorSequence(11),
      formatCursorSequence(12),
      formatCursorSequence(13),
      formatCursorSequence(14),
    ]);
    expect(harness.events[5]?.stage).toBe('worker_wave');
    expect(harness.events[7]?.stage).toBe('leader_review');
    expect(harness.events[9]?.stage).toBe('final_synthesis');
    expect(harness.messages.at(-1)?.role).toBe('assistant');
    expect(harness.messages.at(-1)?.serverCursor).toBe(formatCursorSequence(12));
    expect(harness.runs.get(queuedRun.id)?.status).toBe('completed');
    expect(harness.runs.get(queuedRun.id)?.visibleSummary).toBe('Final answer');
    expect(harness.cursorPublishes).toHaveLength(14);
  });

  it('reuses the latest user message when an agent run is queued without a new prompt', async () => {
    const existingUserMessage: MessageRecord = {
      completedAt: now.toISOString(),
      content: 'Use the previous user message',
      conversationId: conversationFixture.id,
      createdAt: now.toISOString(),
      id: 'msg_existing_01',
      role: 'user',
      runId: null,
      serverCursor: null,
    };
    const harness = createServiceHarness({
      initialMessages: [existingUserMessage],
    });

    const run = await harness.service.queueAgentRun(testEnv, harness.workflow, {
      conversationId: conversationFixture.id,
      userId: conversationFixture.userId,
    });

    expect(run.kind).toBe('agent');
    expect(harness.workflowCreate).toHaveBeenCalledTimes(1);
    expect(harness.workflowCreate.mock.calls[0]?.[0].params.prompt).toBe(
      'Use the previous user message',
    );
    expect(harness.messages).toEqual([existingUserMessage]);
    expect(harness.events.map((event) => event.kind)).toEqual(['run_queued']);
  });

  it('retries an agent run with the injected workflow starter', async () => {
    const harness = createServiceHarness();
    const queuedRun = await harness.service.queueAgentRun(testEnv, harness.workflow, {
      conversationId: conversationFixture.id,
      prompt: 'Retry this agent run',
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
    expect(retryWorkflowCreate.mock.calls[0]?.[0].params.prompt).toBe('Retry this agent run');
    expect(harness.events.at(-1)?.kind).toBe('run_queued');
  });

  it('short-circuits stage execution only after a run becomes terminal', async () => {
    const harness = createServiceHarness();
    const queuedRun = await harness.service.queueAgentRun(testEnv, harness.workflow, {
      conversationId: conversationFixture.id,
      prompt: 'Cancel before execution',
      userId: conversationFixture.userId,
    });

    const cancelledRun = await harness.service.cancelRun(
      testEnv,
      conversationFixture.userId,
      queuedRun.id,
    );
    const started = await harness.service.startQueuedRun(testEnv, {
      runId: queuedRun.id,
      userId: conversationFixture.userId,
    });
    const leaderPlan = await harness.service.executeLeaderPlanning(testEnv, {
      prompt: 'Cancel before execution',
      runId: queuedRun.id,
      userId: conversationFixture.userId,
    });

    expect(cancelledRun.status).toBe('cancelled');
    expect(started).toBe(false);
    expect(leaderPlan).toBeNull();
    expect(harness.runs.get(queuedRun.id)?.status).toBe('cancelled');
    expect(harness.events.at(-1)?.kind).toBe('run_cancelled');
  });
});
