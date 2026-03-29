import type { RunSummaryDTO } from '@glassgpt/backend-contracts';

import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import { buildRunSummaryDTO } from './dto-mappers.js';
import { ApplicationError } from './errors.js';
import { createMessageId } from './ids.js';
import { applyLiveStateToMessage, parseMessageLiveState } from './live-payload-codec.js';
import type { StreamingConversationRequest } from './live-stream-model.js';
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
  readonly createStreamingResponse: (
    apiKey: string,
    request: StreamingConversationRequest,
  ) => AsyncGenerator<import('./live-stream-model.js').LiveStreamEvent, void, undefined>;
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
  readonly findAssistantMessageByRunId: (
    env: BackendRuntimeContext,
    runId: string,
  ) => Promise<MessageRecord | null>;
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
        const existingAssistantMessage = await deps.findAssistantMessageByRunId(env, run.id);
        let assistantMessage: MessageRecord = existingAssistantMessage ?? {
          agentTraceJSON: null,
          annotationsJSON: null,
          completedAt: null,
          content: '',
          conversationId: conversation.id,
          createdAt: deps.now().toISOString(),
          filePathAnnotationsJSON: null,
          id: createMessageId(),
          role: 'assistant',
          runId: run.id,
          serverCursor: null,
          thinking: null,
          toolCallsJSON: null,
        };

        if (existingAssistantMessage == null) {
          await deps.insertMessage(env, assistantMessage);
          const draftResult = await persistProjectedEvent(deps, env, {
            conversation,
            event: createRunEventDraft(deps.now(), run, {
              kind: 'message_created',
            }),
            message: assistantMessage,
            run,
            syncMessageCursor: true,
          });
          conversation = draftResult.conversation;
          run = draftResult.run;
          assistantMessage = draftResult.message ?? assistantMessage;
        }

        let liveState = parseMessageLiveState(assistantMessage);
        let pendingTextDelta = '';
        let streamEventCount = 0;

        const persistAssistantSnapshot = async (input: {
          readonly kind: 'assistant_completed' | 'assistant_delta' | 'run_progress';
          readonly progressLabel?: string | null;
          readonly completedAt?: string | null;
          readonly textDelta?: string | null;
        }): Promise<void> => {
          assistantMessage = applyLiveStateToMessage(
            assistantMessage,
            liveState,
            input.completedAt === undefined
              ? undefined
              : {
                  completedAt: input.completedAt,
                },
          );
          const result = await persistProjectedEvent(deps, env, {
            conversation,
            event: createRunEventDraft(deps.now(), run, {
              kind: input.kind,
              progressLabel: input.progressLabel ?? null,
              textDelta: input.textDelta ?? null,
            }),
            message: assistantMessage,
            run,
            syncMessageCursor: true,
          });
          conversation = result.conversation;
          run = result.run;
          assistantMessage = result.message ?? assistantMessage;
        };

        for await (const event of deps.createStreamingResponse(apiKey, { input: input.content })) {
          streamEventCount += 1;
          if (streamEventCount % 20 === 0) {
            const latestRun = await deps.findRunById(env, run.id);
            if (latestRun?.status === 'cancelled') {
              return;
            }
          }

          switch (event.kind) {
            case 'text_delta':
              liveState = {
                ...liveState,
                content: liveState.content + event.textDelta,
              };
              pendingTextDelta += event.textDelta;
              try {
                await deps.broadcastStreamDelta(env, conversation.id, {
                  type: 'delta',
                  data: { runId: run.id, textDelta: event.textDelta },
                });
              } catch {
                // Non-fatal.
              }
              if (pendingTextDelta.length >= 24) {
                await persistAssistantSnapshot({
                  kind: 'assistant_delta',
                  textDelta: pendingTextDelta,
                });
                pendingTextDelta = '';
              }
              break;

            case 'thinking_delta':
              liveState = {
                ...liveState,
                thinking: `${liveState.thinking ?? ''}${event.thinkingDelta}`,
              };
              try {
                await deps.broadcastStreamDelta(env, conversation.id, {
                  type: 'thinking_delta',
                  data: { runId: run.id, thinkingDelta: event.thinkingDelta },
                });
              } catch {
                // Non-fatal.
              }
              await persistAssistantSnapshot({
                kind: 'run_progress',
                progressLabel: 'Reasoning',
              });
              break;

            case 'thinking_finished':
              try {
                await deps.broadcastStreamDelta(env, conversation.id, {
                  type: 'thinking_done',
                  data: { runId: run.id },
                });
              } catch {
                // Non-fatal.
              }
              break;

            case 'tool_call_updated':
              liveState = {
                ...liveState,
                toolCalls: [
                  ...liveState.toolCalls.filter((toolCall) => toolCall.id !== event.toolCall.id),
                  event.toolCall,
                ],
              };
              try {
                await deps.broadcastStreamDelta(env, conversation.id, {
                  type: 'tool_call_update',
                  data: { runId: run.id, toolCall: event.toolCall },
                });
              } catch {
                // Non-fatal.
              }
              await persistAssistantSnapshot({
                kind: 'run_progress',
                progressLabel: 'Using tools',
              });
              break;

            case 'citation_added':
              liveState = {
                ...liveState,
                citations: [...liveState.citations, event.citation],
              };
              try {
                await deps.broadcastStreamDelta(env, conversation.id, {
                  type: 'citations_update',
                  data: { citations: liveState.citations, runId: run.id },
                });
              } catch {
                // Non-fatal.
              }
              await persistAssistantSnapshot({
                kind: 'run_progress',
                progressLabel: 'Collecting citations',
              });
              break;

            case 'file_path_annotation_added':
              liveState = {
                ...liveState,
                filePathAnnotations: [...liveState.filePathAnnotations, event.annotation],
              };
              try {
                await deps.broadcastStreamDelta(env, conversation.id, {
                  type: 'file_path_annotations_update',
                  data: { filePathAnnotations: liveState.filePathAnnotations, runId: run.id },
                });
              } catch {
                // Non-fatal.
              }
              await persistAssistantSnapshot({
                kind: 'run_progress',
                progressLabel: 'Updating file references',
              });
              break;

            case 'completed':
              if (pendingTextDelta.length > 0) {
                await persistAssistantSnapshot({
                  kind: 'assistant_delta',
                  textDelta: pendingTextDelta,
                });
                pendingTextDelta = '';
              }
              liveState = {
                ...liveState,
                citations: event.citations,
                content: event.outputText,
                filePathAnnotations: event.filePathAnnotations,
                thinking: event.thinkingText,
                toolCalls: event.toolCalls,
              };
              await persistAssistantSnapshot({
                completedAt: deps.now().toISOString(),
                kind: 'assistant_completed',
              });
              break;

            case 'incomplete':
              throw new Error(event.errorMessage ?? 'openai_response_incomplete');

            case 'failed':
              throw new Error(event.errorMessage);

            case 'response_created':
              break;
          }
        }

        if (liveState.content.length === 0) {
          throw new Error('openai_response_empty');
        }

        try {
          await deps.broadcastStreamDelta(env, conversation.id, {
            type: 'done',
            data: { runId: run.id, status: 'completed' },
          });
        } catch {
          // Non-fatal.
        }

        const completedRun: RunRecord = {
          ...run,
          status: 'completed',
          visibleSummary: truncateSummary(liveState.content),
        };
        ({ run } = await persistProjectedEvent(deps, env, {
          conversation,
          event: createRunEventDraft(deps.now(), completedRun, { kind: 'run_completed' }),
          message: assistantMessage,
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
