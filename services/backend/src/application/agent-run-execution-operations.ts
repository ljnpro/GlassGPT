import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import {
  buildFinalSynthesisPrompt,
  buildLeaderPlanningPrompt,
  buildLeaderReviewPrompt,
  buildWorkerWavePrompt,
} from './agent-prompts.js';
import { createAgentRunSupport } from './agent-run-support.js';
import type { AgentRunService, AgentRunServiceDependencies } from './agent-run-types.js';
import { createMessageId } from './ids.js';
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

      const assistantMessage: MessageRecord = {
        completedAt: deps.now().toISOString(),
        content: input.finalText,
        conversationId: activeContext.conversation.id,
        createdAt: deps.now().toISOString(),
        id: createMessageId(),
        role: 'assistant',
        runId: activeContext.run.id,
        serverCursor: null,
      };
      await deps.insertMessage(env, assistantMessage);

      const assistantDeltaResult = await persistProjectedEvent(deps, env, {
        conversation: activeContext.conversation,
        event: createRunEventDraft(deps.now(), activeContext.run, {
          kind: 'assistant_delta',
          stage: 'final_synthesis',
          textDelta: input.finalText,
        }),
        message: assistantMessage,
        run: activeContext.run,
        syncMessageCursor: true,
      });

      const assistantCompletedResult = await persistProjectedEvent(deps, env, {
        conversation: assistantDeltaResult.conversation,
        event: createRunEventDraft(deps.now(), assistantDeltaResult.run, {
          kind: 'assistant_completed',
          stage: 'final_synthesis',
        }),
        message: assistantDeltaResult.message,
        run: assistantDeltaResult.run,
        syncMessageCursor: false,
      });

      const completedRun: RunRecord = {
        ...assistantCompletedResult.run,
        status: 'completed',
        visibleSummary: truncateSummary(input.finalText),
      };
      await persistProjectedEvent(deps, env, {
        conversation: assistantCompletedResult.conversation,
        event: createRunEventDraft(deps.now(), completedRun, {
          kind: 'run_completed',
          stage: 'final_synthesis',
        }),
        message: assistantCompletedResult.message,
        run: completedRun,
        syncMessageCursor: false,
      });
    },

    executeFinalSynthesis: async (env, input) => {
      const finalText = await support.completeStageText(env, {
        prompt: buildFinalSynthesisPrompt({
          leaderPlan: input.leaderPlan,
          leaderReview: input.leaderReview,
          userPrompt: input.userPrompt,
          workerReport: input.workerReport,
        }),
        runId: input.runId,
        userId: input.userId,
      });
      if (!finalText) {
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

      await support.recordStageProgress(env, activeContext, {
        progressLabel: 'Final synthesis ready',
        stage: 'final_synthesis',
        visibleSummary: truncateSummary(finalText),
      });

      return finalText;
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

      const planningContext = await support.recordStageProgress(env, activeContext, {
        progressLabel: 'Leader plan ready',
        stage: 'leader_planning',
        visibleSummary: `Plan ready: ${truncateSummary(leaderPlan)}`,
      });
      await support.recordStageChange(env, planningContext, {
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

      const reviewContext = await support.recordStageProgress(env, activeContext, {
        progressLabel: 'Leader review ready',
        stage: 'leader_review',
        visibleSummary: `Review ready: ${truncateSummary(leaderReview)}`,
      });
      await support.recordStageChange(env, reviewContext, {
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

      const workerContext = await support.recordStageProgress(env, activeContext, {
        progressLabel: 'Worker findings ready',
        stage: 'worker_wave',
        visibleSummary: `Worker findings: ${truncateSummary(workerReport)}`,
      });
      await support.recordStageChange(env, workerContext, {
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

      const failedRun: RunRecord = {
        ...activeContext.run,
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

      const runningRun: RunRecord = {
        ...activeContext.run,
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
          progressLabel: 'Drafting execution plan',
          stage: 'leader_planning',
          visibleSummary: 'Drafting execution plan',
        },
      );
      return true;
    },
  };
};
