import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import type { ChatExecutionContext, ChatRunServiceDependencies } from './chat-run-types.js';
import { ApplicationError } from './errors.js';
import type {
  StreamingConversationMessage,
  StreamingConversationRequest,
} from './live-stream-model.js';
import { requireConversation, requireRun } from './run-projection.js';
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
  return run.status === 'completed' || run.status === 'cancelled';
};

export const requireChatConversation = (conversation: ConversationRecord): ConversationRecord => {
  if (conversation.mode !== 'chat') {
    throw new ApplicationError('invalid_request', 'conversation_not_chat_mode');
  }

  return conversation;
};

export const requireChatRun = (run: RunRecord): RunRecord => {
  if (run.kind !== 'chat') {
    throw new ApplicationError('invalid_request', 'run_not_chat_kind');
  }

  return run;
};

const buildConversationInput = (
  history: readonly MessageRecord[],
  currentContent: string,
): string | StreamingConversationMessage[] => {
  const prior = history.filter(
    (message) =>
      (message.role === 'user' || message.role === 'assistant') && message.content.length > 0,
  );
  if (prior.length === 0) {
    return currentContent;
  }

  const messages: StreamingConversationMessage[] = prior.map((message) => ({
    content: message.content,
    role: message.role as 'user' | 'assistant',
  }));
  messages.push({ content: currentContent, role: 'user' });
  return messages;
};

export const buildChatExecutionRequest = (
  conversation: ConversationRecord,
  input: string,
  conversationHistory: readonly MessageRecord[],
): StreamingConversationRequest => {
  return {
    input: buildConversationInput(conversationHistory, input),
    model: conversation.model ?? 'gpt-5.4',
    reasoningEffort: conversation.reasoningEffort ?? 'medium',
    serviceTier: conversation.serviceTier ?? 'default',
  };
};

export const createChatRunSupport = (deps: ChatRunServiceDependencies) => {
  const loadExecutionContext = async (
    env: BackendRuntimeContext,
    runId: string,
    userId: string,
  ): Promise<ChatExecutionContext> => {
    const run = requireChatRun(requireRun(await deps.findRunById(env, runId)));
    const conversation = requireChatConversation(
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
  ): Promise<ChatExecutionContext | null> => {
    const context = await loadExecutionContext(env, runId, userId);
    return isTerminalRun(context.run) ? null : context;
  };

  const assertCredentialAvailable = async (
    env: BackendRuntimeContext,
    userId: string,
  ): Promise<void> => {
    requireValidCredential(await deps.findProviderCredential(env, userId, 'openai'));
  };

  const loadApiKey = async (env: BackendRuntimeContext, userId: string): Promise<string> => {
    const credential = requireValidCredential(
      await deps.findProviderCredential(env, userId, 'openai'),
    );
    return deps.decryptSecret(env, credential);
  };

  return {
    assertCredentialAvailable,
    loadActiveExecutionContext,
    loadApiKey,
    loadExecutionContext,
  };
};

export type ChatRunSupport = ReturnType<typeof createChatRunSupport>;
