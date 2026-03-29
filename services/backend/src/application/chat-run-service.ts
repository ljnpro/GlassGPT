import { createChatRunExecutionOperations } from './chat-run-execution-operations.js';
import { createChatRunQueueOperations } from './chat-run-queue-operations.js';
import type {
  ChatRunService,
  ChatRunServiceDependencies,
  ChatRunWorkflowParams,
} from './chat-run-types.js';

export const createChatRunService = (deps: ChatRunServiceDependencies): ChatRunService => {
  return {
    ...createChatRunQueueOperations(deps),
    ...createChatRunExecutionOperations(deps),
  };
};

export type { ChatRunService, ChatRunServiceDependencies, ChatRunWorkflowParams };
