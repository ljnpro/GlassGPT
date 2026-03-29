import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import {
  buildQueuedAgentProcessSnapshot,
  encodeAgentProcessSnapshot,
} from './agent-process-payloads.js';
import {
  createAgentRunSupport,
  requireAgentConversation,
  requireAgentRun,
} from './agent-run-support.js';
import type {
  AgentRunService,
  AgentRunServiceDependencies,
  AgentRunWorkflowParams,
} from './agent-run-types.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import { buildRunSummaryDTO } from './dto-mappers.js';
import { ApplicationError } from './errors.js';
import { createMessageId } from './ids.js';
import {
  createQueuedRunRecord,
  createRunEventDraft,
  formatFailureSummary,
  persistProjectedEvent,
  requireConversation,
  requireRun,
  type WorkflowStarter,
} from './run-projection.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const requireValidCredential = (
  credential: ProviderCredentialRecord | null,
): ProviderCredentialRecord => {
  if (!credential || credential.status !== 'valid') {
    throw new ApplicationError('forbidden', 'openai_credential_unavailable');
  }

  return credential;
};

const isTerminalRun = (run: RunRecord): boolean => {
  return run.status === 'completed' || run.status === 'failed' || run.status === 'cancelled';
};

type AgentRunQueueOperations = Pick<
  AgentRunService,
  'cancelRun' | 'getRun' | 'queueAgentRun' | 'retryRun'
>;

export const createAgentRunQueueOperations = (
  deps: AgentRunServiceDependencies,
): AgentRunQueueOperations => {
  const support = createAgentRunSupport(deps);

  const queueRunInternal = async (
    env: BackendRuntimeContext,
    workflow: WorkflowStarter<AgentRunWorkflowParams>,
    input: {
      readonly conversationId: string;
      readonly createUserMessage: boolean;
      readonly prompt: string;
      readonly userId: string;
    },
  ) => {
    const conversation = requireAgentConversation(
      requireConversation(
        await deps.findConversationByIdForUser(env, input.conversationId, input.userId),
      ),
    );
    requireValidCredential(await deps.findProviderCredential(env, input.userId, 'openai'));

    let projectedConversation = conversation;
    const queuedProcessSnapshot = buildQueuedAgentProcessSnapshot({
      now: deps.now(),
      userPrompt: input.prompt,
    });
    let run = createQueuedRunRecord(deps.now(), {
      conversationId: projectedConversation.id,
      kind: 'agent',
      stage: 'leader_planning',
      userId: input.userId,
      visibleSummary: 'Queued agent workflow',
    });
    run = {
      ...run,
      processSnapshotJSON: encodeAgentProcessSnapshot(queuedProcessSnapshot),
    };

    await deps.insertRun(env, run);

    if (input.createUserMessage) {
      const userMessage: MessageRecord = {
        agentTraceJSON: null,
        annotationsJSON: null,
        completedAt: run.createdAt,
        content: input.prompt,
        conversationId: projectedConversation.id,
        createdAt: run.createdAt,
        filePathAnnotationsJSON: null,
        id: createMessageId(),
        role: 'user',
        runId: run.id,
        serverCursor: null,
        thinking: null,
        toolCallsJSON: null,
      };
      await deps.insertMessage(env, userMessage);
      ({ conversation: projectedConversation, run } = await persistProjectedEvent(deps, env, {
        conversation: projectedConversation,
        event: createRunEventDraft(deps.now(), run, {
          kind: 'message_created',
          stage: 'leader_planning',
        }),
        message: userMessage,
        run,
        syncMessageCursor: true,
      }));
    }

    ({ conversation: projectedConversation, run } = await persistProjectedEvent(deps, env, {
      conversation: projectedConversation,
      event: createRunEventDraft(deps.now(), run, {
        kind: 'run_queued',
        progressLabel: 'Queued agent workflow',
        stage: 'leader_planning',
      }),
      message: null,
      run,
      syncMessageCursor: false,
    }));

    try {
      await workflow.create({
        id: run.id,
        params: {
          conversationId: projectedConversation.id,
          prompt: input.prompt,
          runId: run.id,
          userId: input.userId,
        },
      });
    } catch (error) {
      const failedRun: RunRecord = {
        ...run,
        status: 'failed',
        visibleSummary: formatFailureSummary(error),
      };
      ({ run } = await persistProjectedEvent(deps, env, {
        conversation: projectedConversation,
        event: createRunEventDraft(deps.now(), failedRun, {
          kind: 'run_failed',
          progressLabel: failedRun.visibleSummary,
          stage: failedRun.stage,
        }),
        message: null,
        run: failedRun,
        syncMessageCursor: false,
      }));
    }

    return buildRunSummaryDTO(run);
  };

  return {
    cancelRun: async (env, userId, runId) => {
      const run = requireAgentRun(requireRun(await deps.findRunByIdForUser(env, runId, userId)));
      if (isTerminalRun(run)) {
        return buildRunSummaryDTO(run);
      }

      const conversation = requireAgentConversation(
        requireConversation(
          await deps.findConversationByIdForUser(env, run.conversationId, userId),
        ),
      );
      const cancelledRun: RunRecord = {
        ...run,
        status: 'cancelled',
        visibleSummary: 'Agent run cancelled',
      };
      const result = await persistProjectedEvent(deps, env, {
        conversation,
        event: createRunEventDraft(deps.now(), cancelledRun, {
          kind: 'run_cancelled',
          stage: cancelledRun.stage,
        }),
        message: null,
        run: cancelledRun,
        syncMessageCursor: false,
      });
      return buildRunSummaryDTO(result.run);
    },

    getRun: async (env, userId, runId) => {
      const run = requireAgentRun(requireRun(await deps.findRunByIdForUser(env, runId, userId)));
      return buildRunSummaryDTO(run);
    },

    queueAgentRun: async (env, workflow, input) => {
      const promptSource = await support.resolvePromptSource(
        env,
        requireAgentConversation(
          requireConversation(
            await deps.findConversationByIdForUser(env, input.conversationId, input.userId),
          ),
        ),
        input.prompt,
      );
      return queueRunInternal(env, workflow, {
        conversationId: input.conversationId,
        createUserMessage: promptSource.createUserMessage,
        prompt: promptSource.prompt,
        userId: input.userId,
      });
    },

    retryRun: async (env, workflow, userId, runId) => {
      const run = requireAgentRun(requireRun(await deps.findRunByIdForUser(env, runId, userId)));
      const prompt = await support.resolveRetryPromptSource(env, run);
      return queueRunInternal(env, workflow, {
        conversationId: run.conversationId,
        createUserMessage: false,
        prompt,
        userId,
      });
    },
  };
};
