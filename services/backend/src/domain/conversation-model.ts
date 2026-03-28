export type ConversationMode = 'chat' | 'agent';

export interface ConversationRecord {
  readonly id: string;
  readonly userId: string;
  readonly title: string;
  readonly mode: ConversationMode;
  readonly createdAt: string;
  readonly updatedAt: string;
  readonly lastRunId: string | null;
  readonly lastSyncCursor: string | null;
}
