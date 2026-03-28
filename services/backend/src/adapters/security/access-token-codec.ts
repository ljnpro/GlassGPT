import { errors as joseErrors, jwtVerify, SignJWT } from 'jose';

import { InvalidAccessTokenError } from '../../application/errors.js';
import type { BackendEnv } from '../persistence/env.js';
import { decodeHex } from './encoding.js';

const ACCESS_TOKEN_ISSUER = 'glassgpt-beta-5';
const ACCESS_TOKEN_TTL_SECONDS = 60 * 60;

export interface AccessTokenClaims {
  readonly did: string;
  readonly exp: number | undefined;
  readonly iat: number | undefined;
  readonly iss: string | undefined;
  readonly sid: string;
  readonly sub: string | undefined;
}

const createSigningKey = async (secretHex: string): Promise<CryptoKey> => {
  return crypto.subtle.importKey(
    'raw',
    decodeHex(secretHex),
    {
      name: 'HMAC',
      hash: 'SHA-256',
    },
    false,
    ['sign', 'verify'],
  );
};

export const issueAccessToken = async (
  env: BackendEnv,
  userId: string,
  sessionId: string,
  deviceId: string,
): Promise<{ expiresAt: string; token: string }> => {
  const expiresAt = new Date(Date.now() + ACCESS_TOKEN_TTL_SECONDS * 1000).toISOString();
  const signingKey = await createSigningKey(env.SESSION_SIGNING_KEY);
  const token = await new SignJWT({ sid: sessionId, did: deviceId })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer(ACCESS_TOKEN_ISSUER)
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime(`${ACCESS_TOKEN_TTL_SECONDS}s`)
    .sign(signingKey);

  return { expiresAt, token };
};

export const verifyAccessToken = async (
  env: BackendEnv,
  token: string,
): Promise<AccessTokenClaims> => {
  const signingKey = await createSigningKey(env.SESSION_SIGNING_KEY);
  let payload: Awaited<ReturnType<typeof jwtVerify>>['payload'];
  try {
    ({ payload } = await jwtVerify(token, signingKey, {
      issuer: ACCESS_TOKEN_ISSUER,
    }));
  } catch (error) {
    if (error instanceof joseErrors.JWSSignatureVerificationFailed) {
      throw new InvalidAccessTokenError('invalid_access_token_signature');
    }

    if (
      error instanceof joseErrors.JWTExpired ||
      error instanceof joseErrors.JWTClaimValidationFailed ||
      error instanceof joseErrors.JWSInvalid ||
      error instanceof joseErrors.JWTInvalid
    ) {
      throw new InvalidAccessTokenError('invalid_access_token');
    }

    throw error;
  }
  const typedPayload = payload as typeof payload & {
    readonly did?: unknown;
    readonly sid?: unknown;
  };

  const subject = typedPayload.sub;
  const sessionId = typedPayload.sid;
  const deviceId = typedPayload.did;
  if (
    typeof subject !== 'string' ||
    typeof sessionId !== 'string' ||
    typeof deviceId !== 'string' ||
    subject.length === 0 ||
    sessionId.length === 0 ||
    deviceId.length === 0
  ) {
    throw new InvalidAccessTokenError('invalid_access_token_payload');
  }

  return {
    did: deviceId,
    exp: payload.exp,
    iat: payload.iat,
    iss: payload.iss,
    sid: sessionId,
    sub: subject,
  };
};
