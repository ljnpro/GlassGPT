const joinSections = (sections: readonly string[]): string => {
  return sections.join('\n\n');
};

export const buildLeaderPlanningPrompt = (userPrompt: string): string => {
  return joinSections([
    'You are the lead planner for a backend-owned AI agent run.',
    'Produce an internal execution plan for the user request. Do not answer the user directly.',
    'Return plain text with these headings exactly:',
    'Objective:',
    'Constraints:',
    'Plan:',
    'Worker Briefs:',
    `User Request:\n${userPrompt}`,
  ]);
};

export const buildWorkerWavePrompt = (input: {
  readonly leaderPlan: string;
  readonly userPrompt: string;
}): string => {
  return joinSections([
    'You are the worker wave for a backend-owned AI agent run.',
    'Execute the planner direction and gather the strongest analysis you can without mentioning internal workflow mechanics.',
    'Return plain text with these headings exactly:',
    'Findings:',
    'Risks:',
    'Open Questions:',
    'Recommended Direction:',
    `User Request:\n${input.userPrompt}`,
    `Leader Plan:\n${input.leaderPlan}`,
  ]);
};

export const buildLeaderReviewPrompt = (input: {
  readonly leaderPlan: string;
  readonly userPrompt: string;
  readonly workerReport: string;
}): string => {
  return joinSections([
    'You are the lead reviewer for a backend-owned AI agent run.',
    'Audit the worker output against the plan. Identify weak reasoning, missing constraints, and the best path to a final answer.',
    'Return plain text with these headings exactly:',
    'Review Summary:',
    'Corrections:',
    'Approved Direction:',
    `User Request:\n${input.userPrompt}`,
    `Leader Plan:\n${input.leaderPlan}`,
    `Worker Report:\n${input.workerReport}`,
  ]);
};

export const buildFinalSynthesisPrompt = (input: {
  readonly leaderPlan: string;
  readonly leaderReview: string;
  readonly userPrompt: string;
  readonly workerReport: string;
}): string => {
  return joinSections([
    'You are preparing the final user-facing answer for a backend-owned AI agent run.',
    'Answer the user directly. Do not mention planning, workers, hidden stages, or internal process.',
    'Use concise markdown when it improves readability.',
    `User Request:\n${input.userPrompt}`,
    `Leader Plan:\n${input.leaderPlan}`,
    `Worker Report:\n${input.workerReport}`,
    `Leader Review:\n${input.leaderReview}`,
  ]);
};
