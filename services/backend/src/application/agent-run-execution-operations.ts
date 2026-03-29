import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import {
  type AgentProcessSnapshotPayload,
  type AgentTaskPayload,
  buildAgentTurnTraceJSON,
  buildQueuedAgentProcessSnapshot,
  buildRecentUpdate,
  buildStageAgentProcessSnapshot,
  buildWorkerWaveTasks,
  decodeAgentProcessSnapshot,
  encodeAgentProcessSnapshot,
} from './agent-process-payloads.js';
import {
  buildFinalSynthesisPrompt,
  buildLeaderPlanningPrompt,
  buildLeaderReviewPrompt,
  buildWorkerWavePrompt,
} from './agent-prompts.js';
import { createAgentRunSupport } from './agent-run-support.js';
import type { AgentRunService, AgentRunServiceDependencies } from './agent-run-types.js';
import { createMessageId } from './ids.js';
import { applyLiveStateToMessage, parseMessageLiveState } from './live-payload-codec.js';
import {
  createRunEventDraft,
  formatFailureSummary,
  persistProjectedEvent,
  truncateSummary,
} from './run-projection.js';

type AgentRunExecutionOperations = Pick<
  AgentRunService,
  | 'completeRun'
  | 'executeFinalSynthesis'
  | 'executeLeaderPlanning'
  | 'executeLeaderReview'
  | 'executeWorkerWave'
  | 'failRun'
  | 'startQueuedRun'
>;

const summarizeProcessOutcome = (value: string): string => truncateSummary(value);

const decodeSnapshot = (run: RunRecord, now: Date): AgentProcessSnapshotPayload => {
  return (
    decodeAgentProcessSnapshot<AgentProcessSnapshotPayload>(run.processSnapshotJSON) ??
    buildQueuedAgentProcessSnapshot({
      now,
      userPrompt: run.visibleSummary ?? 'Agent request',
    })
  );
};

const runningWorkerTasks = (tasks: readonly AgentTaskPayload[], now: Date): AgentTaskPayload[] => {
  return tasks.map((task) => ({
    ...task,
    liveStatusText: 'Running',
    startedAt: now,
    status: 'running',
  }));
};

export const createAgentRunExecutionOperations = (
  deps: AgentRunServiceDependencies,
): AgentRunExecutionOperations => {
  const support = createAgentRunSupport(deps);

  return {
    completeRun: async (env, input) => {
      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return;
      }

      const now = deps.now();
      const previousSnapshot = decodeSnapshot(activeContext.run, now);
      const finalizedSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: [],
        activity: 'completed',
        currentFocus: previousSnapshot.currentFocus,
        leaderAcceptedFocus: previousSnapshot.leaderAcceptedFocus,
        leaderLiveStatus: 'Completed',
        leaderLiveSummary: summarizeProcessOutcome(input.finalText),
        leaderPlan: previousSnapshot.currentFocus,
        now,
        outcome: input.finalText,
        recentUpdateItems: [
          ...previousSnapshot.recentUpdateItems,
          buildRecentUpdate({
            kind: 'councilCompleted',
            source: 'leader',
            summary: 'Final answer completed.',
            timestamp: now,
          }),
        ],
        stageStatuses: {
          finalSynthesis: 'completed',
          leaderPlanning: 'completed',
          leaderReview: 'completed',
          workerWave: 'completed',
        },
        stopReason: 'sufficientAnswer',
        tasks: previousSnapshot.tasks,
      });

      const existingAssistantMessage = await deps.findAssistantMessageByRunId(
        env,
        activeContext.run.id,
      );
      const workerSummary = previousSnapshot.tasks
        .map((task) => task.resultSummary ?? task.liveSummary ?? '')
        .filter((summary) => summary.length > 0)
        .join('\n');
      const fallbackAssistantMessage: MessageRecord = {
        agentTraceJSON: null,
        annotationsJSON: null,
        completedAt: now.toISOString(),
        content: input.finalText,
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
      let assistantMessage: MessageRecord =
        existingAssistantMessage == null
          ? fallbackAssistantMessage
          : applyLiveStateToMessage(
              existingAssistantMessage,
              {
                ...parseMessageLiveState(existingAssistantMessage),
                agentTraceJSON: null,
                content: input.finalText,
              },
              {
                completedAt: existingAssistantMessage.completedAt ?? now.toISOString(),
              },
            );

      assistantMessage = {
        ...assistantMessage,
        agentTraceJSON: buildAgentTurnTraceJSON({
          completedAt: now,
          leaderBriefSummary: previousSnapshot.leaderAcceptedFocus,
          outcome: input.finalText,
          processSnapshot: finalizedSnapshot,
          workerSummary,
        }),
      };

      if (existingAssistantMessage == null) {
        await deps.insertMessage(env, assistantMessage);
      }

      const completedRun: RunRecord = {
        ...activeContext.run,
        processSnapshotJSON: encodeAgentProcessSnapshot(finalizedSnapshot),
        status: 'completed',
        visibleSummary: truncateSummary(input.finalText),
      };
      await persistProjectedEvent(deps, env, {
        conversation: activeContext.conversation,
        event: createRunEventDraft(deps.now(), completedRun, {
          kind: 'run_completed',
          stage: 'final_synthesis',
        }),
        message: assistantMessage,
        run: completedRun,
        syncMessageCursor: false,
      });
    },

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

      for await (const event of deps.createStreamingResponse(apiKey, { input: prompt })) {
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
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'delta',
                data: {
                  runId: input.runId,
                  stage: 'final_synthesis',
                  textDelta: event.textDelta,
                },
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
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'thinking_delta',
                data: {
                  runId: input.runId,
                  stage: 'final_synthesis',
                  thinkingDelta: event.thinkingDelta,
                },
              });
            } catch {
              // Non-fatal.
            }
            await persistAssistantSnapshot({
              kind: 'run_progress',
              progressLabel: 'Synthesizing final answer',
            });
            break;

          case 'thinking_finished':
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'thinking_done',
                data: { runId: input.runId, stage: 'final_synthesis' },
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
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'tool_call_update',
                data: {
                  runId: input.runId,
                  stage: 'final_synthesis',
                  toolCall: event.toolCall,
                },
              });
            } catch {
              // Non-fatal.
            }
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
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'citations_update',
                data: {
                  citations: liveState.citations,
                  runId: input.runId,
                  stage: 'final_synthesis',
                },
              });
            } catch {
              // Non-fatal.
            }
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
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'file_path_annotations_update',
                data: {
                  filePathAnnotations: liveState.filePathAnnotations,
                  runId: input.runId,
                  stage: 'final_synthesis',
                },
              });
            } catch {
              // Non-fatal.
            }
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

    executeLeaderPlanning: async (env, input) => {
      const leaderPlan = await support.completeStageText(env, {
        prompt: buildLeaderPlanningPrompt(input.prompt),
        runId: input.runId,
        userId: input.userId,
      });
      if (!leaderPlan) {
        return null;
      }

      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return null;
      }

      const now = deps.now();
      const previousSnapshot = decodeSnapshot(activeContext.run, now);
      const queuedTasks = buildWorkerWaveTasks({
        leaderPlan,
        now,
        userPrompt: input.prompt,
      });
      const planningSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: [],
        activity: 'triage',
        currentFocus: leaderPlan,
        leaderAcceptedFocus: input.prompt,
        leaderLiveStatus: 'Leader plan ready',
        leaderLiveSummary: summarizeProcessOutcome(leaderPlan),
        leaderPlan,
        now,
        recentUpdateItems: [
          ...previousSnapshot.recentUpdateItems,
          buildRecentUpdate({
            kind: 'leaderPhase',
            source: 'leader',
            summary: 'Leader plan ready.',
            timestamp: now,
          }),
        ],
        stageStatuses: {
          finalSynthesis: 'planned',
          leaderPlanning: 'completed',
          leaderReview: 'planned',
          workerWave: 'planned',
        },
        tasks: queuedTasks,
      });

      const planningContext = await support.recordStageProgress(env, activeContext, {
        processSnapshotJSON: encodeAgentProcessSnapshot(planningSnapshot),
        progressLabel: 'Leader plan ready',
        stage: 'leader_planning',
        visibleSummary: `Plan ready: ${truncateSummary(leaderPlan)}`,
      });

      const workerWaveSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: queuedTasks.map((task) => task.id),
        activity: 'delegation',
        currentFocus: planningSnapshot.currentFocus,
        leaderAcceptedFocus: planningSnapshot.leaderAcceptedFocus,
        leaderLiveStatus: 'Workers running',
        leaderLiveSummary: 'Dispatching worker wave',
        leaderPlan,
        now,
        recentUpdateItems: [
          ...planningSnapshot.recentUpdateItems,
          buildRecentUpdate({
            kind: 'workerWaveQueued',
            source: 'leader',
            summary: 'Dispatching worker wave.',
            timestamp: now,
          }),
          ...queuedTasks.map((task) =>
            buildRecentUpdate({
              kind: 'workerStarted',
              source: task.owner,
              summary: `${task.title} started.`,
              taskID: task.id,
              timestamp: now,
            }),
          ),
        ],
        stageStatuses: {
          finalSynthesis: 'planned',
          leaderPlanning: 'completed',
          leaderReview: 'planned',
          workerWave: 'running',
        },
        tasks: runningWorkerTasks(queuedTasks, now),
      });

      await support.recordStageChange(env, planningContext, {
        processSnapshotJSON: encodeAgentProcessSnapshot(workerWaveSnapshot),
        progressLabel: 'Dispatching worker wave',
        stage: 'worker_wave',
        visibleSummary: 'Executing worker wave',
      });

      return leaderPlan;
    },

    executeLeaderReview: async (env, input) => {
      const leaderReview = await support.completeStageText(env, {
        prompt: buildLeaderReviewPrompt({
          leaderPlan: input.leaderPlan,
          userPrompt: input.userPrompt,
          workerReport: input.workerReport,
        }),
        runId: input.runId,
        userId: input.userId,
      });
      if (!leaderReview) {
        return null;
      }

      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return null;
      }

      const now = deps.now();
      const previousSnapshot = decodeSnapshot(activeContext.run, now);
      const reviewSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: [],
        activity: 'reviewing',
        currentFocus: previousSnapshot.currentFocus,
        leaderAcceptedFocus: previousSnapshot.leaderAcceptedFocus,
        leaderLiveStatus: 'Leader review ready',
        leaderLiveSummary: summarizeProcessOutcome(leaderReview),
        leaderPlan: input.leaderPlan,
        now,
        recentUpdateItems: [
          ...previousSnapshot.recentUpdateItems,
          buildRecentUpdate({
            kind: 'leaderPhase',
            source: 'leader',
            summary: 'Leader review ready.',
            timestamp: now,
          }),
        ],
        stageStatuses: {
          finalSynthesis: 'planned',
          leaderPlanning: 'completed',
          leaderReview: 'completed',
          workerWave: 'completed',
        },
        tasks: previousSnapshot.tasks,
      });

      const reviewContext = await support.recordStageProgress(env, activeContext, {
        processSnapshotJSON: encodeAgentProcessSnapshot(reviewSnapshot),
        progressLabel: 'Leader review ready',
        stage: 'leader_review',
        visibleSummary: `Review ready: ${truncateSummary(leaderReview)}`,
      });

      const synthesisSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: [],
        activity: 'synthesis',
        currentFocus: reviewSnapshot.currentFocus,
        leaderAcceptedFocus: reviewSnapshot.leaderAcceptedFocus,
        leaderLiveStatus: 'Preparing synthesis',
        leaderLiveSummary: 'Preparing final synthesis',
        leaderPlan: input.leaderPlan,
        now,
        recentUpdateItems: [
          ...reviewSnapshot.recentUpdateItems,
          buildRecentUpdate({
            kind: 'leaderPhase',
            source: 'leader',
            summary: 'Preparing final synthesis.',
            timestamp: now,
          }),
        ],
        stageStatuses: {
          finalSynthesis: 'running',
          leaderPlanning: 'completed',
          leaderReview: 'completed',
          workerWave: 'completed',
        },
        tasks: reviewSnapshot.tasks,
      });

      await support.recordStageChange(env, reviewContext, {
        processSnapshotJSON: encodeAgentProcessSnapshot(synthesisSnapshot),
        progressLabel: 'Preparing final synthesis',
        stage: 'final_synthesis',
        visibleSummary: 'Preparing final synthesis',
      });

      return leaderReview;
    },

    executeWorkerWave: async (env, input) => {
      const workerReport = await support.completeStageText(env, {
        prompt: buildWorkerWavePrompt({
          leaderPlan: input.leaderPlan,
          userPrompt: input.userPrompt,
        }),
        runId: input.runId,
        userId: input.userId,
      });
      if (!workerReport) {
        return null;
      }

      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return null;
      }

      const now = deps.now();
      const previousSnapshot = decodeSnapshot(activeContext.run, now);
      const completedTasks = buildWorkerWaveTasks({
        leaderPlan: input.leaderPlan,
        now,
        userPrompt: input.userPrompt,
        workerSummary: workerReport,
      });
      const workerSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: [],
        activity: 'delegation',
        currentFocus: previousSnapshot.currentFocus,
        leaderAcceptedFocus: previousSnapshot.leaderAcceptedFocus,
        leaderLiveStatus: 'Worker findings ready',
        leaderLiveSummary: summarizeProcessOutcome(workerReport),
        leaderPlan: input.leaderPlan,
        now,
        recentUpdateItems: [
          ...previousSnapshot.recentUpdateItems,
          ...completedTasks.map((task) =>
            buildRecentUpdate({
              kind: 'workerCompleted',
              source: task.owner,
              summary: `${task.title} completed.`,
              taskID: task.id,
              timestamp: now,
            }),
          ),
        ],
        stageStatuses: {
          finalSynthesis: 'planned',
          leaderPlanning: 'completed',
          leaderReview: 'planned',
          workerWave: 'completed',
        },
        tasks: completedTasks,
      });

      const workerContext = await support.recordStageProgress(env, activeContext, {
        processSnapshotJSON: encodeAgentProcessSnapshot(workerSnapshot),
        progressLabel: 'Worker findings ready',
        stage: 'worker_wave',
        visibleSummary: `Worker findings: ${truncateSummary(workerReport)}`,
      });

      const leaderReviewSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: [],
        activity: 'reviewing',
        currentFocus: workerSnapshot.currentFocus,
        leaderAcceptedFocus: workerSnapshot.leaderAcceptedFocus,
        leaderLiveStatus: 'Leader reviewing',
        leaderLiveSummary: 'Starting leader review',
        leaderPlan: input.leaderPlan,
        now,
        recentUpdateItems: [
          ...workerSnapshot.recentUpdateItems,
          buildRecentUpdate({
            kind: 'leaderPhase',
            source: 'leader',
            summary: 'Leader review started.',
            timestamp: now,
          }),
        ],
        stageStatuses: {
          finalSynthesis: 'planned',
          leaderPlanning: 'completed',
          leaderReview: 'running',
          workerWave: 'completed',
        },
        tasks: completedTasks,
      });

      await support.recordStageChange(env, workerContext, {
        processSnapshotJSON: encodeAgentProcessSnapshot(leaderReviewSnapshot),
        progressLabel: 'Starting leader review',
        stage: 'leader_review',
        visibleSummary: 'Reviewing worker output',
      });

      return workerReport;
    },

    failRun: async (env, input) => {
      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return;
      }

      const now = deps.now();
      const previousSnapshot = decodeSnapshot(activeContext.run, now);
      const failedRun: RunRecord = {
        ...activeContext.run,
        processSnapshotJSON: encodeAgentProcessSnapshot(
          buildStageAgentProcessSnapshot({
            activeTaskIDs: [],
            activity: 'failed',
            currentFocus: previousSnapshot.currentFocus,
            leaderAcceptedFocus: previousSnapshot.leaderAcceptedFocus,
            leaderLiveStatus: 'Failed',
            leaderLiveSummary: formatFailureSummary(input.error),
            leaderPlan: previousSnapshot.currentFocus,
            now,
            outcome: '',
            recentUpdateItems: previousSnapshot.recentUpdateItems,
            stageStatuses: {
              finalSynthesis: activeContext.run.stage === 'final_synthesis' ? 'blocked' : 'planned',
              leaderPlanning: 'completed',
              leaderReview: 'blocked',
              workerWave: 'blocked',
            },
            stopReason: 'toolFailure',
            tasks: previousSnapshot.tasks,
          }),
        ),
        status: 'failed',
        visibleSummary: formatFailureSummary(input.error),
      };
      await persistProjectedEvent(deps, env, {
        conversation: activeContext.conversation,
        event: createRunEventDraft(deps.now(), failedRun, {
          kind: 'run_failed',
          progressLabel: failedRun.visibleSummary,
          stage: failedRun.stage,
        }),
        message: null,
        run: failedRun,
        syncMessageCursor: false,
      });
    },

    startQueuedRun: async (env, input) => {
      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return false;
      }

      const now = deps.now();
      const previousSnapshot = decodeSnapshot(activeContext.run, now);
      const runningSnapshot = buildStageAgentProcessSnapshot({
        activeTaskIDs: [],
        activity: 'triage',
        currentFocus: previousSnapshot.currentFocus,
        leaderAcceptedFocus: previousSnapshot.leaderAcceptedFocus,
        leaderLiveStatus: 'Leader planning',
        leaderLiveSummary: 'Planning agent workflow',
        leaderPlan: null,
        now,
        recentUpdateItems: [
          ...previousSnapshot.recentUpdateItems,
          buildRecentUpdate({
            kind: 'leaderPhase',
            source: 'leader',
            summary: 'Planning agent workflow.',
            timestamp: now,
          }),
        ],
        stageStatuses: {
          finalSynthesis: 'planned',
          leaderPlanning: 'running',
          leaderReview: 'planned',
          workerWave: 'planned',
        },
        tasks: previousSnapshot.tasks,
      });

      const runningRun: RunRecord = {
        ...activeContext.run,
        processSnapshotJSON: encodeAgentProcessSnapshot(runningSnapshot),
        stage: 'leader_planning',
        status: 'running',
        visibleSummary: 'Planning agent workflow',
      };
      const startedContext = await persistProjectedEvent(deps, env, {
        conversation: activeContext.conversation,
        event: createRunEventDraft(deps.now(), runningRun, {
          kind: 'run_started',
          progressLabel: 'Planning agent workflow',
          stage: 'leader_planning',
        }),
        message: null,
        run: runningRun,
        syncMessageCursor: false,
      });
      await support.recordStageProgress(
        env,
        {
          conversation: startedContext.conversation,
          run: startedContext.run,
        },
        {
          processSnapshotJSON: encodeAgentProcessSnapshot(runningSnapshot),
          progressLabel: 'Drafting execution plan',
          stage: 'leader_planning',
          visibleSummary: 'Drafting execution plan',
        },
      );
      return true;
    },
  };
};
