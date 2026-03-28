import type {
  AppleAuthRequestDTO,
  RefreshSessionRequestDTO,
  SessionDTO,
  UserDTO,
} from '@glassgpt/backend-contracts';
import type { SessionRecord, UserRecord } from './auth-records.js';
import {
  ApplicationError,
  InvalidAccessTokenError,
  InvalidAppleIdentityTokenError,
} from './errors.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const REFRESH_TOKEN_TTL_DAYS = 30;

interface VerifiedAppleIdentity {
  readonly email: string | null;
  readonly subject: string;
}

interface AccessTokenResult {
  readonly expiresAt: string;
  readonly token: string;
}

interface AccessTokenClaims {
  readonly did: string;
  readonly sid: string;
  readonly sub: string | undefined;
}

const buildUserDTO = (user: UserRecord): UserDTO => {
  return {
    appleSubject: user.appleSubject,
    createdAt: user.createdAt,
    displayName: user.displayName === null ? undefined : user.displayName,
    email: user.email === null ? undefined : user.email,
    id: user.id,
  };
};

const buildSessionDTO = (
  user: UserRecord,
  accessToken: AccessTokenResult,
  refreshToken: string,
  deviceId: string,
): SessionDTO => {
  return {
    accessToken: accessToken.token,
    deviceId,
    expiresAt: accessToken.expiresAt,
    refreshToken,
    user: buildUserDTO(user),
  };
};

const buildDisplayName = (
  givenName: string | null | undefined,
  familyName: string | null | undefined,
): string | null => {
  const parts = [givenName, familyName].filter((part): part is string =>
    Boolean(part && part.length > 0),
  );
  return parts.length > 0 ? parts.join(' ') : null;
};

const isExpired = (timestamp: string, now: Date): boolean => {
  return Date.parse(timestamp) <= now.getTime();
};

const requireActiveSession = (session: SessionRecord | null, now: Date): SessionRecord => {
  if (!session || session.revokedAt || isExpired(session.refreshExpiresAt, now)) {
    throw new ApplicationError('unauthorized', 'session_not_available');
  }

  return session;
};

const requireSessionUser = (user: UserRecord | null): UserRecord => {
  if (!user) {
    throw new ApplicationError('unauthorized', 'user_not_found');
  }

  return user;
};

const toUnauthorizedApplicationError = (
  error: unknown,
  fallbackMessage: string,
): ApplicationError => {
  if (error instanceof ApplicationError) {
    return error;
  }

  if (error instanceof InvalidAccessTokenError || error instanceof InvalidAppleIdentityTokenError) {
    return new ApplicationError('unauthorized', error.message);
  }

  return new ApplicationError('unauthorized', fallbackMessage);
};

export interface AuthServiceDependencies {
  readonly findSessionById: (
    env: BackendRuntimeContext,
    sessionId: string,
  ) => Promise<SessionRecord | null>;
  readonly findSessionByRefreshTokenHash: (
    env: BackendRuntimeContext,
    refreshTokenHash: string,
  ) => Promise<SessionRecord | null>;
  readonly findUserById: (env: BackendRuntimeContext, userId: string) => Promise<UserRecord | null>;
  readonly hashRefreshToken: (env: BackendRuntimeContext, refreshToken: string) => Promise<string>;
  readonly insertSession: (env: BackendRuntimeContext, session: SessionRecord) => Promise<void>;
  readonly issueAccessToken: (
    env: BackendRuntimeContext,
    userId: string,
    sessionId: string,
    deviceId: string,
  ) => Promise<AccessTokenResult>;
  readonly issueRefreshToken: () => string;
  readonly now: () => Date;
  readonly revokeSession: (
    env: BackendRuntimeContext,
    sessionId: string,
    revokedAt: string,
  ) => Promise<void>;
  readonly rotateSessionRefreshToken: (
    env: BackendRuntimeContext,
    input: {
      readonly accessExpiresAt: string;
      readonly refreshExpiresAt: string;
      readonly refreshTokenHash: string;
      readonly sessionId: string;
    },
  ) => Promise<void>;
  readonly upsertAppleUser: (
    env: BackendRuntimeContext,
    input: {
      readonly appleSubject: string;
      readonly displayName: string | null;
      readonly email: string | null;
      readonly timestamp: string;
      readonly userId: string;
    },
  ) => Promise<UserRecord>;
  readonly verifyAccessToken: (
    env: BackendRuntimeContext,
    accessToken: string,
  ) => Promise<AccessTokenClaims>;
  readonly verifyAppleIdentityToken: (
    env: BackendRuntimeContext,
    identityToken: string,
  ) => Promise<VerifiedAppleIdentity>;
}

export interface AuthService {
  authenticateWithApple(
    env: BackendRuntimeContext,
    input: AppleAuthRequestDTO,
  ): Promise<SessionDTO>;
  fetchCurrentUser(env: BackendRuntimeContext, accessToken: string): Promise<UserDTO>;
  logout(env: BackendRuntimeContext, accessToken: string): Promise<void>;
  refreshSession(env: BackendRuntimeContext, input: RefreshSessionRequestDTO): Promise<SessionDTO>;
  resolveSession(
    env: BackendRuntimeContext,
    accessToken: string,
  ): Promise<{ deviceId: string; sessionId: string; user: UserDTO; userId: string }>;
}

export const createAuthService = (deps: AuthServiceDependencies): AuthService => {
  return {
    authenticateWithApple: async (env, input) => {
      const timestamp = deps.now().toISOString();
      let identity: VerifiedAppleIdentity;
      try {
        identity = await deps.verifyAppleIdentityToken(env, input.identityToken);
      } catch (error) {
        throw toUnauthorizedApplicationError(error, 'invalid_apple_identity_token');
      }
      const user = await deps.upsertAppleUser(env, {
        appleSubject: identity.subject,
        displayName: buildDisplayName(input.givenName, input.familyName),
        email: input.email ?? identity.email,
        timestamp,
        userId: `usr_${crypto.randomUUID()}`,
      });

      const refreshToken = deps.issueRefreshToken();
      const refreshTokenHash = await deps.hashRefreshToken(env, refreshToken);
      const sessionId = `ses_${crypto.randomUUID()}`;
      const accessToken = await deps.issueAccessToken(env, user.id, sessionId, input.deviceId);
      const refreshExpiresAt = new Date(
        deps.now().getTime() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000,
      ).toISOString();

      await deps.insertSession(env, {
        accessExpiresAt: accessToken.expiresAt,
        createdAt: timestamp,
        deviceId: input.deviceId,
        id: sessionId,
        refreshExpiresAt,
        refreshTokenHash,
        revokedAt: null,
        userId: user.id,
      });

      return buildSessionDTO(user, accessToken, refreshToken, input.deviceId);
    },

    fetchCurrentUser: async (env, accessToken) => {
      let session: AccessTokenClaims;
      try {
        session = await deps.verifyAccessToken(env, accessToken);
      } catch (error) {
        throw toUnauthorizedApplicationError(error, 'invalid_access_token');
      }
      const subject = session.sub;
      if (typeof subject !== 'string' || subject.length === 0) {
        throw new ApplicationError('unauthorized', 'access_token_missing_subject');
      }

      const persistedSession = await deps.findSessionById(env, session.sid);
      if (
        !persistedSession ||
        persistedSession.revokedAt ||
        persistedSession.userId !== subject ||
        persistedSession.deviceId !== session.did ||
        isExpired(persistedSession.accessExpiresAt, deps.now())
      ) {
        throw new ApplicationError('unauthorized', 'session_not_active');
      }

      const user = requireSessionUser(await deps.findUserById(env, subject));
      return buildUserDTO(user);
    },

    logout: async (env, accessToken) => {
      let session: AccessTokenClaims;
      try {
        session = await deps.verifyAccessToken(env, accessToken);
      } catch (error) {
        throw toUnauthorizedApplicationError(error, 'invalid_access_token');
      }
      await deps.revokeSession(env, session.sid, deps.now().toISOString());
    },

    refreshSession: async (env, input) => {
      const now = deps.now();
      const refreshTokenHash = await deps.hashRefreshToken(env, input.refreshToken);
      const session = requireActiveSession(
        await deps.findSessionByRefreshTokenHash(env, refreshTokenHash),
        now,
      );
      const user = requireSessionUser(await deps.findUserById(env, session.userId));

      const nextRefreshToken = deps.issueRefreshToken();
      const nextRefreshTokenHash = await deps.hashRefreshToken(env, nextRefreshToken);
      const accessToken = await deps.issueAccessToken(env, user.id, session.id, session.deviceId);
      const refreshExpiresAt = new Date(
        now.getTime() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000,
      ).toISOString();

      await deps.rotateSessionRefreshToken(env, {
        accessExpiresAt: accessToken.expiresAt,
        refreshExpiresAt,
        refreshTokenHash: nextRefreshTokenHash,
        sessionId: session.id,
      });

      return buildSessionDTO(user, accessToken, nextRefreshToken, session.deviceId);
    },

    resolveSession: async (env, accessToken) => {
      const now = deps.now();
      let token: AccessTokenClaims;
      try {
        token = await deps.verifyAccessToken(env, accessToken);
      } catch (error) {
        throw toUnauthorizedApplicationError(error, 'invalid_access_token');
      }
      const subject = token.sub;
      if (typeof subject !== 'string' || subject.length === 0) {
        throw new ApplicationError('unauthorized', 'access_token_missing_subject');
      }

      const session = await deps.findSessionById(env, token.sid);
      if (
        !session ||
        session.revokedAt ||
        session.userId !== subject ||
        session.deviceId !== token.did ||
        isExpired(session.accessExpiresAt, now)
      ) {
        throw new ApplicationError('unauthorized', 'session_not_active');
      }

      const user = requireSessionUser(await deps.findUserById(env, subject));

      return {
        deviceId: session.deviceId,
        sessionId: session.id,
        user: buildUserDTO(user),
        userId: user.id,
      };
    },
  };
};
