import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import {
  type AgentProcessSnapshotPayload,
  buildAgentTurnTraceJSON,
  buildQueuedAgentProcessSnapshot,
  buildRecentUpdate,
  buildStageAgentProcessSnapshot,
  decodeAgentProcessSnapshot,
  encodeAgentProcessSnapshot,
} from './agent-process-payloads.js';
import { createAgentRunResponseProcessingOperations } from './agent-run-response-processing.js';
import { createAgentRunSupport } from './agent-run-support.js';
import { createAgentRunToolExecutionOperations } from './agent-run-tool-execution.js';
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

export const createAgentRunExecutionOperations = (
  deps: AgentRunServiceDependencies,
): AgentRunExecutionOperations => {
  const support = createAgentRunSupport(deps);
  const toolExecution = createAgentRunToolExecutionOperations(deps);
  const responseProcessing = createAgentRunResponseProcessingOperations(deps);

  return {
    ...toolExecution,
    ...responseProcessing,

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
      try {
        await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
          type: 'done',
          data: { runId: input.runId, status: 'completed' },
        });
      } catch {
        // Best-effort broadcast; run is already persisted as completed.
      }
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
      try {
        await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
          type: 'done',
          data: { runId: input.runId, status: 'failed' },
        });
      } catch {
        // Best-effort broadcast; run is already persisted as failed.
      }
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
