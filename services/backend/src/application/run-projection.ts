import type { ArtifactRecord } from '../domain/artifact-model.js';
import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type {
  RunEventInsertRecord,
  RunEventKind,
  RunEventRecord,
} from '../domain/run-event-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type { AgentStage } from '../domain/run-phase.js';
import { logError } from '../observability/logger.js';
import { ApplicationError } from './errors.js';
import { createRunEventId, createRunId } from './ids.js';
import type { BackendRuntimeContext } from './runtime-context.js';

export interface WorkflowStarter<TParams> {
  create(options: { id: string; params: TParams }): Promise<{ id: string }>;
}

export interface RunProjectionDependencies {
  readonly insertRunEvent: (
    env: BackendRuntimeContext,
    event: RunEventInsertRecord,
  ) => Promise<RunEventRecord>;
  readonly publishConversationCursor: (
    env: BackendRuntimeContext,
    conversationId: string,
    cursor: string,
  ) => Promise<void>;
  readonly updateConversationPointers: (
    env: BackendRuntimeContext,
    input: {
      readonly conversationId: string;
      readonly lastRunId: string | null;
      readonly lastSyncCursor: string | null;
      readonly updatedAt: string;
    },
  ) => Promise<void>;
  readonly updateMessageServerCursor: (
    env: BackendRuntimeContext,
    messageId: string,
    serverCursor: string,
  ) => Promise<void>;
  readonly updateRun: (env: BackendRuntimeContext, run: RunRecord) => Promise<void>;
  readonly updateRunEventSnapshots: (
    env: BackendRuntimeContext,
    event: RunEventRecord,
  ) => Promise<void>;
}

export interface PersistProjectedEventResult {
  readonly artifact: ArtifactRecord | null;
  readonly conversation: ConversationRecord;
  readonly event: RunEventRecord;
  readonly message: MessageRecord | null;
  readonly run: RunRecord;
}

interface PersistProjectedEventInput {
  readonly artifact?: ArtifactRecord | null;
  readonly conversation: ConversationRecord;
  readonly event: RunEventInsertRecord;
  readonly message: MessageRecord | null;
  readonly run: RunRecord;
  readonly syncMessageCursor: boolean;
}

export const truncateSummary = (value: string): string => {
  return value.length <= 160 ? value : `${value.slice(0, 157)}...`;
};

export const formatFailureSummary = (error: unknown): string => {
  if (error instanceof Error && error.message.length > 0) {
    return truncateSummary(error.message);
  }

  return 'run_failed';
};

export const requireConversation = (
  conversation: ConversationRecord | null,
): ConversationRecord => {
  if (!conversation) {
    throw new ApplicationError('not_found', 'conversation_not_found');
  }

  return conversation;
};

export const requireRun = (run: RunRecord | null): RunRecord => {
  if (!run) {
    throw new ApplicationError('not_found', 'run_not_found');
  }

  return run;
};

export const createRunEventDraft = (
  timestamp: Date,
  run: RunRecord,
  input: {
    readonly artifactId?: string | null;
    readonly kind: RunEventKind;
    readonly progressLabel?: string | null;
    readonly stage?: AgentStage | null;
    readonly textDelta?: string | null;
  },
): RunEventInsertRecord => {
  return {
    artifactId: input.artifactId ?? null,
    conversationId: run.conversationId,
    createdAt: timestamp.toISOString(),
    id: createRunEventId(),
    kind: input.kind,
    progressLabel: input.progressLabel ?? null,
    runId: run.id,
    stage: input.stage ?? run.stage,
    textDelta: input.textDelta ?? null,
  };
};

export const createQueuedRunRecord = (
  timestamp: Date,
  input: {
    readonly conversationId: string;
    readonly kind: RunRecord['kind'];
    readonly stage: AgentStage | null;
    readonly userId: string;
    readonly visibleSummary: string;
  },
): RunRecord => {
  const isoTimestamp = timestamp.toISOString();
  return {
    conversationId: input.conversationId,
    createdAt: isoTimestamp,
    id: createRunId(),
    kind: input.kind,
    lastEventCursor: null,
    stage: input.stage,
    status: 'queued',
    updatedAt: isoTimestamp,
    userId: input.userId,
    visibleSummary: input.visibleSummary,
  };
};

export const persistProjectedEvent = async (
  deps: RunProjectionDependencies,
  env: BackendRuntimeContext,
  input: PersistProjectedEventInput,
): Promise<PersistProjectedEventResult> => {
  const insertedEvent = await deps.insertRunEvent(env, input.event);
  const nextRun: RunRecord = {
    ...input.run,
    lastEventCursor: insertedEvent.cursor,
    updatedAt: insertedEvent.createdAt,
  };
  const nextConversation: ConversationRecord = {
    ...input.conversation,
    lastRunId: nextRun.id,
    lastSyncCursor: insertedEvent.cursor,
    updatedAt: insertedEvent.createdAt,
  };
  const nextMessage =
    input.message && input.syncMessageCursor
      ? {
          ...input.message,
          serverCursor: insertedEvent.cursor,
        }
      : input.message;

  if (input.message && input.syncMessageCursor) {
    await deps.updateMessageServerCursor(env, input.message.id, insertedEvent.cursor);
  }

  await deps.updateRun(env, nextRun);
  await deps.updateConversationPointers(env, {
    conversationId: nextConversation.id,
    lastRunId: nextConversation.lastRunId,
    lastSyncCursor: nextConversation.lastSyncCursor,
    updatedAt: nextConversation.updatedAt,
  });

  const projectedEvent: RunEventRecord = {
    ...insertedEvent,
    artifact: input.artifact ?? null,
    conversation: nextConversation,
    message: nextMessage,
    run: nextRun,
  };
  await deps.updateRunEventSnapshots(env, projectedEvent);

  try {
    await deps.publishConversationCursor(env, nextConversation.id, insertedEvent.cursor);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'unknown_error';
    logError('conversation_cursor_publish_failed', {
      conversationId: nextConversation.id,
      cursor: insertedEvent.cursor,
      error: errorMessage,
      runId: nextRun.id,
    });
  }

  return {
    artifact: input.artifact ?? null,
    conversation: nextConversation,
    event: projectedEvent,
    message: nextMessage,
    run: nextRun,
  };
};
