import { createAgentRunExecutionOperations } from './agent-run-execution-operations.js';
import { createAgentRunQueueOperations } from './agent-run-queue-operations.js';
import type {
  AgentRunService,
  AgentRunServiceDependencies,
  AgentRunWorkflowParams,
} from './agent-run-types.js';

export const createAgentRunService = (deps: AgentRunServiceDependencies): AgentRunService => {
  return {
    ...createAgentRunQueueOperations(deps),
    ...createAgentRunExecutionOperations(deps),
  };
};

export type { AgentRunService, AgentRunServiceDependencies, AgentRunWorkflowParams };
