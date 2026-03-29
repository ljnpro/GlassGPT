import { z } from 'zod';

import { optionalTextSchema } from './common.js';

export const toolCallTypeSchema = z.enum(['web_search', 'code_interpreter', 'file_search']);
export const toolCallStatusSchema = z.enum([
  'in_progress',
  'searching',
  'interpreting',
  'file_searching',
  'completed',
]);

export const toolCallInfoSchema = z.object({
  id: z.string().min(1),
  type: toolCallTypeSchema,
  status: toolCallStatusSchema,
  code: optionalTextSchema,
  results: z.array(z.string()).optional(),
  queries: z.array(z.string()).optional(),
});

export const urlCitationSchema = z.object({
  url: z.string().url(),
  title: z.string(),
  startIndex: z.number().int().nonnegative(),
  endIndex: z.number().int().nonnegative(),
});

export const filePathAnnotationSchema = z.object({
  fileId: z.string().min(1),
  containerId: optionalTextSchema,
  sandboxPath: z.string(),
  filename: z.string().optional(),
  startIndex: z.number().int().nonnegative(),
  endIndex: z.number().int().nonnegative(),
});

export type ToolCallInfoDTO = z.infer<typeof toolCallInfoSchema>;
export type URLCitationDTO = z.infer<typeof urlCitationSchema>;
export type FilePathAnnotationDTO = z.infer<typeof filePathAnnotationSchema>;
