import type { AgentStage, RunStatus } from './run-phase.js';

export type RunKind = 'chat' | 'agent';

export interface RunRecord {
  readonly id: string;
  readonly conversationId: string;
  readonly userId: string;
  readonly kind: RunKind;
  readonly status: RunStatus;
  readonly stage: AgentStage | null;
  readonly createdAt: string;
  readonly updatedAt: string;
  readonly lastEventCursor: string | null;
  readonly visibleSummary: string | null;
  readonly processSnapshotJSON: string | null;
}
