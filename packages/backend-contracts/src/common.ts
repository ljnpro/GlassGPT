import { z } from 'zod';

export const idSchema = z.string().min(1);
export const cursorSchema = z.string().min(1);
export const isoDateSchema = z.string().datetime({ offset: true });
export const optionalTextSchema = z.string().min(1).optional();

export const providerSchema = z.enum(['openai']);

export const errorResponseSchema = z.object({
  error: z.string().min(1),
  code: z.string().min(1),
  requestId: z.string().min(1),
  retryable: z.boolean(),
});

export type ErrorResponseDTO = z.infer<typeof errorResponseSchema>;

/**
 * Build a typed error response envelope.
 * `code` defaults to `error` when not explicitly provided.
 */
export const makeErrorResponse = (
  error: string,
  requestId: string,
  options?: { code?: string; retryable?: boolean },
): ErrorResponseDTO => {
  const code = options?.code ?? error;
  const retryable = options?.retryable ?? isRetryableErrorCode(code);
  return errorResponseSchema.parse({ error, code, requestId, retryable });
};

const RETRYABLE_ERROR_CODES = new Set([
  'internal_server_error',
  'server_error',
  'service_unavailable',
  'rate_limited',
  'realtime_stream_unavailable',
  'openai_file_upload_failed',
]);

function isRetryableErrorCode(code: string): boolean {
  return RETRYABLE_ERROR_CODES.has(code);
}
