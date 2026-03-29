import type { RunSummaryDTO } from '@glassgpt/backend-contracts';
import type { RunRecord } from '../domain/run-model.js';
import type { AgentRunService, AgentRunWorkflowParams } from './agent-run-service.js';
import type { ChatRunService, ChatRunWorkflowParams } from './chat-run-types.js';
import { buildRunSummaryDTO } from './dto-mappers.js';
import { requireRun, type WorkflowStarter } from './run-projection.js';
import type { BackendRuntimeContext } from './runtime-context.js';

export interface RunServiceDependencies {
  readonly agentRunService: Pick<AgentRunService, 'cancelRun' | 'retryRun'>;
  readonly chatRunService: Pick<ChatRunService, 'cancelRun' | 'retryRun'>;
  readonly findRunByIdForUser: (
    env: BackendRuntimeContext,
    runId: string,
    userId: string,
  ) => Promise<RunRecord | null>;
}

export interface RunService {
  cancelRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  getRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  retryRun(
    env: BackendRuntimeContext,
    workflows: {
      readonly agent: WorkflowStarter<AgentRunWorkflowParams>;
      readonly chat: WorkflowStarter<ChatRunWorkflowParams>;
    },
    userId: string,
    runId: string,
  ): Promise<RunSummaryDTO>;
}

export const createRunService = (deps: RunServiceDependencies): RunService => {
  return {
    cancelRun: async (env, userId, runId) => {
      const run = requireRun(await deps.findRunByIdForUser(env, runId, userId));
      return run.kind === 'chat'
        ? deps.chatRunService.cancelRun(env, userId, runId)
        : deps.agentRunService.cancelRun(env, userId, runId);
    },

    getRun: async (env, userId, runId) => {
      const run = requireRun(await deps.findRunByIdForUser(env, runId, userId));
      return buildRunSummaryDTO(run);
    },

    retryRun: async (env, workflows, userId, runId) => {
      const run = requireRun(await deps.findRunByIdForUser(env, runId, userId));
      return run.kind === 'chat'
        ? deps.chatRunService.retryRun(env, workflows.chat, userId, runId)
        : deps.agentRunService.retryRun(env, workflows.agent, userId, runId);
    },
  };
};
