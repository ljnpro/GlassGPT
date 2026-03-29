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
import type { LiveCitation, LiveFilePathAnnotation } from './live-stream-model.js';
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

const mergeLiveCitations = (
  citations: readonly LiveCitation[],
  nextCitation: LiveCitation,
): LiveCitation[] => {
  if (
    citations.some(
      (candidate) =>
        candidate.url === nextCitation.url &&
        candidate.title === nextCitation.title &&
        candidate.startIndex === nextCitation.startIndex &&
        candidate.endIndex === nextCitation.endIndex,
    )
  ) {
    return [...citations];
  }

  return [...citations, nextCitation];
};

const mergeLiveFilePathAnnotations = (
  annotations: readonly LiveFilePathAnnotation[],
  nextAnnotation: LiveFilePathAnnotation,
): LiveFilePathAnnotation[] => {
  if (
    annotations.some(
      (candidate) =>
        candidate.fileId === nextAnnotation.fileId &&
        candidate.containerId === nextAnnotation.containerId &&
        candidate.sandboxPath === nextAnnotation.sandboxPath &&
        candidate.filename === nextAnnotation.filename &&
        candidate.startIndex === nextAnnotation.startIndex &&
        candidate.endIndex === nextAnnotation.endIndex,
    )
  ) {
    return [...annotations];
  }

  return [...annotations, nextAnnotation];
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
      readonly runId: string;
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

    for await (const event of deps.createStreamingResponse(apiKey, { input: input.prompt })) {
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
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'delta',
                data: {
                  runId: input.runId,
                  stage: activeContext.run.stage,
                  textDelta: event.textDelta,
                },
              });
            } catch {
              // Non-fatal
            }
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
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'thinking_delta',
                data: {
                  runId: input.runId,
                  stage: activeContext.run.stage,
                  thinkingDelta: event.thinkingDelta,
                },
              });
            } catch {
              // Non-fatal
            }
          }
          break;

        case 'thinking_finished':
          if (activeContext) {
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'thinking_done',
                data: { runId: input.runId, stage: activeContext.run.stage },
              });
            } catch {
              // Non-fatal
            }
          }
          break;

        case 'tool_call_updated':
          if (activeContext) {
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'tool_call_update',
                data: {
                  runId: input.runId,
                  stage: activeContext.run.stage,
                  toolCall: event.toolCall,
                },
              });
            } catch {
              // Non-fatal
            }
          }
          break;

        case 'citation_added':
          liveCitations = mergeLiveCitations(liveCitations, event.citation);
          if (activeContext) {
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'citations_update',
                data: {
                  citations: liveCitations,
                  runId: input.runId,
                  stage: activeContext.run.stage,
                },
              });
            } catch {
              // Non-fatal
            }
          }
          break;

        case 'file_path_annotation_added':
          liveFilePathAnnotations = mergeLiveFilePathAnnotations(
            liveFilePathAnnotations,
            event.annotation,
          );
          if (activeContext) {
            try {
              await deps.broadcastStreamDelta(env, activeContext.conversation.id, {
                type: 'file_path_annotations_update',
                data: {
                  filePathAnnotations: liveFilePathAnnotations,
                  runId: input.runId,
                  stage: activeContext.run.stage,
                },
              });
            } catch {
              // Non-fatal
            }
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
