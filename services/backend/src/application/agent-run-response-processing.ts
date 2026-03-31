import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import { logError, sanitizeLogValue } from '../observability/logger.js';
import {
  type AgentProcessSnapshotPayload,
  buildQueuedAgentProcessSnapshot,
  buildRecentUpdate,
  buildStageAgentProcessSnapshot,
  decodeAgentProcessSnapshot,
  encodeAgentProcessSnapshot,
} from './agent-process-payloads.js';
import { buildFinalSynthesisPrompt } from './agent-prompts.js';
import { createAgentRunSupport } from './agent-run-support.js';
import type { AgentRunService, AgentRunServiceDependencies } from './agent-run-types.js';
import { createMessageId } from './ids.js';
import { applyLiveStateToMessage, parseMessageLiveState } from './live-payload-codec.js';
import { createRunEventDraft, persistProjectedEvent } from './run-projection.js';

type AgentRunResponseProcessingOperations = Pick<AgentRunService, 'executeFinalSynthesis'>;

const decodeSnapshot = (run: RunRecord, now: Date): AgentProcessSnapshotPayload => {
  return (
    decodeAgentProcessSnapshot<AgentProcessSnapshotPayload>(run.processSnapshotJSON) ??
    buildQueuedAgentProcessSnapshot({
      now,
      userPrompt: run.visibleSummary ?? 'Agent request',
    })
  );
};

export const createAgentRunResponseProcessingOperations = (
  deps: AgentRunServiceDependencies,
): AgentRunResponseProcessingOperations => {
  const support = createAgentRunSupport(deps);

  return {
    executeFinalSynthesis: async (env, input) => {
      const loadedContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!loadedContext) {
        return null;
      }
      let activeContext = loadedContext;

      const now = deps.now();
      const previousSnapshot = decodeSnapshot(activeContext.run, now);
      const synthesisStartedSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: [],
        activity: 'synthesis',
        currentFocus: previousSnapshot.currentFocus,
        leaderAcceptedFocus: previousSnapshot.leaderAcceptedFocus,
        leaderLiveStatus: 'Synthesizing final answer',
        leaderLiveSummary: 'Synthesizing final answer',
        leaderPlan: input.leaderPlan,
        now,
        recentUpdateItems: [
          ...previousSnapshot.recentUpdateItems,
          buildRecentUpdate({
            kind: 'leaderPhase',
            source: 'leader',
            summary: 'Final synthesis started.',
            timestamp: now,
          }),
        ],
        stageStatuses: {
          finalSynthesis: 'running',
          leaderPlanning: 'completed',
          leaderReview: 'completed',
          workerWave: 'completed',
        },
        tasks: previousSnapshot.tasks,
      });

      const existingAssistantMessage = await deps.findAssistantMessageByRunId(
        env,
        activeContext.run.id,
      );
      let assistantMessage: MessageRecord;
      if (existingAssistantMessage == null) {
        const draftAssistantMessage: MessageRecord = {
          agentTraceJSON: null,
          annotationsJSON: null,
          completedAt: null,
          content: '',
          conversationId: activeContext.conversation.id,
          createdAt: now.toISOString(),
          filePathAnnotationsJSON: null,
          id: createMessageId(),
          role: 'assistant',
          runId: activeContext.run.id,
          serverCursor: null,
          thinking: null,
          toolCallsJSON: null,
        };
        assistantMessage = draftAssistantMessage;
        await deps.insertMessage(env, assistantMessage);
        const draftResult = await persistProjectedEvent(deps, env, {
          conversation: activeContext.conversation,
          event: createRunEventDraft(now, activeContext.run, {
            kind: 'message_created',
            stage: 'final_synthesis',
          }),
          message: assistantMessage,
          run: activeContext.run,
          syncMessageCursor: true,
        });
        activeContext = {
          conversation: draftResult.conversation,
          run: draftResult.run,
        };
        assistantMessage = draftResult.message ?? assistantMessage;
      } else {
        assistantMessage = existingAssistantMessage;
      }

      activeContext = await support.recordStageProgress(env, activeContext, {
        processSnapshotJSON: encodeAgentProcessSnapshot(synthesisStartedSnapshot),
        progressLabel: 'Synthesizing final answer',
        stage: 'final_synthesis',
        visibleSummary: 'Synthesizing final answer',
      });

      let liveState = parseMessageLiveState(assistantMessage);
      let pendingTextDelta = '';
      let streamEventCount = 0;

      const persistAssistantSnapshot = async (input: {
        readonly completedAt?: string | null;
        readonly kind: 'assistant_completed' | 'assistant_delta' | 'run_progress';
        readonly progressLabel?: string | null;
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
          conversation: activeContext.conversation,
          event: createRunEventDraft(deps.now(), activeContext.run, {
            kind: input.kind,
            progressLabel: input.progressLabel ?? null,
            stage: 'final_synthesis',
            textDelta: input.textDelta ?? null,
          }),
          message: assistantMessage,
          run: activeContext.run,
          syncMessageCursor: true,
        });
        activeContext = {
          conversation: result.conversation,
          run: result.run,
        };
        assistantMessage = result.message ?? assistantMessage;
      };

      const apiKey = await support.loadApiKey(env, input.userId);
      const prompt = buildFinalSynthesisPrompt({
        leaderPlan: input.leaderPlan,
        leaderReview: input.leaderReview,
        userPrompt: input.userPrompt,
        workerReport: input.workerReport,
      });
      const broadcastNonFatalDelta = async (
        delta: Parameters<AgentRunServiceDependencies['broadcastStreamDelta']>[2],
      ): Promise<void> => {
        try {
          await deps.broadcastStreamDelta(env, activeContext.conversation.id, delta);
        } catch (error) {
          logError('agent_final_synthesis_broadcast_failed', {
            conversationId: activeContext.conversation.id,
            errorMessage:
              error instanceof Error ? sanitizeLogValue(error.message) : 'unknown_error',
            runId: input.runId,
            stage: 'final_synthesis',
            type: delta.type,
          });
        }
      };

      for await (const event of deps.createStreamingResponse(apiKey, {
        input: prompt,
        reasoningEffort: activeContext.conversation.reasoningEffort ?? 'high',
        serviceTier: activeContext.conversation.serviceTier ?? 'default',
      })) {
        streamEventCount += 1;
        if (streamEventCount % 20 === 0) {
          const latestRun = await deps.findRunById(env, input.runId);
          if (latestRun?.status === 'cancelled') {
            return null;
          }
        }

        switch (event.kind) {
          case 'text_delta':
            liveState = {
              ...liveState,
              content: liveState.content + event.textDelta,
            };
            pendingTextDelta += event.textDelta;
            await broadcastNonFatalDelta({
              type: 'delta',
              data: {
                runId: input.runId,
                stage: 'final_synthesis',
                textDelta: event.textDelta,
              },
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
            await broadcastNonFatalDelta({
              type: 'thinking_delta',
              data: {
                runId: input.runId,
                stage: 'final_synthesis',
                thinkingDelta: event.thinkingDelta,
              },
            });
            await persistAssistantSnapshot({
              kind: 'run_progress',
              progressLabel: 'Synthesizing final answer',
            });
            break;

          case 'thinking_finished':
            await broadcastNonFatalDelta({
              type: 'thinking_done',
              data: { runId: input.runId, stage: 'final_synthesis' },
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
            await broadcastNonFatalDelta({
              type: 'tool_call_update',
              data: {
                runId: input.runId,
                stage: 'final_synthesis',
                toolCall: event.toolCall,
              },
            });
            await persistAssistantSnapshot({
              kind: 'run_progress',
              progressLabel: 'Using tools during synthesis',
            });
            break;

          case 'citation_added':
            liveState = {
              ...liveState,
              citations: [...liveState.citations, event.citation],
            };
            await broadcastNonFatalDelta({
              type: 'citations_update',
              data: {
                citations: liveState.citations,
                runId: input.runId,
                stage: 'final_synthesis',
              },
            });
            await persistAssistantSnapshot({
              kind: 'run_progress',
              progressLabel: 'Collecting citations during synthesis',
            });
            break;

          case 'file_path_annotation_added':
            liveState = {
              ...liveState,
              filePathAnnotations: [...liveState.filePathAnnotations, event.annotation],
            };
            await broadcastNonFatalDelta({
              type: 'file_path_annotations_update',
              data: {
                filePathAnnotations: liveState.filePathAnnotations,
                runId: input.runId,
                stage: 'final_synthesis',
              },
            });
            await persistAssistantSnapshot({
              kind: 'run_progress',
              progressLabel: 'Updating file references during synthesis',
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
              citations: [...event.citations],
              content: event.outputText,
              filePathAnnotations: [...event.filePathAnnotations],
              thinking: event.thinkingText,
              toolCalls: [...event.toolCalls],
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

      return liveState.content;
    },
  };
};
