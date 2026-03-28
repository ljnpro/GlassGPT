export const runStatuses = ['queued', 'running', 'completed', 'failed', 'cancelled'] as const;

export const agentStages = [
  'leader_planning',
  'worker_wave',
  'leader_review',
  'final_synthesis',
] as const;

export type RunStatus = (typeof runStatuses)[number];
export type AgentStage = (typeof agentStages)[number];
