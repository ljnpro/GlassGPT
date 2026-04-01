import { buildWorkerSummaries, sectionLines, summarize } from './agent-process-codec.js';

export {
  buildAgentTurnTraceJSON,
  decodeAgentProcessSnapshot,
  encodeAgentProcessSnapshot,
} from './agent-process-codec.js';

export interface AgentTaskPayload {
  readonly completedAt: Date | null;
  readonly contextSummary: string;
  readonly dependencyIDs: readonly string[];
  readonly expectedOutput: string;
  readonly goal: string;
  readonly id: string;
  readonly liveConfidence: 'high' | 'low' | 'medium' | null;
  readonly liveEvidence: readonly string[];
  readonly liveRisks: readonly string[];
  readonly liveStatusText: string | null;
  readonly liveSummary: string | null;
  readonly owner: 'leader' | 'workerA' | 'workerB' | 'workerC';
  readonly parentStepID: string | null;
  readonly result: {
    readonly citations: readonly unknown[];
    readonly confidence: 'high' | 'low' | 'medium';
    readonly evidence: readonly string[];
    readonly followUpRecommendations: readonly unknown[];
    readonly risks: readonly string[];
    readonly summary: string;
    readonly toolCalls: readonly unknown[];
  } | null;
  readonly resultSummary: string | null;
  readonly startedAt: Date | null;
  readonly status: 'blocked' | 'completed' | 'discarded' | 'failed' | 'queued' | 'running';
  readonly title: string;
  readonly toolPolicy: 'enabled' | 'reasoningOnly';
}

export interface AgentProcessUpdatePayload {
  readonly createdAt: Date;
  readonly id: string;
  readonly kind:
    | 'councilCompleted'
    | 'leaderPhase'
    | 'runStarted'
    | 'workerCompleted'
    | 'workerStarted'
    | 'workerWaveQueued';
  readonly phase: null;
  readonly source: 'leader' | 'system' | 'workerA' | 'workerB' | 'workerC';
  readonly sourceEventID: null;
  readonly summary: string;
  readonly taskID: string | null;
  readonly updatedAt: Date;
}

export interface AgentProcessSnapshotPayload {
  readonly activeTaskIDs: readonly string[];
  readonly activity:
    | 'completed'
    | 'delegation'
    | 'failed'
    | 'localPass'
    | 'reviewing'
    | 'synthesis'
    | 'triage';
  readonly currentFocus: string;
  readonly decisions: readonly unknown[];
  readonly events: readonly unknown[];
  readonly evidence: readonly string[];
  readonly leaderAcceptedFocus: string;
  readonly leaderLiveStatus: string;
  readonly leaderLiveSummary: string;
  readonly outcome: string;
  readonly plan: readonly {
    readonly id: string;
    readonly owner: 'leader';
    readonly parentStepID: null;
    readonly status: 'blocked' | 'completed' | 'planned' | 'running';
    readonly summary: string;
    readonly title: string;
  }[];
  readonly recentUpdateItems: readonly AgentProcessUpdatePayload[];
  readonly recentUpdates: readonly string[];
  readonly recoveryState: 'idle';
  readonly stopReason:
    | 'budgetReached'
    | 'cancelled'
    | 'clarificationRequired'
    | 'incomplete'
    | 'sufficientAnswer'
    | 'toolFailure'
    | null;
  readonly tasks: readonly AgentTaskPayload[];
  readonly updatedAt: Date;
}

interface AgentPlanStepPayload {
  readonly id: string;
  readonly owner: 'leader';
  readonly parentStepID: null;
  readonly status: 'blocked' | 'completed' | 'planned' | 'running';
  readonly summary: string;
  readonly title: string;
}

const buildDefaultWorkerTasks = (focus: string, contextSummary: string): AgentTaskPayload[] => {
  return [
    {
      completedAt: null,
      contextSummary,
      dependencyIDs: [],
      expectedOutput: 'Key evidence and citations that best support the answer.',
      goal: focus,
      id: 'task_worker_a',
      liveConfidence: null,
      liveEvidence: [],
      liveRisks: [],
      liveStatusText: null,
      liveSummary: null,
      owner: 'workerA',
      parentStepID: 'plan_worker_wave',
      result: null,
      resultSummary: null,
      startedAt: null,
      status: 'queued',
      title: 'Evidence scan',
      toolPolicy: 'enabled',
    },
    {
      completedAt: null,
      contextSummary,
      dependencyIDs: [],
      expectedOutput: 'Risks, edge cases, and contradictions the leader should review.',
      goal: focus,
      id: 'task_worker_b',
      liveConfidence: null,
      liveEvidence: [],
      liveRisks: [],
      liveStatusText: null,
      liveSummary: null,
      owner: 'workerB',
      parentStepID: 'plan_worker_wave',
      result: null,
      resultSummary: null,
      startedAt: null,
      status: 'queued',
      title: 'Risk audit',
      toolPolicy: 'enabled',
    },
    {
      completedAt: null,
      contextSummary,
      dependencyIDs: [],
      expectedOutput: 'A synthesis-ready framing and recommended direction.',
      goal: focus,
      id: 'task_worker_c',
      liveConfidence: null,
      liveEvidence: [],
      liveRisks: [],
      liveStatusText: null,
      liveSummary: null,
      owner: 'workerC',
      parentStepID: 'plan_worker_wave',
      result: null,
      resultSummary: null,
      startedAt: null,
      status: 'queued',
      title: 'Synthesis prep',
      toolPolicy: 'enabled',
    },
  ];
};

const buildPlanSteps = (input: {
  readonly leaderPlan: string | null;
  readonly workerWaveStatus: 'blocked' | 'completed' | 'planned' | 'running';
  readonly leaderPlanningStatus: 'blocked' | 'completed' | 'planned' | 'running';
  readonly leaderReviewStatus: 'blocked' | 'completed' | 'planned' | 'running';
  readonly finalSynthesisStatus: 'blocked' | 'completed' | 'planned' | 'running';
}): AgentPlanStepPayload[] => {
  const planBullets = input.leaderPlan ? sectionLines(input.leaderPlan, 'Plan') : [];
  const leaderSummary = planBullets[0] ?? 'Clarify the request and shape the execution plan.';
  const workerSummary = planBullets[1] ?? 'Run the worker wave and gather supporting evidence.';
  const reviewSummary = planBullets[2] ?? 'Review worker findings and approve the direction.';
  const synthesisSummary = planBullets[3] ?? 'Synthesize a concise final answer.';

  return [
    {
      id: 'plan_leader_triage',
      owner: 'leader' as const,
      parentStepID: null,
      status: input.leaderPlanningStatus,
      summary: leaderSummary,
      title: 'Leader planning',
    },
    {
      id: 'plan_worker_wave',
      owner: 'leader' as const,
      parentStepID: null,
      status: input.workerWaveStatus,
      summary: workerSummary,
      title: 'Worker wave',
    },
    {
      id: 'plan_leader_review',
      owner: 'leader' as const,
      parentStepID: null,
      status: input.leaderReviewStatus,
      summary: reviewSummary,
      title: 'Leader review',
    },
    {
      id: 'plan_final_synthesis',
      owner: 'leader' as const,
      parentStepID: null,
      status: input.finalSynthesisStatus,
      summary: synthesisSummary,
      title: 'Final synthesis',
    },
  ];
};

export const buildRecentUpdate = (input: {
  readonly kind:
    | 'councilCompleted'
    | 'leaderPhase'
    | 'runStarted'
    | 'workerCompleted'
    | 'workerStarted'
    | 'workerWaveQueued';
  readonly source: 'leader' | 'system' | 'workerA' | 'workerB' | 'workerC';
  readonly summary: string;
  readonly taskID?: string;
  readonly timestamp: Date;
}) => {
  return {
    createdAt: input.timestamp,
    id: crypto.randomUUID(),
    kind: input.kind,
    phase: null,
    source: input.source,
    sourceEventID: null,
    summary: summarize(input.summary, 140),
    taskID: input.taskID ?? null,
    updatedAt: input.timestamp,
  };
};

export const buildQueuedAgentProcessSnapshot = (input: {
  readonly now: Date;
  readonly userPrompt: string;
}): AgentProcessSnapshotPayload => {
  const focus = summarize(input.userPrompt, 140);
  const tasks = buildDefaultWorkerTasks(focus, 'Waiting for the leader plan.');
  const updates = [
    buildRecentUpdate({
      kind: 'runStarted',
      source: 'system',
      summary: 'Queued agent workflow.',
      timestamp: input.now,
    }),
  ];

  return {
    activeTaskIDs: [],
    activity: 'triage',
    currentFocus: focus,
    decisions: [],
    events: [],
    evidence: [],
    leaderAcceptedFocus: focus,
    leaderLiveStatus: 'Queued',
    leaderLiveSummary: 'Preparing agent run',
    outcome: '',
    plan: buildPlanSteps({
      finalSynthesisStatus: 'planned',
      leaderPlan: null,
      leaderPlanningStatus: 'running',
      leaderReviewStatus: 'planned',
      workerWaveStatus: 'planned',
    }),
    recentUpdateItems: updates,
    recentUpdates: updates.map((update) => update.summary),
    recoveryState: 'idle',
    stopReason: null,
    tasks,
    updatedAt: input.now,
  };
};

export const buildStageAgentProcessSnapshot = (input: {
  readonly now: Date;
  readonly outcome?: string;
  readonly currentFocus: string;
  readonly leaderAcceptedFocus?: string;
  readonly leaderLiveStatus: string;
  readonly leaderLiveSummary: string;
  readonly leaderPlan: string | null;
  readonly recentUpdateItems: readonly AgentProcessUpdatePayload[];
  readonly activeTaskIDs: readonly string[];
  readonly tasks: readonly AgentTaskPayload[];
  readonly activity:
    | 'completed'
    | 'delegation'
    | 'failed'
    | 'localPass'
    | 'reviewing'
    | 'synthesis'
    | 'triage';
  readonly stopReason?:
    | 'budgetReached'
    | 'cancelled'
    | 'clarificationRequired'
    | 'incomplete'
    | 'sufficientAnswer'
    | 'toolFailure'
    | null;
  readonly stageStatuses: {
    readonly finalSynthesis: 'blocked' | 'completed' | 'planned' | 'running';
    readonly leaderPlanning: 'blocked' | 'completed' | 'planned' | 'running';
    readonly leaderReview: 'blocked' | 'completed' | 'planned' | 'running';
    readonly workerWave: 'blocked' | 'completed' | 'planned' | 'running';
  };
}): AgentProcessSnapshotPayload => {
  const recentUpdateItems: AgentProcessUpdatePayload[] = [...input.recentUpdateItems];

  return {
    activeTaskIDs: [...input.activeTaskIDs],
    activity: input.activity,
    currentFocus: input.currentFocus,
    decisions: [],
    events: [],
    evidence: [],
    leaderAcceptedFocus: input.leaderAcceptedFocus ?? input.currentFocus,
    leaderLiveStatus: input.leaderLiveStatus,
    leaderLiveSummary: input.leaderLiveSummary,
    outcome: input.outcome ?? '',
    plan: buildPlanSteps({
      finalSynthesisStatus: input.stageStatuses.finalSynthesis,
      leaderPlan: input.leaderPlan,
      leaderPlanningStatus: input.stageStatuses.leaderPlanning,
      leaderReviewStatus: input.stageStatuses.leaderReview,
      workerWaveStatus: input.stageStatuses.workerWave,
    }),
    recentUpdateItems,
    recentUpdates: recentUpdateItems.map((update) => (update as { summary: string }).summary),
    recoveryState: 'idle',
    stopReason: input.stopReason ?? null,
    tasks: [...input.tasks],
    updatedAt: input.now,
  };
};

export const buildWorkerWaveTasks = (input: {
  readonly leaderPlan: string;
  readonly now: Date;
  readonly userPrompt: string;
  readonly workerSummary?: string | null;
}): AgentTaskPayload[] => {
  const focus = summarize(input.userPrompt, 140);
  const briefs = sectionLines(input.leaderPlan, 'Worker Briefs');
  const tasks = buildDefaultWorkerTasks(focus, summarize(input.leaderPlan, 180));
  const summaries = input.workerSummary ? buildWorkerSummaries(input.workerSummary) : null;

  return tasks.map((task, index) => {
    const summary = input.workerSummary ? summarize(input.workerSummary, 180) : null;
    const roleSummary = summaries?.[index] ?? null;
    return {
      ...task,
      completedAt: summary ? input.now : null,
      contextSummary: briefs[index] ?? task.contextSummary,
      liveConfidence: summary ? ('medium' as const) : null,
      liveEvidence: summary ? sectionLines(input.workerSummary ?? '', 'Findings').slice(0, 2) : [],
      liveRisks: summary ? sectionLines(input.workerSummary ?? '', 'Risks').slice(0, 2) : [],
      liveStatusText: summary ? 'Completed' : 'Running',
      liveSummary: summary,
      result: summary
        ? {
            citations: [],
            confidence: 'medium',
            evidence: sectionLines(input.workerSummary ?? '', 'Findings').slice(0, 2),
            followUpRecommendations: [],
            risks: sectionLines(input.workerSummary ?? '', 'Risks').slice(0, 2),
            summary,
            toolCalls: [],
          }
        : null,
      resultSummary: roleSummary?.summary ?? summary,
      startedAt: input.now,
      status: summary ? ('completed' as const) : ('running' as const),
      title: briefs[index] ?? task.title,
    };
  });
};
