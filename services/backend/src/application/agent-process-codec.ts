export const summarize = (text: string, maxLength = 160): string => {
  const normalized = text.trim().replace(/\s+/g, ' ');
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return `${normalized.slice(0, maxLength - 1).trimEnd()}…`;
};

export const sectionLines = (input: string, heading: string): string[] => {
  const expression = new RegExp(`${heading}:\\s*([\\s\\S]*?)(?:\\n[A-Z][^\\n]*:|$)`, 'i');
  const match = input.match(expression);
  if (!match?.[1]) {
    return [];
  }

  return match[1]
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => line.replace(/^[-*0-9.)\s]+/, '').trim())
    .filter((line) => line.length > 0);
};

export const buildWorkerSummaries = (workerSummary: string) => {
  const adoptedPoints = sectionLines(workerSummary, 'Findings').slice(0, 2);
  return [
    { adoptedPoints, role: 'workerA', summary: summarize(workerSummary, 180) },
    { adoptedPoints, role: 'workerB', summary: summarize(workerSummary, 180) },
    { adoptedPoints, role: 'workerC', summary: summarize(workerSummary, 180) },
  ];
};

export const encodeAgentProcessSnapshot = (snapshot: unknown): string => {
  return JSON.stringify(snapshot);
};

export const decodeAgentProcessSnapshot = <T>(json: string | null): T | null => {
  if (!json) {
    return null;
  }
  return JSON.parse(json) as T;
};

export const buildAgentTurnTraceJSON = (input: {
  readonly completedAt: Date;
  readonly leaderBriefSummary: string;
  readonly outcome: string;
  readonly processSnapshot: unknown;
  readonly workerSummary: string;
}) => {
  return JSON.stringify({
    completedAt: input.completedAt,
    completedStage: 'finalSynthesis',
    leaderBriefSummary: summarize(input.leaderBriefSummary, 180),
    outcome: input.outcome,
    processSnapshot: input.processSnapshot,
    workerSummaries: buildWorkerSummaries(input.workerSummary),
  });
};
