import { describe, expect, it } from 'vitest';

import type { ProviderCredentialRecord } from './auth-records.js';
import { createCredentialService } from './credential-service.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const now = new Date('2026-03-27T00:00:00.000Z');

const testEnv = {
  APPLE_AUDIENCE: 'com.glassgpt.app',
  APPLE_BUNDLE_ID: 'com.glassgpt.app',
  CREDENTIAL_ENCRYPTION_KEY: '00',
  CREDENTIAL_ENCRYPTION_KEY_VERSION: 'v1',
  REFRESH_TOKEN_SIGNING_KEY: '11',
  SESSION_SIGNING_KEY: '22',
} as BackendRuntimeContext;

const existingCredential: ProviderCredentialRecord = {
  checkedAt: now.toISOString(),
  ciphertext: 'ciphertext_existing',
  createdAt: now.toISOString(),
  id: 'cred_01',
  keyVersion: 'v1',
  lastErrorSummary: null,
  nonce: 'nonce_existing',
  provider: 'openai',
  status: 'valid',
  updatedAt: now.toISOString(),
  userId: 'usr_01',
};

describe('createCredentialService', () => {
  it('reports missing when the user has not stored a provider key', async () => {
    const service = createCredentialService({
      deleteProviderCredential: async () => {},
      encryptSecret: async () => ({
        ciphertext: 'ciphertext',
        keyVersion: 'v1',
        nonce: 'nonce',
      }),
      findProviderCredential: async () => null,
      now: () => now,
      upsertProviderCredential: async () => {},
      validateOpenAiApiKey: async () => ({
        checkedAt: now.toISOString(),
        lastErrorSummary: null,
        state: 'valid',
      }),
    });

    await expect(service.readOpenAiKeyStatus(testEnv, 'usr_01')).resolves.toEqual({
      checkedAt: undefined,
      lastErrorSummary: undefined,
      provider: 'openai',
      state: 'missing',
    });
  });

  it('stores validated keys and preserves the existing credential identity', async () => {
    let upsertedCredential: ProviderCredentialRecord | null = null;
    const service = createCredentialService({
      deleteProviderCredential: async () => {},
      encryptSecret: async () => ({
        ciphertext: 'ciphertext_next',
        keyVersion: 'v2',
        nonce: 'nonce_next',
      }),
      findProviderCredential: async () => existingCredential,
      now: () => now,
      upsertProviderCredential: async (_env, credential) => {
        upsertedCredential = credential;
      },
      validateOpenAiApiKey: async () => ({
        checkedAt: now.toISOString(),
        lastErrorSummary: null,
        state: 'valid',
      }),
    });

    const status = await service.storeOpenAiKey(testEnv, 'usr_01', 'sk-live');

    expect(upsertedCredential).toEqual({
      ...existingCredential,
      checkedAt: now.toISOString(),
      ciphertext: 'ciphertext_next',
      keyVersion: 'v2',
      lastErrorSummary: null,
      nonce: 'nonce_next',
      status: 'valid',
      updatedAt: now.toISOString(),
    });
    expect(status).toEqual({
      checkedAt: now.toISOString(),
      lastErrorSummary: undefined,
      provider: 'openai',
      state: 'valid',
    });
  });

  it('deletes stored keys on deletion', async () => {
    const deleted: Array<{
      readonly provider: 'openai';
      readonly updatedAt: string;
      readonly userId: string;
    }> = [];
    const service = createCredentialService({
      deleteProviderCredential: async (_env, userId, provider, updatedAt) => {
        deleted.push({ provider, updatedAt, userId });
      },
      encryptSecret: async () => ({
        ciphertext: 'ciphertext',
        keyVersion: 'v1',
        nonce: 'nonce',
      }),
      findProviderCredential: async () => existingCredential,
      now: () => now,
      upsertProviderCredential: async () => {},
      validateOpenAiApiKey: async () => ({
        checkedAt: now.toISOString(),
        lastErrorSummary: null,
        state: 'valid',
      }),
    });

    await service.deleteOpenAiKey(testEnv, 'usr_01');

    expect(deleted).toEqual([
      {
        provider: 'openai',
        updatedAt: now.toISOString(),
        userId: 'usr_01',
      },
    ]);
  });
});
