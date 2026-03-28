import type { ArtifactRecord } from './artifact-model.js';
import type { ConversationRecord } from './conversation-model.js';
import type { MessageRecord } from './message-model.js';
import type { RunRecord } from './run-model.js';
import type { AgentStage } from './run-phase.js';

export type RunEventKind =
  | 'message_created'
  | 'run_queued'
  | 'run_started'
  | 'run_progress'
  | 'assistant_delta'
  | 'assistant_completed'
  | 'stage_changed'
  | 'artifact_created'
  | 'run_completed'
  | 'run_failed'
  | 'run_cancelled';

export interface RunEventRecord {
  readonly id: string;
  readonly cursor: string;
  readonly runId: string;
  readonly conversationId: string;
  readonly kind: RunEventKind;
  readonly createdAt: string;
  readonly stage: AgentStage | null;
  readonly textDelta: string | null;
  readonly progressLabel: string | null;
  readonly artifactId: string | null;
  readonly conversation: ConversationRecord | null;
  readonly message: MessageRecord | null;
  readonly run: RunRecord | null;
  readonly artifact: ArtifactRecord | null;
}

export interface RunEventInsertRecord {
  readonly id: string;
  readonly runId: string;
  readonly conversationId: string;
  readonly kind: RunEventKind;
  readonly createdAt: string;
  readonly stage: AgentStage | null;
  readonly textDelta: string | null;
  readonly progressLabel: string | null;
  readonly artifactId: string | null;
}
