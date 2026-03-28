import { z } from 'zod';

import { conversationSchema, messageSchema } from './conversation.js';
import { artifactSchema, runEventSchema, runSummarySchema } from './run.js';

export const conversationListSchema = z.array(conversationSchema);

export const conversationDetailSchema = z.object({
  conversation: conversationSchema,
  messages: z.array(messageSchema),
  runs: z.array(runSummarySchema),
});

export const syncEnvelopeSchema = z.object({
  nextCursor: z.string().min(1).nullable().optional(),
  events: z.array(runEventSchema),
});

export const artifactDownloadSchema = z.object({
  artifact: artifactSchema,
  url: z.string().url(),
});

export type ConversationListDTO = z.infer<typeof conversationListSchema>;
export type ConversationDetailDTO = z.infer<typeof conversationDetailSchema>;
export type SyncEnvelopeDTO = z.infer<typeof syncEnvelopeSchema>;
export type ArtifactDownloadDTO = z.infer<typeof artifactDownloadSchema>;
