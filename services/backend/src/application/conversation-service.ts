import type {
  ConversationDetailDTO,
  ConversationDTO,
  ConversationPageDTO,
  CreateConversationRequestDTO,
  ListConversationsQueryDTO,
  UpdateConversationConfigurationRequestDTO,
} from '@glassgpt/backend-contracts';
import type { ConversationRecord } from '../domain/conversation-model.js';
import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type {
  ConversationListCursor,
  ConversationListPage,
} from './conversation-list-pagination.js';
import {
  buildConversationDetailDTO,
  buildConversationDTO,
  buildConversationPageDTO,
} from './dto-mappers.js';
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
    input: {
      readonly cursor: ConversationListCursor | null;
      readonly limit: number;
    },
  ) => Promise<ConversationListPage>;
  readonly listMessagesForConversation: (
    env: BackendRuntimeContext,
    conversationId: string,
  ) => Promise<MessageRecord[]>;
  readonly listRunsForConversation: (
    env: BackendRuntimeContext,
    conversationId: string,
  ) => Promise<RunRecord[]>;
  readonly now: () => Date;
  readonly updateConversationConfiguration: (
    env: BackendRuntimeContext,
    input: {
      readonly conversationId: string;
      readonly model: ConversationRecord['model'];
      readonly reasoningEffort: ConversationRecord['reasoningEffort'];
      readonly agentWorkerReasoningEffort: ConversationRecord['agentWorkerReasoningEffort'];
      readonly serviceTier: ConversationRecord['serviceTier'];
      readonly updatedAt: string;
    },
  ) => Promise<void>;
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
  listConversations(
    env: BackendRuntimeContext,
    userId: string,
    input: ListConversationsQueryDTO,
  ): Promise<ConversationPageDTO>;
  updateConversationConfiguration(
    env: BackendRuntimeContext,
    userId: string,
    conversationId: string,
    input: UpdateConversationConfigurationRequestDTO,
  ): Promise<ConversationDTO>;
}

const defaultChatConfiguration = {
  agentWorkerReasoningEffort: null,
  model: 'gpt-5.4',
  reasoningEffort: 'high',
  serviceTier: 'default',
} as const satisfies Pick<
  ConversationRecord,
  'agentWorkerReasoningEffort' | 'model' | 'reasoningEffort' | 'serviceTier'
>;

const defaultAgentConfiguration = {
  agentWorkerReasoningEffort: 'low',
  model: null,
  reasoningEffort: 'high',
  serviceTier: 'default',
} as const satisfies Pick<
  ConversationRecord,
  'agentWorkerReasoningEffort' | 'model' | 'reasoningEffort' | 'serviceTier'
>;

const resolveConversationConfiguration = (
  mode: ConversationRecord['mode'],
  input: Pick<
    UpdateConversationConfigurationRequestDTO,
    'agentWorkerReasoningEffort' | 'model' | 'reasoningEffort' | 'serviceTier'
  >,
): Pick<
  ConversationRecord,
  'agentWorkerReasoningEffort' | 'model' | 'reasoningEffort' | 'serviceTier'
> => {
  if (mode === 'chat') {
    return {
      agentWorkerReasoningEffort: null,
      model: input.model ?? defaultChatConfiguration.model,
      reasoningEffort: input.reasoningEffort ?? defaultChatConfiguration.reasoningEffort,
      serviceTier: input.serviceTier ?? defaultChatConfiguration.serviceTier,
    };
  }

  return {
    agentWorkerReasoningEffort:
      input.agentWorkerReasoningEffort ?? defaultAgentConfiguration.agentWorkerReasoningEffort,
    model: null,
    reasoningEffort: input.reasoningEffort ?? defaultAgentConfiguration.reasoningEffort,
    serviceTier: input.serviceTier ?? defaultAgentConfiguration.serviceTier,
  };
};

const DEFAULT_CONVERSATION_PAGE_LIMIT = 100;

const encodeConversationPageCursor = (cursor: ConversationListCursor | null): string | null => {
  if (!cursor) {
    return null;
  }

  return btoa(JSON.stringify(cursor));
};

const decodeConversationPageCursor = (cursor: string): ConversationListCursor => {
  try {
    const parsed = JSON.parse(atob(cursor)) as Partial<ConversationListCursor>;
    if (typeof parsed.id !== 'string' || typeof parsed.updatedAt !== 'string') {
      throw new Error('conversation_page_cursor_invalid');
    }

    return {
      id: parsed.id,
      updatedAt: parsed.updatedAt,
    };
  } catch {
    throw new ApplicationError('invalid_request', 'conversation_page_cursor_invalid');
  }
};

export const createConversationService = (
  deps: ConversationServiceDependencies,
): ConversationService => {
  return {
    createConversation: async (env, userId, input) => {
      const timestamp = deps.now().toISOString();
      const conversation: ConversationRecord = {
        ...resolveConversationConfiguration(input.mode, input),
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

    listConversations: async (env, userId, input) => {
      const page = await deps.listConversationsForUser(env, userId, {
        cursor: input.cursor ? decodeConversationPageCursor(input.cursor) : null,
        limit: input.limit ?? DEFAULT_CONVERSATION_PAGE_LIMIT,
      });
      return buildConversationPageDTO(
        page.items,
        encodeConversationPageCursor(page.nextCursor),
        page.hasMore,
      );
    },

    updateConversationConfiguration: async (env, userId, conversationId, input) => {
      const existing = await deps.findConversationByIdForUser(env, conversationId, userId);
      if (!existing) {
        throw new ApplicationError('not_found', 'conversation_not_found');
      }

      const configuration = resolveConversationConfiguration(existing.mode, input);
      const updatedConversation: ConversationRecord = {
        ...existing,
        ...configuration,
        updatedAt: deps.now().toISOString(),
      };
      await deps.updateConversationConfiguration(env, {
        agentWorkerReasoningEffort: updatedConversation.agentWorkerReasoningEffort,
        conversationId,
        model: updatedConversation.model,
        reasoningEffort: updatedConversation.reasoningEffort,
        serviceTier: updatedConversation.serviceTier,
        updatedAt: updatedConversation.updatedAt,
      });
      return buildConversationDTO(updatedConversation);
    },
  };
};
