import type { ProviderCredentialRecord } from './auth-records.js';
import { ApplicationError } from './errors.js';
import type { BackendRuntimeContext } from './runtime-context.js';

export interface FileProxySupportDependencies {
  readonly decryptSecret: (
    env: BackendRuntimeContext,
    encrypted: {
      readonly ciphertext: string;
      readonly keyVersion: string;
      readonly nonce: string;
    },
  ) => Promise<string>;
  readonly findProviderCredential: (
    env: BackendRuntimeContext,
    userId: string,
    provider: 'openai',
  ) => Promise<ProviderCredentialRecord | null>;
}

export const createFileProxySupport = (deps: FileProxySupportDependencies) => ({
  loadApiKey: async (env: BackendRuntimeContext, userId: string): Promise<string> => {
    const credential = await deps.findProviderCredential(env, userId, 'openai');
    if (!credential || credential.status !== 'valid') {
      throw new ApplicationError('forbidden', 'openai_credential_unavailable');
    }
    return deps.decryptSecret(env, credential);
  },
});

export type FileProxySupport = ReturnType<typeof createFileProxySupport>;
