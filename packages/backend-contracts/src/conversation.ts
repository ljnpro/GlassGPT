import { z } from 'zod';

import { cursorSchema, idSchema, isoDateSchema, optionalTextSchema } from './common.js';
import { filePathAnnotationSchema, toolCallInfoSchema, urlCitationSchema } from './payloads.js';

export const conversationModeSchema = z.enum(['chat', 'agent']);
export const messageRoleSchema = z.enum(['system', 'user', 'assistant', 'tool']);
export const modelSchema = z.enum(['gpt-5.4', 'gpt-5.4-pro']);
export const reasoningEffortSchema = z.enum(['none', 'low', 'medium', 'high', 'xhigh']);
export const serviceTierSchema = z.enum(['default', 'flex']);

export const conversationSchema = z.object({
  id: idSchema,
  title: z.string().min(1),
  mode: conversationModeSchema,
  createdAt: isoDateSchema,
  updatedAt: isoDateSchema,
  lastRunId: optionalTextSchema,
  lastSyncCursor: cursorSchema.optional(),
  model: modelSchema.optional(),
  reasoningEffort: reasoningEffortSchema.optional(),
  agentWorkerReasoningEffort: reasoningEffortSchema.optional(),
  serviceTier: serviceTierSchema.optional(),
});

export const messageSchema = z.object({
  id: idSchema,
  conversationId: idSchema,
  role: messageRoleSchema,
  content: z.string(),
  thinking: optionalTextSchema,
  createdAt: isoDateSchema,
  completedAt: isoDateSchema.optional(),
  serverCursor: cursorSchema.optional(),
  runId: idSchema.optional(),
  annotations: z.array(urlCitationSchema).optional(),
  toolCalls: z.array(toolCallInfoSchema).optional(),
  filePathAnnotations: z.array(filePathAnnotationSchema).optional(),
  agentTraceJSON: optionalTextSchema,
});

export const createConversationRequestSchema = z.object({
  title: z.string().min(1),
  mode: conversationModeSchema,
  model: modelSchema.optional(),
  reasoningEffort: reasoningEffortSchema.optional(),
  agentWorkerReasoningEffort: reasoningEffortSchema.optional(),
  serviceTier: serviceTierSchema.optional(),
});

export const createMessageRequestSchema = z.object({
  content: z.string().min(1),
});

export const updateConversationConfigurationRequestSchema = z.object({
  model: modelSchema.optional(),
  reasoningEffort: reasoningEffortSchema.optional(),
  agentWorkerReasoningEffort: reasoningEffortSchema.optional(),
  serviceTier: serviceTierSchema.optional(),
});

export const listConversationsQuerySchema = z.object({
  cursor: optionalTextSchema,
  limit: z.coerce.number().int().positive().max(100).optional(),
});

export const conversationPageSchema = z.object({
  items: z.array(conversationSchema),
  nextCursor: optionalTextSchema,
  hasMore: z.boolean(),
});

export type ConversationDTO = z.infer<typeof conversationSchema>;
export type ConversationPageDTO = z.infer<typeof conversationPageSchema>;
export type MessageDTO = z.infer<typeof messageSchema>;
export type CreateConversationRequestDTO = z.infer<typeof createConversationRequestSchema>;
export type CreateMessageRequestDTO = z.infer<typeof createMessageRequestSchema>;
export type ListConversationsQueryDTO = z.infer<typeof listConversationsQuerySchema>;
export type UpdateConversationConfigurationRequestDTO = z.infer<
  typeof updateConversationConfigurationRequestSchema
>;
