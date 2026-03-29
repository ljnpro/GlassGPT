import { WorkflowEntrypoint, type WorkflowEvent, type WorkflowStep } from 'cloudflare:workers';
import { createBackendServices } from '../adapters/create-backend-services.js';
import type { ChatRunWorkflowParams } from '../application/chat-run-types.js';
import type { BackendRuntimeContext } from '../application/runtime-context.js';
import { logInfo } from '../observability/logger.js';

interface ChatRunWorkflowResult {
  readonly runId: string;
  readonly completedAt: string;
}

export class ChatRunWorkflow extends WorkflowEntrypoint<Env, ChatRunWorkflowParams> {
  override async run(
    event: Readonly<WorkflowEvent<ChatRunWorkflowParams>>,
    _step: WorkflowStep,
  ): Promise<ChatRunWorkflowResult> {
    logInfo('chat_run_workflow_started', {
      runId: event.payload.runId,
      workflowInstanceId: event.instanceId,
    });

    const services = createBackendServices();
    await services.chatRunService.executeQueuedRun(
      this.env as unknown as BackendRuntimeContext,
      event.payload,
    );

    return {
      completedAt: new Date().toISOString(),
      runId: event.payload.runId,
    };
  }
}
