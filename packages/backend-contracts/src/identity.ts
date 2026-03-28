import { z } from 'zod';

import { isoDateSchema, optionalTextSchema, providerSchema } from './common.js';

export const userSchema = z.object({
  id: z.string().min(1),
  appleSubject: z.string().min(1),
  displayName: optionalTextSchema,
  email: z.string().email().optional(),
  createdAt: isoDateSchema,
});

export const sessionSchema = z.object({
  accessToken: z.string().min(1),
  refreshToken: z.string().min(1),
  expiresAt: isoDateSchema,
  deviceId: z.string().min(1),
  user: userSchema,
});

export const credentialStatusStateSchema = z.enum(['missing', 'valid', 'invalid']);

export const credentialStatusSchema = z.object({
  provider: providerSchema,
  state: credentialStatusStateSchema,
  checkedAt: isoDateSchema.optional(),
  lastErrorSummary: optionalTextSchema,
});

export const appleAuthRequestSchema = z.object({
  identityToken: z.string().min(1),
  authorizationCode: optionalTextSchema,
  deviceId: z.string().min(1),
  email: z.string().email().optional(),
  givenName: optionalTextSchema,
  familyName: optionalTextSchema,
});

export const refreshSessionRequestSchema = z.object({
  refreshToken: z.string().min(1),
});

export const openAiCredentialRequestSchema = z.object({
  apiKey: z.string().min(1),
});

export type UserDTO = z.infer<typeof userSchema>;
export type SessionDTO = z.infer<typeof sessionSchema>;
export type CredentialStatusDTO = z.infer<typeof credentialStatusSchema>;
export type AppleAuthRequestDTO = z.infer<typeof appleAuthRequestSchema>;
export type RefreshSessionRequestDTO = z.infer<typeof refreshSessionRequestSchema>;
export type OpenAiCredentialRequestDTO = z.infer<typeof openAiCredentialRequestSchema>;
