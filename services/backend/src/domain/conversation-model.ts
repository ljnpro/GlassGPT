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
  readonly model?: 'gpt-5.4' | 'gpt-5.4-pro' | null;
  readonly reasoningEffort?: 'none' | 'low' | 'medium' | 'high' | 'xhigh' | null;
  readonly agentWorkerReasoningEffort?: 'none' | 'low' | 'medium' | 'high' | 'xhigh' | null;
  readonly serviceTier?: 'default' | 'flex' | null;
}
