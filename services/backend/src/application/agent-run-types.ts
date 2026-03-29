import type { RunSummaryDTO } from '@glassgpt/backend-contracts';

import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import type { LiveStreamEvent, StreamingConversationRequest } from './live-stream-model.js';
import type { RunProjectionDependencies, WorkflowStarter } from './run-projection.js';
import type { BackendRuntimeContext } from './runtime-context.js';

export interface AgentRunWorkflowParams {
  readonly conversationId: string;
  readonly prompt: string;
  readonly runId: string;
  readonly userId: string;
}

export interface AgentRunServiceDependencies extends RunProjectionDependencies {
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
  readonly listMessagesForConversation: (
    env: BackendRuntimeContext,
    conversationId: string,
  ) => Promise<MessageRecord[]>;
  readonly now: () => Date;
}

export interface AgentRunService {
  cancelRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  completeRun(
    env: BackendRuntimeContext,
    input: {
      readonly finalText: string;
      readonly runId: string;
      readonly userId: string;
    },
  ): Promise<void>;
  executeFinalSynthesis(
    env: BackendRuntimeContext,
    input: {
      readonly leaderPlan: string;
      readonly leaderReview: string;
      readonly runId: string;
      readonly userId: string;
      readonly userPrompt: string;
      readonly workerReport: string;
    },
  ): Promise<string | null>;
  executeLeaderPlanning(
    env: BackendRuntimeContext,
    input: {
      readonly prompt: string;
      readonly runId: string;
      readonly userId: string;
    },
  ): Promise<string | null>;
  executeLeaderReview(
    env: BackendRuntimeContext,
    input: {
      readonly leaderPlan: string;
      readonly runId: string;
      readonly userId: string;
      readonly userPrompt: string;
      readonly workerReport: string;
    },
  ): Promise<string | null>;
  executeWorkerWave(
    env: BackendRuntimeContext,
    input: {
      readonly leaderPlan: string;
      readonly runId: string;
      readonly userId: string;
      readonly userPrompt: string;
    },
  ): Promise<string | null>;
  failRun(
    env: BackendRuntimeContext,
    input: {
      readonly error: unknown;
      readonly runId: string;
      readonly userId: string;
    },
  ): Promise<void>;
  getRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  queueAgentRun(
    env: BackendRuntimeContext,
    workflow: WorkflowStarter<AgentRunWorkflowParams>,
    input: {
      readonly conversationId: string;
      readonly prompt?: string;
      readonly userId: string;
    },
  ): Promise<RunSummaryDTO>;
  retryRun(
    env: BackendRuntimeContext,
    workflow: WorkflowStarter<AgentRunWorkflowParams>,
    userId: string,
    runId: string,
  ): Promise<RunSummaryDTO>;
  startQueuedRun(
    env: BackendRuntimeContext,
    input: { readonly runId: string; readonly userId: string },
  ): Promise<boolean>;
}

export interface AgentExecutionContext {
  readonly conversation: ConversationRecord;
  readonly run: RunRecord;
}

export interface PromptSource {
  readonly createUserMessage: boolean;
  readonly prompt: string;
}
