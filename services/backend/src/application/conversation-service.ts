import type {
  ConversationDetailDTO,
  ConversationDTO,
  CreateConversationRequestDTO,
} from '@glassgpt/backend-contracts';
import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import { buildConversationDetailDTO, buildConversationDTO } from './dto-mappers.js';
import { ApplicationError } from './errors.js';
import { createConversationId } from './ids.js';
import type { BackendRuntimeContext } from './runtime-context.js';

export interface ConversationServiceDependencies {
  readonly findConversationByIdForUser: (
    env: BackendRuntimeContext,
    conversationId: string,
    userId: string,
  ) => Promise<ConversationRecord | null>;
  readonly insertConversation: (
    env: BackendRuntimeContext,
    conversation: ConversationRecord,
  ) => Promise<void>;
  readonly listConversationsForUser: (
    env: BackendRuntimeContext,
    userId: string,
  ) => Promise<ConversationRecord[]>;
  readonly listMessagesForConversation: (
    env: BackendRuntimeContext,
    conversationId: string,
  ) => Promise<MessageRecord[]>;
  readonly listRunsForConversation: (
    env: BackendRuntimeContext,
    conversationId: string,
  ) => Promise<RunRecord[]>;
  readonly now: () => Date;
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

export const createConversationService = (
  deps: ConversationServiceDependencies,
): ConversationService => {
  return {
    createConversation: async (env, userId, input) => {
      const timestamp = deps.now().toISOString();
      const conversation: ConversationRecord = {
        createdAt: timestamp,
        id: createConversationId(),
        lastRunId: null,
        lastSyncCursor: null,
        mode: input.mode,
        title: input.title,
        updatedAt: timestamp,
        userId,
      };
      await deps.insertConversation(env, conversation);
      return buildConversationDTO(conversation);
    },

    getConversationDetail: async (env, userId, conversationId) => {
      const conversation = await deps.findConversationByIdForUser(env, conversationId, userId);
      if (!conversation) {
        throw new ApplicationError('not_found', 'conversation_not_found');
      }

      const [messages, runs] = await Promise.all([
        deps.listMessagesForConversation(env, conversationId),
        deps.listRunsForConversation(env, conversationId),
      ]);
      return buildConversationDetailDTO(conversation, messages, runs);
    },

    listConversations: async (env, userId) => {
      const conversations = await deps.listConversationsForUser(env, userId);
      return conversations.map(buildConversationDTO);
    },
  };
};
