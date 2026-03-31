import type { RunRecord } from '../domain/run-model.js';
import {
  type AgentProcessSnapshotPayload,
  type AgentTaskPayload,
  buildQueuedAgentProcessSnapshot,
  buildRecentUpdate,
  buildStageAgentProcessSnapshot,
  buildWorkerWaveTasks,
  decodeAgentProcessSnapshot,
  encodeAgentProcessSnapshot,
} from './agent-process-payloads.js';
import {
  buildLeaderPlanningPrompt,
  buildLeaderReviewPrompt,
  buildWorkerWavePrompt,
} from './agent-prompts.js';
import { createAgentRunSupport } from './agent-run-support.js';
import type { AgentRunService, AgentRunServiceDependencies } from './agent-run-types.js';
import { truncateSummary } from './run-projection.js';

type AgentRunToolExecutionOperations = Pick<
  AgentRunService,
  'executeLeaderPlanning' | 'executeLeaderReview' | 'executeWorkerWave'
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

export const createAgentRunToolExecutionOperations = (
  deps: AgentRunServiceDependencies,
): AgentRunToolExecutionOperations => {
  const support = createAgentRunSupport(deps);

  return {
    executeLeaderPlanning: async (env, input) => {
      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return null;
      }

      const leaderPlan = await support.completeStageText(env, {
        prompt: buildLeaderPlanningPrompt(input.prompt),
        reasoningEffort: activeContext.conversation.reasoningEffort ?? 'high',
        runId: input.runId,
        serviceTier: activeContext.conversation.serviceTier ?? 'default',
        userId: input.userId,
      });
      if (!leaderPlan) {
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
      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return null;
      }

      const leaderReview = await support.completeStageText(env, {
        prompt: buildLeaderReviewPrompt({
          leaderPlan: input.leaderPlan,
          userPrompt: input.userPrompt,
          workerReport: input.workerReport,
        }),
        reasoningEffort: activeContext.conversation.reasoningEffort ?? 'high',
        runId: input.runId,
        serviceTier: activeContext.conversation.serviceTier ?? 'default',
        userId: input.userId,
      });
      if (!leaderReview) {
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
      const activeContext = await support.loadActiveExecutionContext(
        env,
        input.runId,
        input.userId,
      );
      if (!activeContext) {
        return null;
      }

      const workerReport = await support.completeStageText(env, {
        prompt: buildWorkerWavePrompt({
          leaderPlan: input.leaderPlan,
          userPrompt: input.userPrompt,
        }),
        reasoningEffort: activeContext.conversation.agentWorkerReasoningEffort ?? 'low',
        runId: input.runId,
        serviceTier: activeContext.conversation.serviceTier ?? 'default',
        userId: input.userId,
      });
      if (!workerReport) {
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
  };
};
