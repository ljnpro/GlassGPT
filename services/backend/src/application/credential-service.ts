import type { CredentialStatusDTO } from '@glassgpt/backend-contracts';

import type { ProviderCredentialRecord } from './auth-records.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const buildCredentialStatusDTO = (
  status: ProviderCredentialRecord['status'],
  checkedAt: string | null,
  lastErrorSummary: string | null,
): CredentialStatusDTO => {
  return {
    checkedAt: checkedAt ?? undefined,
    lastErrorSummary: lastErrorSummary ?? undefined,
    provider: 'openai',
    state: status,
  };
};

interface EncryptedSecret {
  readonly ciphertext: string;
  readonly keyVersion: string;
  readonly nonce: string;
}

interface OpenAiKeyValidationResult {
  readonly checkedAt: string;
  readonly lastErrorSummary: string | null;
  readonly state: 'invalid' | 'valid';
}

export interface CredentialServiceDependencies {
  readonly encryptSecret: (env: BackendRuntimeContext, secret: string) => Promise<EncryptedSecret>;
  readonly findProviderCredential: (
    env: BackendRuntimeContext,
    userId: string,
    provider: 'openai',
  ) => Promise<ProviderCredentialRecord | null>;
  readonly now: () => Date;
  readonly deleteProviderCredential: (
    env: BackendRuntimeContext,
    userId: string,
    provider: 'openai',
    updatedAt: string,
  ) => Promise<void>;
  readonly upsertProviderCredential: (
    env: BackendRuntimeContext,
    credential: ProviderCredentialRecord,
  ) => Promise<void>;
  readonly validateOpenAiApiKey: (apiKey: string) => Promise<OpenAiKeyValidationResult>;
}

export interface CredentialService {
  deleteOpenAiKey(env: BackendRuntimeContext, userId: string): Promise<void>;
  readOpenAiKeyStatus(env: BackendRuntimeContext, userId: string): Promise<CredentialStatusDTO>;
  storeOpenAiKey(
    env: BackendRuntimeContext,
    userId: string,
    apiKey: string,
  ): Promise<CredentialStatusDTO>;
}

export const createCredentialService = (deps: CredentialServiceDependencies): CredentialService => {
  return {
    deleteOpenAiKey: async (env, userId) => {
      await deps.deleteProviderCredential(env, userId, 'openai', deps.now().toISOString());
    },

    readOpenAiKeyStatus: async (env, userId) => {
      const credential = await deps.findProviderCredential(env, userId, 'openai');
      if (!credential) {
        return buildCredentialStatusDTO('missing', null, null);
      }

      return buildCredentialStatusDTO(
        credential.status,
        credential.checkedAt,
        credential.lastErrorSummary,
      );
    },

    storeOpenAiKey: async (env, userId, apiKey) => {
      const timestamp = deps.now().toISOString();
      const validation = await deps.validateOpenAiApiKey(apiKey);
      const encrypted = await deps.encryptSecret(env, apiKey);
      const existing = await deps.findProviderCredential(env, userId, 'openai');

      await deps.upsertProviderCredential(env, {
        checkedAt: validation.checkedAt,
        ciphertext: encrypted.ciphertext,
        createdAt: existing?.createdAt ?? timestamp,
        id: existing?.id ?? `cred_${crypto.randomUUID()}`,
        keyVersion: encrypted.keyVersion,
        lastErrorSummary: validation.lastErrorSummary,
        nonce: encrypted.nonce,
        provider: 'openai',
        status: validation.state,
        updatedAt: timestamp,
        userId,
      });

      return buildCredentialStatusDTO(
        validation.state,
        validation.checkedAt,
        validation.lastErrorSummary,
      );
    },
  };
};
