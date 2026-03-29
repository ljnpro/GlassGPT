import type { ConversationRecord } from '../domain/conversation-model.js';

export interface ConversationListCursor {
  readonly id: string;
  readonly updatedAt: string;
}

export interface ConversationListPage {
  readonly hasMore: boolean;
  readonly items: ConversationRecord[];
  readonly nextCursor: ConversationListCursor | null;
}
