import { WorkflowEntrypoint, type WorkflowEvent, type WorkflowStep } from 'cloudflare:workers';

import { createBackendServices } from '../adapters/create-backend-services.js';
import type { AgentRunWorkflowParams } from '../application/agent-run-service.js';
import type { BackendRuntimeContext } from '../application/runtime-context.js';
import { logInfo } from '../observability/logger.js';

interface AgentRunWorkflowResult {
  readonly finalStage: 'final_synthesis';
  readonly runId: string;
}

const terminalRunStatuses = new Set(['cancelled', 'completed', 'failed']);

export class AgentRunWorkflow extends WorkflowEntrypoint<Env, AgentRunWorkflowParams> {
  override async run(
    event: Readonly<WorkflowEvent<AgentRunWorkflowParams>>,
    step: WorkflowStep,
  ): Promise<AgentRunWorkflowResult> {
    logInfo('agent_run_workflow_started', {
      runId: event.payload.runId,
      workflowInstanceId: event.instanceId,
    });

    const services = createBackendServices();
    const env = this.env as unknown as BackendRuntimeContext;
    const ensureTerminalShortCircuit = async (): Promise<AgentRunWorkflowResult> => {
      const run = await services.agentRunService.getRun(
        env,
        event.payload.userId,
        event.payload.runId,
      );
      if (!terminalRunStatuses.has(run.status)) {
        throw new Error('agent_run_workflow_short_circuit_without_terminal_state');
      }

      return {
        finalStage: 'final_synthesis',
        runId: event.payload.runId,
      };
    };

    try {
      const started = await step.do('start-run', async () => {
        return services.agentRunService.startQueuedRun(env, {
          runId: event.payload.runId,
          userId: event.payload.userId,
        });
      });
      if (!started) {
        return ensureTerminalShortCircuit();
      }

      const leaderPlan = await step.do('leader-planning', async () => {
        return services.agentRunService.executeLeaderPlanning(env, {
          prompt: event.payload.prompt,
          runId: event.payload.runId,
          userId: event.payload.userId,
        });
      });
      if (!leaderPlan) {
        return ensureTerminalShortCircuit();
      }

      const workerReport = await step.do('worker-wave', async () => {
        return services.agentRunService.executeWorkerWave(env, {
          leaderPlan,
          runId: event.payload.runId,
          userId: event.payload.userId,
          userPrompt: event.payload.prompt,
        });
      });
      if (!workerReport) {
        return ensureTerminalShortCircuit();
      }

      const leaderReview = await step.do('leader-review', async () => {
        return services.agentRunService.executeLeaderReview(env, {
          leaderPlan,
          runId: event.payload.runId,
          userId: event.payload.userId,
          userPrompt: event.payload.prompt,
          workerReport,
        });
      });
      if (!leaderReview) {
        return ensureTerminalShortCircuit();
      }

      const finalText = await step.do('final-synthesis', async () => {
        return services.agentRunService.executeFinalSynthesis(env, {
          leaderPlan,
          leaderReview,
          runId: event.payload.runId,
          userId: event.payload.userId,
          userPrompt: event.payload.prompt,
          workerReport,
        });
      });
      if (!finalText) {
        return ensureTerminalShortCircuit();
      }

      await step.do('complete-run', async () => {
        await services.agentRunService.completeRun(env, {
          finalText,
          runId: event.payload.runId,
          userId: event.payload.userId,
        });
      });
    } catch (error) {
      await services.agentRunService.failRun(env, {
        error,
        runId: event.payload.runId,
        userId: event.payload.userId,
      });
      throw error;
    }

    return {
      finalStage: 'final_synthesis',
      runId: event.payload.runId,
    };
  }
}
