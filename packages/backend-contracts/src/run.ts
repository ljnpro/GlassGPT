import { z } from 'zod';

import { cursorSchema, idSchema, isoDateSchema, optionalTextSchema } from './common.js';
import { conversationSchema, messageSchema } from './conversation.js';

export const healthStateSchema = z.enum([
  'healthy',
  'degraded',
  'unavailable',
  'missing',
  'invalid',
  'unauthorized',
]);

export const runKindSchema = z.enum(['chat', 'agent']);
export const runStatusSchema = z.enum(['queued', 'running', 'completed', 'failed', 'cancelled']);
export const agentStageSchema = z.enum([
  'leader_planning',
  'worker_wave',
  'leader_review',
  'final_synthesis',
]);
export const runEventKindSchema = z.enum([
  'message_created',
  'run_queued',
  'run_started',
  'run_progress',
  'assistant_delta',
  'assistant_completed',
  'stage_changed',
  'artifact_created',
  'run_completed',
  'run_failed',
  'run_cancelled',
]);
export const artifactKindSchema = z.enum(['image', 'document', 'code', 'data']);

export const connectionCheckSchema = z.object({
  backend: healthStateSchema,
  auth: healthStateSchema,
  openaiCredential: healthStateSchema,
  sse: healthStateSchema,
  checkedAt: isoDateSchema,
  latencyMilliseconds: z.number().int().nonnegative().optional(),
  errorSummary: optionalTextSchema,
});

export const runSummarySchema = z.object({
  id: idSchema,
  conversationId: idSchema,
  kind: runKindSchema,
  status: runStatusSchema,
  stage: agentStageSchema.optional(),
  createdAt: isoDateSchema,
  updatedAt: isoDateSchema,
  lastEventCursor: cursorSchema.optional(),
  visibleSummary: optionalTextSchema,
  processSnapshotJSON: optionalTextSchema,
});

export const artifactSchema = z.object({
  id: idSchema,
  conversationId: idSchema,
  runId: idSchema,
  kind: artifactKindSchema,
  filename: z.string().min(1),
  contentType: z.string().min(1),
  byteCount: z.number().int().nonnegative(),
  createdAt: isoDateSchema,
  downloadUrl: z.string().url().optional(),
});

export const runEventSchema = z.object({
  id: idSchema,
  cursor: cursorSchema,
  runId: idSchema,
  conversationId: idSchema,
  kind: runEventKindSchema,
  createdAt: isoDateSchema,
  stage: agentStageSchema.optional(),
  textDelta: optionalTextSchema,
  progressLabel: optionalTextSchema,
  artifactId: idSchema.optional(),
  conversation: conversationSchema.optional(),
  message: messageSchema.optional(),
  run: runSummarySchema.optional(),
  artifact: artifactSchema.optional(),
});

export const startAgentRunRequestSchema = z.object({
  prompt: optionalTextSchema,
});

export type ConnectionCheckDTO = z.infer<typeof connectionCheckSchema>;
export type RunSummaryDTO = z.infer<typeof runSummarySchema>;
export type RunEventDTO = z.infer<typeof runEventSchema>;
export type ArtifactDTO = z.infer<typeof artifactSchema>;
export type StartAgentRunRequestDTO = z.infer<typeof startAgentRunRequestSchema>;
