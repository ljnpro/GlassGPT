export type MessageRole = 'system' | 'user' | 'assistant' | 'tool';

export interface MessageRecord {
  readonly id: string;
  readonly conversationId: string;
  readonly runId: string | null;
  readonly role: MessageRole;
  readonly content: string;
  readonly createdAt: string;
  readonly completedAt: string | null;
  readonly serverCursor: string | null;
}
