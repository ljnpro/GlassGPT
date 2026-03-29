import type { AgentRunService } from '../application/agent-run-service.js';
import type { AuthService } from '../application/auth-service.js';
import type { ChatRunService } from '../application/chat-run-types.js';
import type { ConversationService } from '../application/conversation-service.js';
import type { CredentialService } from '../application/credential-service.js';
import type { RateLimitService } from '../application/rate-limit-service.js';
import type { RunService } from '../application/run-service.js';
import type { SyncService } from '../application/sync-service.js';

export type AuthenticatedBackendSession = Awaited<ReturnType<AuthService['resolveSession']>>;

export interface BackendServices {
  readonly agentRunService: AgentRunService;
  readonly authService: AuthService;
  readonly chatRunService: ChatRunService;
  readonly conversationService: ConversationService;
  readonly credentialService: CredentialService;
  readonly rateLimitService: RateLimitService;
  readonly runService: RunService;
  readonly syncService: SyncService;
}
