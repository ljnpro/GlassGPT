import type { BackendEnv } from '../persistence/env.js';
import { decodeHex, encodeBase64Url } from './encoding.js';

const DEFAULT_REFRESH_TOKEN_BYTES = 32;

const createRefreshTokenKey = async (secretHex: string): Promise<CryptoKey> => {
  return crypto.subtle.importKey(
    'raw',
    decodeHex(secretHex),
    {
      name: 'HMAC',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );
};

export const issueRefreshToken = (): string => {
  const bytes = crypto.getRandomValues(new Uint8Array(DEFAULT_REFRESH_TOKEN_BYTES));
  return encodeBase64Url(bytes);
};

export const hashRefreshToken = async (env: BackendEnv, refreshToken: string): Promise<string> => {
  const signingKey = await createRefreshTokenKey(env.REFRESH_TOKEN_SIGNING_KEY);
  const signature = await crypto.subtle.sign(
    'HMAC',
    signingKey,
    new TextEncoder().encode(refreshToken),
  );
  return encodeBase64Url(signature);
};
