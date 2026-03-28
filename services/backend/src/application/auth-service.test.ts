import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { SessionRecord, UserRecord } from './auth-records.js';
import { createAuthService } from './auth-service.js';
import { InvalidAccessTokenError, InvalidAppleIdentityTokenError } from './errors.js';
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

const userFixture: UserRecord = {
  appleSubject: 'apple_subject_01',
  createdAt: now.toISOString(),
  displayName: 'Glass User',
  email: 'glass@example.com',
  id: 'usr_01',
};

const sessionFixture: SessionRecord = {
  accessExpiresAt: new Date(now.getTime() + 60 * 60 * 1_000).toISOString(),
  createdAt: now.toISOString(),
  deviceId: 'device_01',
  id: 'ses_01',
  refreshExpiresAt: new Date(now.getTime() + 30 * 24 * 60 * 60 * 1_000).toISOString(),
  refreshTokenHash: 'hash_refresh-token',
  revokedAt: null,
  userId: userFixture.id,
};

describe('createAuthService', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('authenticates with apple and persists a fresh session', async () => {
    const insertedSessions: SessionRecord[] = [];
    const upsertInputs: Array<{ readonly displayName: string | null; readonly userId: string }> =
      [];
    vi.spyOn(globalThis.crypto, 'randomUUID')
      .mockReturnValueOnce('user_random')
      .mockReturnValueOnce('session_random');

    const service = createAuthService({
      findSessionById: async () => null,
      findSessionByRefreshTokenHash: async () => null,
      findUserById: async () => userFixture,
      hashRefreshToken: async (_env, token) => `hash_${token}`,
      insertSession: async (_env, session) => {
        insertedSessions.push(session);
      },
      issueAccessToken: async () => ({
        expiresAt: sessionFixture.accessExpiresAt,
        token: 'access-token',
      }),
      issueRefreshToken: () => 'refresh-token',
      now: () => now,
      revokeSession: async () => {},
      rotateSessionRefreshToken: async () => {},
      upsertAppleUser: async (_env, input) => {
        upsertInputs.push({ displayName: input.displayName, userId: input.userId });
        return {
          ...userFixture,
          appleSubject: input.appleSubject,
          displayName: input.displayName,
          email: input.email,
          id: input.userId,
        };
      },
      verifyAccessToken: async () => {
        throw new Error('verifyAccessToken should not be called');
      },
      verifyAppleIdentityToken: async () => ({
        email: 'glass@example.com',
        subject: 'apple_subject_01',
      }),
    });

    const session = await service.authenticateWithApple(testEnv, {
      authorizationCode: 'auth-code',
      deviceId: 'device_01',
      email: 'glass@example.com',
      familyName: 'User',
      givenName: 'Glass',
      identityToken: 'identity-token',
    });

    expect(upsertInputs).toEqual([
      {
        displayName: 'Glass User',
        userId: 'usr_user_random',
      },
    ]);
    expect(insertedSessions).toEqual([
      {
        ...sessionFixture,
        createdAt: now.toISOString(),
        deviceId: 'device_01',
        id: 'ses_session_random',
        refreshTokenHash: 'hash_refresh-token',
        userId: 'usr_user_random',
      },
    ]);
    expect(session).toMatchObject({
      accessToken: 'access-token',
      deviceId: 'device_01',
      refreshToken: 'refresh-token',
      user: {
        displayName: 'Glass User',
        id: 'usr_user_random',
      },
    });
  });

  it('refreshes an active session and rotates the refresh token', async () => {
    const rotatedSessions: Array<{
      readonly refreshTokenHash: string;
      readonly sessionId: string;
    }> = [];

    const service = createAuthService({
      findSessionById: async () => sessionFixture,
      findSessionByRefreshTokenHash: async () => sessionFixture,
      findUserById: async () => userFixture,
      hashRefreshToken: async (_env, token) => `hash_${token}`,
      insertSession: async () => {},
      issueAccessToken: async () => ({
        expiresAt: sessionFixture.accessExpiresAt,
        token: 'access-token-refreshed',
      }),
      issueRefreshToken: () => 'refresh-token-next',
      now: () => now,
      revokeSession: async () => {},
      rotateSessionRefreshToken: async (_env, input) => {
        rotatedSessions.push({
          refreshTokenHash: input.refreshTokenHash,
          sessionId: input.sessionId,
        });
      },
      upsertAppleUser: async () => userFixture,
      verifyAccessToken: async () => ({
        did: sessionFixture.deviceId,
        sid: sessionFixture.id,
        sub: sessionFixture.userId,
      }),
      verifyAppleIdentityToken: async () => {
        throw new Error('verifyAppleIdentityToken should not be called');
      },
    });

    const session = await service.refreshSession(testEnv, { refreshToken: 'refresh-token' });

    expect(rotatedSessions).toEqual([
      {
        refreshTokenHash: 'hash_refresh-token-next',
        sessionId: sessionFixture.id,
      },
    ]);
    expect(session.accessToken).toBe('access-token-refreshed');
    expect(session.refreshToken).toBe('refresh-token-next');
    expect(session.user.id).toBe(userFixture.id);
  });

  it('rejects fetchCurrentUser when the persisted session has been revoked', async () => {
    const service = createAuthService({
      findSessionById: async () => ({
        ...sessionFixture,
        revokedAt: now.toISOString(),
      }),
      findSessionByRefreshTokenHash: async () => sessionFixture,
      findUserById: async () => userFixture,
      hashRefreshToken: async () => 'hash_refresh-token',
      insertSession: async () => {},
      issueAccessToken: async () => ({
        expiresAt: sessionFixture.accessExpiresAt,
        token: 'access-token',
      }),
      issueRefreshToken: () => 'refresh-token',
      now: () => now,
      revokeSession: async () => {},
      rotateSessionRefreshToken: async () => {},
      upsertAppleUser: async () => userFixture,
      verifyAccessToken: async () => ({
        did: sessionFixture.deviceId,
        sid: sessionFixture.id,
        sub: sessionFixture.userId,
      }),
      verifyAppleIdentityToken: async () => ({
        email: userFixture.email,
        subject: userFixture.appleSubject,
      }),
    });

    await expect(service.fetchCurrentUser(testEnv, 'access-token')).rejects.toMatchObject({
      code: 'unauthorized',
      message: 'session_not_active',
      name: 'ApplicationError',
    });
  });

  it('rejects session resolution when token claims no longer match persisted state', async () => {
    const service = createAuthService({
      findSessionById: async () => sessionFixture,
      findSessionByRefreshTokenHash: async () => sessionFixture,
      findUserById: async () => userFixture,
      hashRefreshToken: async () => 'hash_refresh-token',
      insertSession: async () => {},
      issueAccessToken: async () => ({
        expiresAt: sessionFixture.accessExpiresAt,
        token: 'access-token',
      }),
      issueRefreshToken: () => 'refresh-token',
      now: () => now,
      revokeSession: async () => {},
      rotateSessionRefreshToken: async () => {},
      upsertAppleUser: async () => userFixture,
      verifyAccessToken: async () => ({
        did: 'device_mismatch',
        sid: sessionFixture.id,
        sub: sessionFixture.userId,
      }),
      verifyAppleIdentityToken: async () => ({
        email: userFixture.email,
        subject: userFixture.appleSubject,
      }),
    });

    await expect(service.resolveSession(testEnv, 'access-token')).rejects.toMatchObject({
      code: 'unauthorized',
      message: 'session_not_active',
      name: 'ApplicationError',
    });
  });

  it('maps invalid apple identity tokens to unauthorized application errors', async () => {
    const service = createAuthService({
      findSessionById: async () => null,
      findSessionByRefreshTokenHash: async () => null,
      findUserById: async () => userFixture,
      hashRefreshToken: async () => 'hash_refresh-token',
      insertSession: async () => {},
      issueAccessToken: async () => ({
        expiresAt: sessionFixture.accessExpiresAt,
        token: 'access-token',
      }),
      issueRefreshToken: () => 'refresh-token',
      now: () => now,
      revokeSession: async () => {},
      rotateSessionRefreshToken: async () => {},
      upsertAppleUser: async () => userFixture,
      verifyAccessToken: async () => ({
        did: sessionFixture.deviceId,
        sid: sessionFixture.id,
        sub: sessionFixture.userId,
      }),
      verifyAppleIdentityToken: async () => {
        throw new InvalidAppleIdentityTokenError('invalid_apple_identity_token');
      },
    });

    await expect(
      service.authenticateWithApple(testEnv, {
        authorizationCode: 'auth-code',
        deviceId: 'device_01',
        email: 'glass@example.com',
        familyName: 'User',
        givenName: 'Glass',
        identityToken: 'identity-token',
      }),
    ).rejects.toMatchObject({
      code: 'unauthorized',
      message: 'invalid_apple_identity_token',
      name: 'ApplicationError',
    });
  });

  it('maps invalid access tokens to unauthorized application errors', async () => {
    const service = createAuthService({
      findSessionById: async () => sessionFixture,
      findSessionByRefreshTokenHash: async () => sessionFixture,
      findUserById: async () => userFixture,
      hashRefreshToken: async () => 'hash_refresh-token',
      insertSession: async () => {},
      issueAccessToken: async () => ({
        expiresAt: sessionFixture.accessExpiresAt,
        token: 'access-token',
      }),
      issueRefreshToken: () => 'refresh-token',
      now: () => now,
      revokeSession: async () => {},
      rotateSessionRefreshToken: async () => {},
      upsertAppleUser: async () => userFixture,
      verifyAccessToken: async () => {
        throw new InvalidAccessTokenError('invalid_access_token');
      },
      verifyAppleIdentityToken: async () => ({
        email: userFixture.email,
        subject: userFixture.appleSubject,
      }),
    });

    await expect(service.fetchCurrentUser(testEnv, 'access-token')).rejects.toMatchObject({
      code: 'unauthorized',
      message: 'invalid_access_token',
      name: 'ApplicationError',
    });
  });
});
