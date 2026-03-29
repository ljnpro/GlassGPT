import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import {
  createChatRunSupport,
  requireChatConversation,
  requireChatRun,
} from './chat-run-support.js';
import type {
  ChatRunService,
  ChatRunServiceDependencies,
  ChatRunWorkflowParams,
} from './chat-run-types.js';
import { buildRunSummaryDTO } from './dto-mappers.js';
import { ApplicationError } from './errors.js';
import { createMessageId } from './ids.js';
import {
  createQueuedRunRecord,
  createRunEventDraft,
  formatFailureSummary,
  persistProjectedEvent,
  requireConversation,
  requireRun,
  type WorkflowStarter,
} from './run-projection.js';

type ChatRunQueueOperations = Pick<
  ChatRunService,
  'cancelRun' | 'getRun' | 'queueChatRun' | 'retryRun'
>;

interface QueueRunInternalInput {
  readonly content: string;
  readonly conversation: ReturnType<typeof requireChatConversation>;
  readonly createUserMessage: boolean;
  readonly userId: string;
}

export const createChatRunQueueOperations = (
  deps: ChatRunServiceDependencies,
): ChatRunQueueOperations => {
  const support = createChatRunSupport(deps);

  const queueRunInternal = async (
    env: Parameters<ChatRunService['getRun']>[0],
    workflow: WorkflowStarter<ChatRunWorkflowParams>,
    input: QueueRunInternalInput,
  ) => {
    const conversation = requireChatConversation(input.conversation);
    await support.assertCredentialAvailable(env, input.userId);

    let projectedConversation = conversation;
    let run = createQueuedRunRecord(deps.now(), {
      conversationId: projectedConversation.id,
      kind: 'chat',
      stage: null,
      userId: input.userId,
      visibleSummary: 'Queued chat run',
    });

    await deps.insertRun(env, run);

    if (input.createUserMessage) {
      const userMessage: MessageRecord = {
        agentTraceJSON: null,
        annotationsJSON: null,
        completedAt: run.createdAt,
        content: input.content,
        conversationId: projectedConversation.id,
        createdAt: run.createdAt,
        filePathAnnotationsJSON: null,
        id: createMessageId(),
        role: 'user',
        runId: run.id,
        serverCursor: null,
        thinking: null,
        toolCallsJSON: null,
      };
      await deps.insertMessage(env, userMessage);
      ({ conversation: projectedConversation, run } = await persistProjectedEvent(deps, env, {
        conversation: projectedConversation,
        event: createRunEventDraft(deps.now(), run, { kind: 'message_created' }),
        message: userMessage,
        run,
        syncMessageCursor: true,
      }));
    }

    ({ conversation: projectedConversation, run } = await persistProjectedEvent(deps, env, {
      conversation: projectedConversation,
      event: createRunEventDraft(deps.now(), run, { kind: 'run_queued' }),
      message: null,
      run,
      syncMessageCursor: false,
    }));

    try {
      await workflow.create({
        id: run.id,
        params: {
          content: input.content,
          conversationId: projectedConversation.id,
          runId: run.id,
          userId: input.userId,
        },
      });
    } catch (error) {
      const failedRun: RunRecord = {
        ...run,
        status: 'failed',
        visibleSummary: formatFailureSummary(error),
      };
      ({ run } = await persistProjectedEvent(deps, env, {
        conversation: projectedConversation,
        event: createRunEventDraft(deps.now(), failedRun, {
          kind: 'run_failed',
          progressLabel: failedRun.visibleSummary,
        }),
        message: null,
        run: failedRun,
        syncMessageCursor: false,
      }));
    }

    return buildRunSummaryDTO(run);
  };

  return {
    cancelRun: async (env, userId, runId) => {
      const run = requireChatRun(requireRun(await deps.findRunByIdForUser(env, runId, userId)));
      if (run.status === 'completed' || run.status === 'failed' || run.status === 'cancelled') {
        return buildRunSummaryDTO(run);
      }

      const conversation = requireChatConversation(
        requireConversation(
          await deps.findConversationByIdForUser(env, run.conversationId, userId),
        ),
      );
      const cancelledRun: RunRecord = {
        ...run,
        status: 'cancelled',
        visibleSummary: 'Run cancelled',
      };
      const result = await persistProjectedEvent(deps, env, {
        conversation,
        event: createRunEventDraft(deps.now(), cancelledRun, { kind: 'run_cancelled' }),
        message: null,
        run: cancelledRun,
        syncMessageCursor: false,
      });
      return buildRunSummaryDTO(result.run);
    },

    getRun: async (env, userId, runId) => {
      const run = requireChatRun(requireRun(await deps.findRunByIdForUser(env, runId, userId)));
      return buildRunSummaryDTO(run);
    },

    queueChatRun: async (env, workflow, input) => {
      const conversation = requireConversation(
        await deps.findConversationByIdForUser(env, input.conversationId, input.userId),
      );
      return queueRunInternal(env, workflow, {
        content: input.content,
        conversation,
        createUserMessage: true,
        userId: input.userId,
      });
    },

    retryRun: async (env, workflow, userId, runId) => {
      const run = requireChatRun(requireRun(await deps.findRunByIdForUser(env, runId, userId)));
      const message = await deps.findUserMessageByRunId(env, run.id);
      if (!message) {
        throw new ApplicationError('invalid_request', 'retry_source_message_missing');
      }

      const conversation = requireConversation(
        await deps.findConversationByIdForUser(env, run.conversationId, userId),
      );
      return queueRunInternal(env, workflow, {
        content: message.content,
        conversation,
        createUserMessage: false,
        userId,
      });
    },
  };
};
