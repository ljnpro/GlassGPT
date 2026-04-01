import type { ConversationRecord } from '../domain/conversation-model.js';
import type { RunRecord } from '../domain/run-model.js';
import { logError, sanitizeLogValue } from '../observability/logger.js';
import type {
  AgentExecutionContext,
  AgentRunServiceDependencies,
  PromptSource,
} from './agent-run-types.js';
import {
  compareMessages,
  isTerminalRun,
  mergeLiveCitations,
  mergeLiveFilePathAnnotations,
  normalizePrompt,
  requireValidCredential,
} from './agent-run-utilities.js';
import { ApplicationError } from './errors.js';
import type { LiveCitation, LiveFilePathAnnotation } from './live-stream-model.js';
import {
  createRunEventDraft,
  persistProjectedEvent,
  requireConversation,
  requireRun,
  type WorkflowStarter,
} from './run-projection.js';
import type { BackendRuntimeContext } from './runtime-context.js';

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
      readonly processSnapshotJSON?: string | null;
      readonly progressLabel: string;
      readonly stage: RunRecord['stage'];
      readonly visibleSummary: string;
    },
  ): Promise<AgentExecutionContext> => {
    const nextRun: RunRecord = {
      ...context.run,
      processSnapshotJSON: input.processSnapshotJSON ?? context.run.processSnapshotJSON,
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
      readonly processSnapshotJSON?: string | null;
      readonly progressLabel: string;
      readonly stage: RunRecord['stage'];
      readonly visibleSummary: string;
    },
  ): Promise<AgentExecutionContext> => {
    const nextRun: RunRecord = {
      ...context.run,
      processSnapshotJSON: input.processSnapshotJSON ?? context.run.processSnapshotJSON,
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
      readonly reasoningEffort: 'none' | 'low' | 'medium' | 'high' | 'xhigh';
      readonly runId: string;
      readonly serviceTier: 'default' | 'flex';
      readonly userId: string;
    },
  ): Promise<string | null> => {
    let activeContext = await loadActiveExecutionContext(env, input.runId, input.userId);
    if (!activeContext) {
      return null;
    }

    const apiKey = await loadApiKey(env, input.userId);
    let outputText = '';
    let pendingDelta = '';
    let chunkCount = 0;
    let liveCitations: LiveCitation[] = [];
    let liveFilePathAnnotations: LiveFilePathAnnotation[] = [];
    const DELTA_FLUSH_THRESHOLD = 5;
    const broadcastNonFatalDelta = async (
      delta: Parameters<AgentRunServiceDependencies['broadcastStreamDelta']>[2],
    ): Promise<void> => {
      if (!activeContext) {
        return;
      }

      try {
        await deps.broadcastStreamDelta(env, activeContext.conversation.id, delta);
      } catch (error) {
        logError('agent_stream_broadcast_failed', {
          conversationId: activeContext.conversation.id,
          errorMessage: error instanceof Error ? sanitizeLogValue(error.message) : 'unknown_error',
          runId: input.runId,
          stage: activeContext.run.stage ?? 'unknown',
          type: delta.type,
        });
      }
    };

    for await (const event of deps.createStreamingResponse(apiKey, {
      input: input.prompt,
      reasoningEffort: input.reasoningEffort,
      serviceTier: input.serviceTier,
    })) {
      // Check for cancellation periodically
      if (chunkCount % 20 === 0) {
        const latestRun = await deps.findRunById(env, input.runId);
        if (latestRun?.status === 'cancelled') {
          return null;
        }
      }

      switch (event.kind) {
        case 'text_delta':
          outputText += event.textDelta;
          pendingDelta += event.textDelta;
          chunkCount += 1;

          if (activeContext) {
            await broadcastNonFatalDelta({
              type: 'delta',
              data: {
                runId: input.runId,
                stage: activeContext.run.stage,
                textDelta: event.textDelta,
              },
            });
          }

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
          break;

        case 'thinking_delta':
          if (activeContext) {
            await broadcastNonFatalDelta({
              type: 'thinking_delta',
              data: {
                runId: input.runId,
                stage: activeContext.run.stage,
                thinkingDelta: event.thinkingDelta,
              },
            });
          }
          break;

        case 'thinking_finished':
          if (activeContext) {
            await broadcastNonFatalDelta({
              type: 'thinking_done',
              data: { runId: input.runId, stage: activeContext.run.stage },
            });
          }
          break;

        case 'tool_call_updated':
          if (activeContext) {
            await broadcastNonFatalDelta({
              type: 'tool_call_update',
              data: {
                runId: input.runId,
                stage: activeContext.run.stage,
                toolCall: event.toolCall,
              },
            });
          }
          break;

        case 'citation_added':
          liveCitations = mergeLiveCitations(liveCitations, event.citation);
          if (activeContext) {
            await broadcastNonFatalDelta({
              type: 'citations_update',
              data: {
                citations: liveCitations,
                runId: input.runId,
                stage: activeContext.run.stage,
              },
            });
          }
          break;

        case 'file_path_annotation_added':
          liveFilePathAnnotations = mergeLiveFilePathAnnotations(
            liveFilePathAnnotations,
            event.annotation,
          );
          if (activeContext) {
            await broadcastNonFatalDelta({
              type: 'file_path_annotations_update',
              data: {
                filePathAnnotations: liveFilePathAnnotations,
                runId: input.runId,
                stage: activeContext.run.stage,
              },
            });
          }
          break;

        case 'completed':
          outputText = event.outputText;
          break;

        case 'incomplete':
          throw new Error(event.errorMessage ?? 'openai_response_incomplete');

        case 'failed':
          throw new Error(event.errorMessage);

        case 'response_created':
          break;
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

    return outputText || null;
  };

  return {
    assertCredentialAvailable,
    completeStageText,
    loadActiveExecutionContext,
    loadApiKey,
    loadExecutionContext,
    recordStageChange,
    recordStageProgress,
    resolvePromptSource,
    resolveRetryPromptSource,
  };
};

export type AgentRunSupport = ReturnType<typeof createAgentRunSupport>;
export type { WorkflowStarter };
