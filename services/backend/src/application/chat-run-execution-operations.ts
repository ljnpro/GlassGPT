import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import { logError, sanitizeLogValue } from '../observability/logger.js';
import { buildChatExecutionRequest, createChatRunSupport } from './chat-run-support.js';
import type { ChatRunService, ChatRunServiceDependencies } from './chat-run-types.js';
import { createMessageId } from './ids.js';
import { applyLiveStateToMessage, parseMessageLiveState } from './live-payload-codec.js';
import {
  createRunEventDraft,
  formatFailureSummary,
  persistProjectedEvent,
  truncateSummary,
} from './run-projection.js';
import { createStreamDeltaDispatcher } from './stream-delta-dispatcher.js';

type ChatRunExecutionOperations = Pick<ChatRunService, 'executeQueuedRun'>;
type BroadcastDelta = Parameters<ChatRunServiceDependencies['broadcastStreamDelta']>[2];

export const createChatRunExecutionOperations = (
  deps: ChatRunServiceDependencies,
): ChatRunExecutionOperations => {
  const support = createChatRunSupport(deps);

  return {
    executeQueuedRun: async (env, input) => {
      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return;
      }

      let { conversation, run } = activeContext;
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
        const apiKey = await support.loadApiKey(env, input.userId);
        const allMessages = await deps.listMessagesForConversation(env, conversation.id);
        // Exclude messages from the current run (user message already included
        // in input.content; assistant message is being created now).
        const conversationHistory = allMessages.filter((m) => m.runId !== run.id);
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

        const deltaDispatcher = createStreamDeltaDispatcher<BroadcastDelta>({
          dispatch: async (delta) => {
            await deps.broadcastStreamDelta(env, conversation.id, delta);
          },
          onError: (error, delta) => {
            const errorMessage =
              error instanceof Error ? sanitizeLogValue(error.message) : 'unknown_error';
            logError('chat_stream_broadcast_failed', {
              conversationId: conversation.id,
              deltaType: delta.type,
              error: errorMessage,
              runId: run.id,
            });
          },
        });

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

        for await (const event of deps.createStreamingResponse(
          apiKey,
          buildChatExecutionRequest(
            conversation,
            input.content,
            conversationHistory,
            input.imageBase64,
            input.fileIds,
          ),
        )) {
          streamEventCount += 1;
          if (streamEventCount % 20 === 0) {
            const latestRun = await deps.findRunById(env, run.id);
            if (latestRun?.status === 'cancelled') {
              deltaDispatcher.enqueue({
                type: 'done',
                data: { runId: run.id, status: 'cancelled' },
              });
              await deltaDispatcher.flush();
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
              deltaDispatcher.enqueue({
                type: 'delta',
                data: { runId: run.id, textDelta: event.textDelta },
              });
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
              deltaDispatcher.enqueue({
                type: 'thinking_delta',
                data: { runId: run.id, thinkingDelta: event.thinkingDelta },
              });
              await persistAssistantSnapshot({
                kind: 'run_progress',
                progressLabel: 'Reasoning',
              });
              break;

            case 'thinking_finished':
              deltaDispatcher.enqueue({
                type: 'thinking_done',
                data: { runId: run.id },
              });
              break;

            case 'tool_call_updated':
              liveState = {
                ...liveState,
                toolCalls: [
                  ...liveState.toolCalls.filter((toolCall) => toolCall.id !== event.toolCall.id),
                  event.toolCall,
                ],
              };
              deltaDispatcher.enqueue({
                type: 'tool_call_update',
                data: { runId: run.id, toolCall: event.toolCall },
              });
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
              deltaDispatcher.enqueue({
                type: 'citations_update',
                data: { citations: liveState.citations, runId: run.id },
              });
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
              deltaDispatcher.enqueue({
                type: 'file_path_annotations_update',
                data: { filePathAnnotations: liveState.filePathAnnotations, runId: run.id },
              });
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

        // Flush any remaining pending text that was not persisted during
        // streaming (responses shorter than the 24-char batch threshold).
        if (pendingTextDelta.length > 0) {
          await persistAssistantSnapshot({
            kind: 'assistant_delta',
            textDelta: pendingTextDelta,
          });
          pendingTextDelta = '';
        }

        // If the streaming generator returned without yielding a 'completed'
        // event (e.g. OpenAI sent [DONE] without response.completed), the
        // liveState.content may still reflect the accumulated text deltas.
        // Ensure the assistant message is persisted with final state.
        if (liveState.content.length > 0 && assistantMessage.content !== liveState.content) {
          assistantMessage = applyLiveStateToMessage(assistantMessage, liveState, {
            completedAt: deps.now().toISOString(),
          });
          const result = await persistProjectedEvent(deps, env, {
            conversation,
            event: createRunEventDraft(deps.now(), run, {
              kind: 'assistant_completed',
            }),
            message: assistantMessage,
            run,
            syncMessageCursor: true,
          });
          conversation = result.conversation;
          run = result.run;
          assistantMessage = result.message ?? assistantMessage;
        }

        if (liveState.content.length === 0) {
          throw new Error('openai_response_empty');
        }

        deltaDispatcher.enqueue({
          type: 'done',
          data: { runId: run.id, status: 'completed' },
        });
        await deltaDispatcher.flush();

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
        try {
          await deps.broadcastStreamDelta(env, conversation.id, {
            type: 'done',
            data: { runId: run.id, status: 'failed' },
          });
        } catch {
          // Best-effort broadcast; run is already persisted as failed.
        }
      }
    },
  };
};
