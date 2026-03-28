import type { BackendEnv } from '../persistence/env.js';
import { decodeBase64Url, decodeHex, encodeBase64Url } from './encoding.js';

const AES_NONCE_BYTES = 12;
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

const createEncryptionKey = async (secretHex: string): Promise<CryptoKey> => {
  return crypto.subtle.importKey('raw', decodeHex(secretHex), 'AES-GCM', false, [
    'encrypt',
    'decrypt',
  ]);
};

export interface EncryptedSecret {
  readonly ciphertext: string;
  readonly keyVersion: string;
  readonly nonce: string;
}

const createKeyRing = (env: BackendEnv): Map<string, string> => {
  const keyRing = new Map<string, string>([
    [env.CREDENTIAL_ENCRYPTION_KEY_VERSION, env.CREDENTIAL_ENCRYPTION_KEY],
  ]);

  const serializedKeyRing = env.CREDENTIAL_ENCRYPTION_KEYS_JSON;
  if (!serializedKeyRing) {
    return keyRing;
  }

  const parsed = JSON.parse(serializedKeyRing) as unknown;
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('credential_key_ring_invalid');
  }

  for (const [version, secret] of Object.entries(parsed)) {
    if (typeof version !== 'string' || version.length === 0) {
      throw new Error('credential_key_ring_invalid_version');
    }

    if (typeof secret !== 'string' || secret.length === 0) {
      throw new Error('credential_key_ring_invalid_secret');
    }

    keyRing.set(version, secret);
  }

  return keyRing;
};

const resolveDecryptionSecretHex = (env: BackendEnv, keyVersion: string): string => {
  const secretHex = createKeyRing(env).get(keyVersion);
  if (!secretHex) {
    throw new Error('credential_key_version_unavailable');
  }

  return secretHex;
};

export const encryptSecret = async (env: BackendEnv, secret: string): Promise<EncryptedSecret> => {
  const nonce = crypto.getRandomValues(new Uint8Array(AES_NONCE_BYTES));
  const key = await createEncryptionKey(env.CREDENTIAL_ENCRYPTION_KEY);
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce },
    key,
    textEncoder.encode(secret),
  );

  return {
    ciphertext: encodeBase64Url(ciphertext),
    keyVersion: env.CREDENTIAL_ENCRYPTION_KEY_VERSION,
    nonce: encodeBase64Url(nonce),
  };
};

export const decryptSecret = async (
  env: BackendEnv,
  encrypted: EncryptedSecret,
): Promise<string> => {
  const key = await createEncryptionKey(resolveDecryptionSecretHex(env, encrypted.keyVersion));
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: decodeBase64Url(encrypted.nonce) },
    key,
    decodeBase64Url(encrypted.ciphertext),
  );
  return textDecoder.decode(plaintext);
};
