import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type {
  AgentExecutionContext,
  AgentRunServiceDependencies,
  PromptSource,
} from './agent-run-types.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import { ApplicationError } from './errors.js';
import {
  createRunEventDraft,
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

export const requireAgentConversation = (conversation: ConversationRecord): ConversationRecord => {
  if (conversation.mode !== 'agent') {
    throw new ApplicationError('invalid_request', 'conversation_not_agent_mode');
  }

  return conversation;
};

export const requireAgentRun = (run: RunRecord): RunRecord => {
  if (run.kind !== 'agent') {
    throw new ApplicationError('invalid_request', 'run_not_agent_kind');
  }

  return run;
};

const isTerminalRun = (run: RunRecord): boolean => {
  return run.status === 'completed' || run.status === 'failed' || run.status === 'cancelled';
};

const normalizePrompt = (prompt: string | undefined): string | null => {
  const trimmed = prompt?.trim() ?? '';
  return trimmed.length > 0 ? trimmed : null;
};

const compareMessages = (left: MessageRecord, right: MessageRecord): number => {
  if (left.createdAt !== right.createdAt) {
    return left.createdAt.localeCompare(right.createdAt);
  }

  return left.id.localeCompare(right.id);
};

export const createAgentRunSupport = (deps: AgentRunServiceDependencies) => {
  const loadExecutionContext = async (
    env: BackendRuntimeContext,
    runId: string,
    userId: string,
  ): Promise<AgentExecutionContext> => {
    const run = requireAgentRun(requireRun(await deps.findRunById(env, runId)));
    const conversation = requireAgentConversation(
      requireConversation(await deps.findConversationByIdForUser(env, run.conversationId, userId)),
    );
    return {
      conversation,
      run,
    };
  };

  const loadActiveExecutionContext = async (
    env: BackendRuntimeContext,
    runId: string,
    userId: string,
  ): Promise<AgentExecutionContext | null> => {
    const context = await loadExecutionContext(env, runId, userId);
    return isTerminalRun(context.run) ? null : context;
  };

  const loadApiKey = async (env: BackendRuntimeContext, userId: string): Promise<string> => {
    const credential = requireValidCredential(
      await deps.findProviderCredential(env, userId, 'openai'),
    );
    return deps.decryptSecret(env, credential);
  };

  const assertCredentialAvailable = async (
    env: BackendRuntimeContext,
    userId: string,
  ): Promise<void> => {
    requireValidCredential(await deps.findProviderCredential(env, userId, 'openai'));
  };

  const resolvePromptSource = async (
    env: BackendRuntimeContext,
    conversation: ConversationRecord,
    prompt: string | undefined,
  ): Promise<PromptSource> => {
    const explicitPrompt = normalizePrompt(prompt);
    if (explicitPrompt) {
      return {
        createUserMessage: true,
        prompt: explicitPrompt,
      };
    }

    const messages = await deps.listMessagesForConversation(env, conversation.id);
    const latestUserMessage = [...messages]
      .filter((message) => message.role === 'user')
      .sort(compareMessages)
      .at(-1);
    if (!latestUserMessage) {
      throw new ApplicationError('invalid_request', 'agent_prompt_missing');
    }

    return {
      createUserMessage: false,
      prompt: latestUserMessage.content,
    };
  };

  const resolveRetryPromptSource = async (
    env: BackendRuntimeContext,
    run: RunRecord,
  ): Promise<string> => {
    const directSourceMessage = await deps.findUserMessageByRunId(env, run.id);
    if (directSourceMessage) {
      return directSourceMessage.content;
    }

    const messages = await deps.listMessagesForConversation(env, run.conversationId);
    const retrySource = [...messages]
      .filter((message) => message.role === 'user' && message.createdAt <= run.createdAt)
      .sort(compareMessages)
      .at(-1);
    if (!retrySource) {
      throw new ApplicationError('invalid_request', 'retry_source_message_missing');
    }

    return retrySource.content;
  };

  const recordStageProgress = async (
    env: BackendRuntimeContext,
    context: AgentExecutionContext,
    input: {
      readonly progressLabel: string;
      readonly stage: RunRecord['stage'];
      readonly visibleSummary: string;
    },
  ): Promise<AgentExecutionContext> => {
    const nextRun: RunRecord = {
      ...context.run,
      stage: input.stage,
      status: 'running',
      visibleSummary: input.visibleSummary,
    };
    const result = await persistProjectedEvent(deps, env, {
      conversation: context.conversation,
      event: createRunEventDraft(deps.now(), nextRun, {
        kind: 'run_progress',
        progressLabel: input.progressLabel,
        stage: input.stage,
      }),
      message: null,
      run: nextRun,
      syncMessageCursor: false,
    });
    return {
      conversation: result.conversation,
      run: result.run,
    };
  };

  const recordStageChange = async (
    env: BackendRuntimeContext,
    context: AgentExecutionContext,
    input: {
      readonly progressLabel: string;
      readonly stage: RunRecord['stage'];
      readonly visibleSummary: string;
    },
  ): Promise<AgentExecutionContext> => {
    const nextRun: RunRecord = {
      ...context.run,
      stage: input.stage,
      status: 'running',
      visibleSummary: input.visibleSummary,
    };
    const result = await persistProjectedEvent(deps, env, {
      conversation: context.conversation,
      event: createRunEventDraft(deps.now(), nextRun, {
        kind: 'stage_changed',
        progressLabel: input.progressLabel,
        stage: input.stage,
      }),
      message: null,
      run: nextRun,
      syncMessageCursor: false,
    });
    return {
      conversation: result.conversation,
      run: result.run,
    };
  };

  const completeStageText = async (
    env: BackendRuntimeContext,
    input: {
      readonly prompt: string;
      readonly runId: string;
      readonly userId: string;
    },
  ): Promise<string | null> => {
    let activeContext = await loadActiveExecutionContext(env, input.runId, input.userId);
    if (!activeContext) {
      return null;
    }

    const apiKey = await loadApiKey(env, input.userId);
    const chunks: string[] = [];
    let pendingDelta = '';
    let chunkCount = 0;
    const DELTA_FLUSH_THRESHOLD = 5;

    for await (const delta of deps.createStreamingChatCompletion(apiKey, input.prompt)) {
      // Check for cancellation periodically
      if (chunkCount % 20 === 0) {
        const latestRun = await deps.findRunById(env, input.runId);
        if (latestRun?.status === 'cancelled') {
          return null;
        }
      }

      chunks.push(delta);
      pendingDelta += delta;
      chunkCount++;

      // Broadcast every token directly to SSE clients (bypasses D1)
      if (activeContext) {
        try {
          await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
            type: 'delta',
            data: { textDelta: delta, runId: input.runId, stage: activeContext.run.stage },
          });
        } catch {
          // Non-fatal
        }
      }

      // Persist to D1 less frequently (for catch-up and history)
      if (chunkCount % DELTA_FLUSH_THRESHOLD === 0 && activeContext) {
        const result = await persistProjectedEvent(deps, env, {
          conversation: activeContext.conversation,
          event: createRunEventDraft(deps.now(), activeContext.run, {
            kind: 'assistant_delta',
            textDelta: pendingDelta,
            stage: activeContext.run.stage,
          }),
          message: null,
          run: activeContext.run,
          syncMessageCursor: false,
        });
        activeContext = { conversation: result.conversation, run: result.run };
        pendingDelta = '';
      }
    }

    // Flush remaining delta
    if (pendingDelta.length > 0 && activeContext) {
      const result = await persistProjectedEvent(deps, env, {
        conversation: activeContext.conversation,
        event: createRunEventDraft(deps.now(), activeContext.run, {
          kind: 'assistant_delta',
          textDelta: pendingDelta,
          stage: activeContext.run.stage,
        }),
        message: null,
        run: activeContext.run,
        syncMessageCursor: false,
      });
      activeContext = { conversation: result.conversation, run: result.run };
    }

    return chunks.join('') || null;
  };

  return {
    assertCredentialAvailable,
    completeStageText,
    loadActiveExecutionContext,
    loadExecutionContext,
    recordStageChange,
    recordStageProgress,
    resolvePromptSource,
    resolveRetryPromptSource,
  };
};

export type AgentRunSupport = ReturnType<typeof createAgentRunSupport>;
export type { WorkflowStarter };
