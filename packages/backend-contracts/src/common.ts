import { z } from 'zod';

export const idSchema = z.string().min(1);
export const cursorSchema = z.string().min(1);
export const isoDateSchema = z.string().datetime({ offset: true });
export const optionalTextSchema = z.string().min(1).optional();

export const providerSchema = z.enum(['openai']);

export const errorResponseSchema = z.object({
  error: z.string().min(1),
});

export type ErrorResponseDTO = z.infer<typeof errorResponseSchema>;
