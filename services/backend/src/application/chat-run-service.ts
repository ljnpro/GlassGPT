import type { RunSummaryDTO } from '@glassgpt/backend-contracts';

import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import { buildRunSummaryDTO } from './dto-mappers.js';
import { ApplicationError } from './errors.js';
import { createMessageId } from './ids.js';
import {
  createQueuedRunRecord,
  createRunEventDraft,
  formatFailureSummary,
  persistProjectedEvent,
  type RunProjectionDependencies,
  requireConversation,
  requireRun,
  truncateSummary,
  type WorkflowStarter,
} from './run-projection.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const requireValidCredential = (
  credential: ProviderCredentialRecord | null,
): ProviderCredentialRecord => {
  if (!credential || credential.status !== 'valid') {
    throw new ApplicationError('forbidden', 'openai_credential_unavailable');
  }

  return credential;
};

const requireChatConversation = (conversation: ConversationRecord): ConversationRecord => {
  if (conversation.mode !== 'chat') {
    throw new ApplicationError('invalid_request', 'conversation_not_chat_mode');
  }

  return conversation;
};

const requireChatRun = (run: RunRecord): RunRecord => {
  if (run.kind !== 'chat') {
    throw new ApplicationError('invalid_request', 'run_not_chat_kind');
  }

  return run;
};

export interface ChatRunWorkflowParams {
  readonly runId: string;
  readonly conversationId: string;
  readonly userId: string;
  readonly content: string;
}

export interface ChatRunServiceDependencies extends RunProjectionDependencies {
  readonly createChatCompletion: (apiKey: string, input: string) => Promise<string>;
  readonly createStreamingChatCompletion: (
    apiKey: string,
    input: string,
  ) => AsyncGenerator<string, void, undefined>;
  readonly decryptSecret: (
    env: BackendRuntimeContext,
    encrypted: {
      readonly ciphertext: string;
      readonly keyVersion: string;
      readonly nonce: string;
    },
  ) => Promise<string>;
  readonly findConversationByIdForUser: (
    env: BackendRuntimeContext,
    conversationId: string,
    userId: string,
  ) => Promise<ConversationRecord | null>;
  readonly findProviderCredential: (
    env: BackendRuntimeContext,
    userId: string,
    provider: 'openai',
  ) => Promise<ProviderCredentialRecord | null>;
  readonly findRunById: (env: BackendRuntimeContext, runId: string) => Promise<RunRecord | null>;
  readonly findRunByIdForUser: (
    env: BackendRuntimeContext,
    runId: string,
    userId: string,
  ) => Promise<RunRecord | null>;
  readonly findUserMessageByRunId: (
    env: BackendRuntimeContext,
    runId: string,
  ) => Promise<MessageRecord | null>;
  readonly insertMessage: (env: BackendRuntimeContext, message: MessageRecord) => Promise<void>;
  readonly insertRun: (env: BackendRuntimeContext, run: RunRecord) => Promise<void>;
  readonly now: () => Date;
}

export interface ChatRunService {
  cancelRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  executeQueuedRun(env: BackendRuntimeContext, input: ChatRunWorkflowParams): Promise<void>;
  getRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  queueChatRun(
    env: BackendRuntimeContext,
    workflow: WorkflowStarter<ChatRunWorkflowParams>,
    input: {
      readonly content: string;
      readonly conversationId: string;
      readonly userId: string;
    },
  ): Promise<RunSummaryDTO>;
  retryRun(
    env: BackendRuntimeContext,
    workflow: WorkflowStarter<ChatRunWorkflowParams>,
    userId: string,
    runId: string,
  ): Promise<RunSummaryDTO>;
}

interface QueueRunInternalInput {
  readonly content: string;
  readonly conversation: ConversationRecord;
  readonly createUserMessage: boolean;
  readonly userId: string;
}

export const createChatRunService = (deps: ChatRunServiceDependencies): ChatRunService => {
  const queueRunInternal = async (
    env: BackendRuntimeContext,
    workflow: WorkflowStarter<ChatRunWorkflowParams>,
    input: QueueRunInternalInput,
  ): Promise<RunSummaryDTO> => {
    const conversation = requireChatConversation(input.conversation);
    requireValidCredential(await deps.findProviderCredential(env, input.userId, 'openai'));

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
        completedAt: run.createdAt,
        content: input.content,
        conversationId: projectedConversation.id,
        createdAt: run.createdAt,
        id: createMessageId(),
        role: 'user',
        runId: run.id,
        serverCursor: null,
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

    executeQueuedRun: async (env, input) => {
      let run = requireChatRun(requireRun(await deps.findRunById(env, input.runId)));
      if (run.status === 'cancelled' || run.status === 'completed') {
        return;
      }

      let conversation = requireChatConversation(
        requireConversation(
          await deps.findConversationByIdForUser(env, run.conversationId, input.userId),
        ),
      );
      const runningRun: RunRecord = {
        ...run,
        status: 'running',
        visibleSummary: 'Generating response',
      };

      ({ conversation, run } = await persistProjectedEvent(deps, env, {
        conversation,
        event: createRunEventDraft(deps.now(), runningRun, {
          kind: 'run_started',
          progressLabel: 'Generating response',
        }),
        message: null,
        run: runningRun,
        syncMessageCursor: false,
      }));

      ({ conversation, run } = await persistProjectedEvent(deps, env, {
        conversation,
        event: createRunEventDraft(deps.now(), run, {
          kind: 'run_progress',
          progressLabel: 'Contacting OpenAI',
        }),
        message: null,
        run,
        syncMessageCursor: false,
      }));

      try {
        const credential = requireValidCredential(
          await deps.findProviderCredential(env, input.userId, 'openai'),
        );
        const apiKey = await deps.decryptSecret(env, credential);

        // Stream tokens from OpenAI, emitting delta events as they arrive
        const chunks: string[] = [];
        let pendingDelta = '';
        const DELTA_FLUSH_THRESHOLD = 5;
        let chunkCount = 0;

        for await (const delta of deps.createStreamingChatCompletion(apiKey, input.content)) {
          // Check for cancellation between chunks
          const latestRun = chunkCount % 20 === 0 ? await deps.findRunById(env, run.id) : null;
          if (latestRun?.status === 'cancelled') {
            return;
          }

          chunks.push(delta);
          pendingDelta += delta;
          chunkCount++;

          // Broadcast every token directly to SSE clients via Durable Object (bypasses D1)
          try {
            await deps.broadcastStreamDelta(env, conversation.id, {
              type: 'delta',
              data: { textDelta: delta, runId: run.id },
            });
          } catch {
            // Non-fatal: broadcast failure doesn't block execution
          }

          // Persist delta events to D1 less frequently (for catch-up and history)
          if (chunkCount % DELTA_FLUSH_THRESHOLD === 0) {
            ({ conversation, run } = await persistProjectedEvent(deps, env, {
              conversation,
              event: createRunEventDraft(deps.now(), run, {
                kind: 'assistant_delta',
                textDelta: pendingDelta,
              }),
              message: null,
              run,
              syncMessageCursor: false,
            }));
            pendingDelta = '';
          }
        }

        const assistantText = chunks.join('');
        if (assistantText.length === 0) {
          throw new Error('openai_response_empty');
        }

        // Flush any remaining delta to D1
        if (pendingDelta.length > 0) {
          ({ conversation, run } = await persistProjectedEvent(deps, env, {
            conversation,
            event: createRunEventDraft(deps.now(), run, {
              kind: 'assistant_delta',
              textDelta: pendingDelta,
            }),
            message: null,
            run,
            syncMessageCursor: false,
          }));
        }

        // Broadcast completion to SSE clients
        try {
          await deps.broadcastStreamDelta(env, conversation.id, {
            type: 'done',
            data: { runId: run.id, status: 'completed' },
          });
        } catch {
          // Non-fatal
        }

        // Create the final assistant message with full text
        const assistantMessage: MessageRecord = {
          completedAt: deps.now().toISOString(),
          content: assistantText,
          conversationId: conversation.id,
          createdAt: deps.now().toISOString(),
          id: createMessageId(),
          role: 'assistant',
          runId: run.id,
          serverCursor: null,
        };
        await deps.insertMessage(env, assistantMessage);

        let projectedAssistantMessage: MessageRecord | null = assistantMessage;
        ({
          conversation,
          run,
          message: projectedAssistantMessage,
        } = await persistProjectedEvent(deps, env, {
          conversation,
          event: createRunEventDraft(deps.now(), run, { kind: 'assistant_completed' }),
          message: assistantMessage,
          run,
          syncMessageCursor: true,
        }));

        const completedRun: RunRecord = {
          ...run,
          status: 'completed',
          visibleSummary: truncateSummary(assistantText),
        };
        ({ run } = await persistProjectedEvent(deps, env, {
          conversation,
          event: createRunEventDraft(deps.now(), completedRun, { kind: 'run_completed' }),
          message: projectedAssistantMessage,
          run: completedRun,
          syncMessageCursor: false,
        }));
      } catch (error) {
        const failedRun: RunRecord = {
          ...run,
          status: 'failed',
          visibleSummary: formatFailureSummary(error),
        };
        await persistProjectedEvent(deps, env, {
          conversation,
          event: createRunEventDraft(deps.now(), failedRun, {
            kind: 'run_failed',
            progressLabel: failedRun.visibleSummary,
          }),
          message: null,
          run: failedRun,
          syncMessageCursor: false,
        });
      }
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
