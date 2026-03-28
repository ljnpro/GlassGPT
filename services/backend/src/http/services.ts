import type {
  AppleAuthRequestDTO,
  ConversationDetailDTO,
  ConversationDTO,
  CreateConversationRequestDTO,
  CredentialStatusDTO,
  RefreshSessionRequestDTO,
  RunSummaryDTO,
  SessionDTO,
  SyncEnvelopeDTO,
  UserDTO,
} from '@glassgpt/backend-contracts';
import type { AgentRunService, AgentRunWorkflowParams } from '../application/agent-run-service.js';
import type { ChatRunWorkflowParams } from '../application/chat-run-service.js';
import type { WorkflowStarter } from '../application/run-projection.js';
import type { BackendRuntimeContext } from '../application/runtime-context.js';

export interface AuthenticatedBackendSession {
  readonly sessionId: string;
  readonly userId: string;
  readonly deviceId: string;
  readonly user: UserDTO;
}

export interface AuthService {
  authenticateWithApple(
    env: BackendRuntimeContext,
    input: AppleAuthRequestDTO,
  ): Promise<SessionDTO>;
  fetchCurrentUser(env: BackendRuntimeContext, accessToken: string): Promise<UserDTO>;
  logout(env: BackendRuntimeContext, accessToken: string): Promise<void>;
  refreshSession(env: BackendRuntimeContext, input: RefreshSessionRequestDTO): Promise<SessionDTO>;
  resolveSession(
    env: BackendRuntimeContext,
    accessToken: string,
  ): Promise<AuthenticatedBackendSession>;
}

export interface CredentialService {
  deleteOpenAiKey(env: BackendRuntimeContext, userId: string): Promise<void>;
  readOpenAiKeyStatus(env: BackendRuntimeContext, userId: string): Promise<CredentialStatusDTO>;
  storeOpenAiKey(
    env: BackendRuntimeContext,
    userId: string,
    apiKey: string,
  ): Promise<CredentialStatusDTO>;
}

export interface ConversationService {
  createConversation(
    env: BackendRuntimeContext,
    userId: string,
    input: CreateConversationRequestDTO,
  ): Promise<ConversationDTO>;
  getConversationDetail(
    env: BackendRuntimeContext,
    userId: string,
    conversationId: string,
  ): Promise<ConversationDetailDTO>;
  listConversations(env: BackendRuntimeContext, userId: string): Promise<ConversationDTO[]>;
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

export interface RunService {
  cancelRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  getRun(env: BackendRuntimeContext, userId: string, runId: string): Promise<RunSummaryDTO>;
  retryRun(
    env: BackendRuntimeContext,
    workflows: {
      readonly agent: WorkflowStarter<AgentRunWorkflowParams>;
      readonly chat: WorkflowStarter<ChatRunWorkflowParams>;
    },
    userId: string,
    runId: string,
  ): Promise<RunSummaryDTO>;
}

export interface SyncService {
  syncEvents(
    env: BackendRuntimeContext,
    userId: string,
    afterCursor: string | null,
  ): Promise<SyncEnvelopeDTO>;
}

export interface BackendServices {
  readonly agentRunService: AgentRunService;
  readonly authService: AuthService;
  readonly chatRunService: ChatRunService;
  readonly conversationService: ConversationService;
  readonly credentialService: CredentialService;
  readonly runService: RunService;
  readonly syncService: SyncService;
}
