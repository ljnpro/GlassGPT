import { describe, expect, it } from 'vitest';

import { decryptSecret, encryptSecret } from './credential-encryption.js';

const currentKey = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const previousKey = 'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';

const testEnv = {
  AGENT_RUN_WORKFLOW: {} as Workflow<unknown>,
  APPLE_AUDIENCE: 'com.glassgpt.app',
  APPLE_BUNDLE_ID: 'com.glassgpt.app',
  APP_ENV: 'beta',
  CHAT_RUN_WORKFLOW: {} as Workflow<unknown>,
  CONVERSATION_EVENT_HUB: {} as DurableObjectNamespace,
  CREDENTIAL_ENCRYPTION_KEY: currentKey,
  CREDENTIAL_ENCRYPTION_KEYS_JSON: JSON.stringify({ v1: previousKey }),
  CREDENTIAL_ENCRYPTION_KEY_VERSION: 'v2',
  GLASSGPT_ARTIFACTS: {} as R2Bucket,
  GLASSGPT_DB: {} as D1Database,
  R2_BUCKET_NAME: 'glassgpt-beta-artifacts',
  REFRESH_TOKEN_SIGNING_KEY: '11',
  SESSION_SIGNING_KEY: '22',
};

describe('credential encryption', () => {
  it('decrypts payloads encrypted with the current key version', async () => {
    const encrypted = await encryptSecret(testEnv, 'sk-live-current');

    await expect(decryptSecret(testEnv, encrypted)).resolves.toBe('sk-live-current');
  });

  it('decrypts payloads encrypted with an older configured key version', async () => {
    const legacyEnv = {
      ...testEnv,
      CREDENTIAL_ENCRYPTION_KEY: previousKey,
      CREDENTIAL_ENCRYPTION_KEYS_JSON: undefined,
      CREDENTIAL_ENCRYPTION_KEY_VERSION: 'v1',
    };
    const encrypted = await encryptSecret(legacyEnv, 'sk-live-legacy');

    await expect(decryptSecret(testEnv, encrypted)).resolves.toBe('sk-live-legacy');
  });

  it('fails when the requested key version is not configured', async () => {
    await expect(
      decryptSecret(testEnv, {
        ciphertext: 'ciphertext',
        keyVersion: 'v3',
        nonce: 'nonce',
      }),
    ).rejects.toThrowError('credential_key_version_unavailable');
  });
});
