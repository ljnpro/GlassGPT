import { createAgentRunService } from '../application/agent-run-service.js';
import { createAuthService } from '../application/auth-service.js';
import { createChatRunService } from '../application/chat-run-service.js';
import { createConversationService } from '../application/conversation-service.js';
import { createCredentialService } from '../application/credential-service.js';
import { createRunService } from '../application/run-service.js';
import { createSyncService } from '../application/sync-service.js';
import { validateOpenAiApiKey } from './openai/openai-client.js';
import {
  createChatCompletion,
  createStreamingChatCompletion,
  createStreamingResponse,
} from './openai/openai-responses.js';
import {
  findConversationByIdForUser,
  insertConversation,
  listConversationsForUser,
  updateConversationPointers,
} from './persistence/conversation-repository.js';
import {
  findAssistantMessageByRunId,
  findUserMessageByRunId,
  insertMessage,
  listMessagesForConversation,
  updateMessage,
} from './persistence/message-repository.js';
import {
  deleteProviderCredential,
  findProviderCredential,
  upsertProviderCredential,
} from './persistence/provider-credential-repository.js';
import {
  insertRunEvent,
  listRunEventsForUser,
  updateRunEventSnapshots,
} from './persistence/run-event-repository.js';
import {
  findRunById,
  findRunByIdForUser,
  insertRun,
  listRunsForConversation,
  updateRun,
} from './persistence/run-repository.js';
import {
  findSessionById,
  findSessionByRefreshTokenHash,
  insertSession,
  revokeSession,
  rotateSessionRefreshToken,
} from './persistence/session-repository.js';
import { findUserById, upsertAppleUser } from './persistence/user-repository.js';
import {
  broadcastStreamDelta,
  publishConversationCursor,
} from './realtime/conversation-event-hub.js';
import { issueAccessToken, verifyAccessToken } from './security/access-token-codec.js';
import { verifyAppleIdentityToken } from './security/apple-identity-verifier.js';
import { decryptSecret, encryptSecret } from './security/credential-encryption.js';
import { hashRefreshToken, issueRefreshToken } from './security/refresh-token-crypto.js';

export const createBackendServices = () => {
  const chatRunService = createChatRunService({
    broadcastStreamDelta,
    createChatCompletion,
    createStreamingResponse,
    createStreamingChatCompletion,
    decryptSecret,
    findConversationByIdForUser,
    findAssistantMessageByRunId,
    findProviderCredential,
    findRunById,
    findRunByIdForUser,
    findUserMessageByRunId,
    insertMessage,
    insertRun,
    insertRunEvent,
    now: () => new Date(),
    publishConversationCursor,
    updateMessage,
    updateRunEventSnapshots,
    updateConversationPointers,
    updateRun,
  });

  const agentRunService = createAgentRunService({
    broadcastStreamDelta,
    createChatCompletion,
    createStreamingResponse,
    createStreamingChatCompletion,
    decryptSecret,
    findConversationByIdForUser,
    findAssistantMessageByRunId,
    findProviderCredential,
    findRunById,
    findRunByIdForUser,
    findUserMessageByRunId,
    insertMessage,
    insertRun,
    insertRunEvent,
    listMessagesForConversation,
    now: () => new Date(),
    publishConversationCursor,
    updateMessage,
    updateRunEventSnapshots,
    updateConversationPointers,
    updateRun,
  });

  const runService = createRunService({
    agentRunService,
    chatRunService,
    findRunByIdForUser,
  });

  return {
    authService: createAuthService({
      findSessionById,
      findSessionByRefreshTokenHash,
      findUserById,
      hashRefreshToken,
      insertSession,
      issueAccessToken,
      issueRefreshToken,
      now: () => new Date(),
      revokeSession,
      rotateSessionRefreshToken,
      upsertAppleUser,
      verifyAccessToken,
      verifyAppleIdentityToken,
    }),
    credentialService: createCredentialService({
      encryptSecret,
      findProviderCredential,
      now: () => new Date(),
      deleteProviderCredential,
      upsertProviderCredential,
      validateOpenAiApiKey,
    }),
    conversationService: createConversationService({
      findConversationByIdForUser,
      insertConversation,
      listConversationsForUser,
      listMessagesForConversation,
      listRunsForConversation,
      now: () => new Date(),
    }),
    agentRunService,
    chatRunService,
    syncService: createSyncService({
      listRunEventsForUser,
    }),
    runService,
  };
};
