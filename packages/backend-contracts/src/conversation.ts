import { z } from 'zod';

import { cursorSchema, idSchema, isoDateSchema, optionalTextSchema } from './common.js';

export const conversationModeSchema = z.enum(['chat', 'agent']);
export const messageRoleSchema = z.enum(['system', 'user', 'assistant', 'tool']);

export const conversationSchema = z.object({
  id: idSchema,
  title: z.string().min(1),
  mode: conversationModeSchema,
  createdAt: isoDateSchema,
  updatedAt: isoDateSchema,
  lastRunId: optionalTextSchema,
  lastSyncCursor: cursorSchema.optional(),
});

export const messageSchema = z.object({
  id: idSchema,
  conversationId: idSchema,
  role: messageRoleSchema,
  content: z.string(),
  createdAt: isoDateSchema,
  completedAt: isoDateSchema.optional(),
  serverCursor: cursorSchema.optional(),
  runId: idSchema.optional(),
});

export const createConversationRequestSchema = z.object({
  title: z.string().min(1),
  mode: conversationModeSchema,
});

export const createMessageRequestSchema = z.object({
  content: z.string().min(1),
});

export type ConversationDTO = z.infer<typeof conversationSchema>;
export type MessageDTO = z.infer<typeof messageSchema>;
export type CreateConversationRequestDTO = z.infer<typeof createConversationRequestSchema>;
export type CreateMessageRequestDTO = z.infer<typeof createMessageRequestSchema>;
