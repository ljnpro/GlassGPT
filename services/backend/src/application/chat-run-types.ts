import type { RunSummaryDTO } from '@glassgpt/backend-contracts';

import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import type { LiveStreamEvent, StreamingConversationRequest } from './live-stream-model.js';
import type { RunProjectionDependencies, WorkflowStarter } from './run-projection.js';
import type { BackendRuntimeContext } from './runtime-context.js';

export interface ChatRunWorkflowParams {
  readonly runId: string;
  readonly conversationId: string;
  readonly userId: string;
  readonly content: string;
}

export interface ChatRunServiceDependencies extends RunProjectionDependencies {
  readonly createChatCompletion: (apiKey: string, input: string) => Promise<string>;
  readonly createStreamingResponse: (
    apiKey: string,
    request: StreamingConversationRequest,
  ) => AsyncGenerator<LiveStreamEvent, void, undefined>;
  readonly createStreamingChatCompletion: (
    apiKey: string,
    input: string,
  ) => AsyncGenerator<string, void, undefined>;
  readonly decryptSecret: (
    env: BackendRuntimeContext,
    encrypted: {
      readonly ciphertext: string;
      readonly keyVersion: string;
      readonly nonce: string;
    },
  ) => Promise<string>;
  readonly findConversationByIdForUser: (
    env: BackendRuntimeContext,
    conversationId: string,
    userId: string,
  ) => Promise<ConversationRecord | null>;
  readonly findProviderCredential: (
    env: BackendRuntimeContext,
    userId: string,
    provider: 'openai',
  ) => Promise<ProviderCredentialRecord | null>;
  readonly findAssistantMessageByRunId: (
    env: BackendRuntimeContext,
    runId: string,
  ) => Promise<MessageRecord | null>;
  readonly listMessagesForConversation: (
    env: BackendRuntimeContext,
    conversationId: string,
  ) => Promise<MessageRecord[]>;
  readonly findRunById: (env: BackendRuntimeContext, runId: string) => Promise<RunRecord | null>;
  readonly findRunByIdForUser: (
    env: BackendRuntimeContext,
    runId: string,
    userId: string,
  ) => Promise<RunRecord | null>;
  readonly findUserMessageByRunId: (
    env: BackendRuntimeContext,
    runId: string,
  ) => Promise<MessageRecord | null>;
  readonly insertMessage: (env: BackendRuntimeContext, message: MessageRecord) => Promise<void>;
  readonly insertRun: (env: BackendRuntimeContext, run: RunRecord) => Promise<void>;
  readonly now: () => Date;
}

export interface ChatRunService {
  cancelRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  executeQueuedRun(env: BackendRuntimeContext, input: ChatRunWorkflowParams): Promise<void>;
  getRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  queueChatRun(
    env: BackendRuntimeContext,
    workflow: WorkflowStarter<ChatRunWorkflowParams>,
    input: {
      readonly content: string;
      readonly conversationId: string;
      readonly userId: string;
    },
  ): Promise<RunSummaryDTO>;
  retryRun(
    env: BackendRuntimeContext,
    workflow: WorkflowStarter<ChatRunWorkflowParams>,
    userId: string,
    runId: string,
  ): Promise<RunSummaryDTO>;
}

export interface ChatExecutionContext {
  readonly conversation: ConversationRecord;
  readonly run: RunRecord;
}
