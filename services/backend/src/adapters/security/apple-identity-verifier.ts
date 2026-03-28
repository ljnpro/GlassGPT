import { createRemoteJWKSet, errors as joseErrors, jwtVerify } from 'jose';

import { InvalidAppleIdentityTokenError } from '../../application/errors.js';
import type { BackendEnv } from '../persistence/env.js';

const APPLE_ISSUER = 'https://appleid.apple.com';
const appleJwks = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`));

export interface VerifiedAppleIdentity {
  readonly email: string | null;
  readonly subject: string;
}

export const verifyAppleIdentityToken = async (
  env: BackendEnv,
  identityToken: string,
): Promise<VerifiedAppleIdentity> => {
  let payload: Awaited<ReturnType<typeof jwtVerify>>['payload'];
  try {
    ({ payload } = await jwtVerify(identityToken, appleJwks, {
      audience: env.APPLE_AUDIENCE,
      issuer: APPLE_ISSUER,
    }));
  } catch (error) {
    if (
      error instanceof joseErrors.JWSSignatureVerificationFailed ||
      error instanceof joseErrors.JWTExpired ||
      error instanceof joseErrors.JWTClaimValidationFailed ||
      error instanceof joseErrors.JWSInvalid ||
      error instanceof joseErrors.JWTInvalid
    ) {
      throw new InvalidAppleIdentityTokenError('invalid_apple_identity_token');
    }

    throw error;
  }
  const typedPayload = payload as typeof payload & {
    readonly email?: unknown;
  };

  const subject = typedPayload.sub;
  if (typeof subject !== 'string' || subject.length === 0) {
    throw new InvalidAppleIdentityTokenError('apple_subject_missing');
  }

  const emailClaim = typedPayload.email;
  const email = typeof emailClaim === 'string' && emailClaim.length > 0 ? emailClaim : null;

  return { email, subject };
};
