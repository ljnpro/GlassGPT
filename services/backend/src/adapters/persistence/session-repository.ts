import type { SessionRecord } from '../../application/auth-records.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface SessionRow extends SessionRecord {}

const mapSessionRow = (row: SessionRow): SessionRecord => {
  return {
    accessExpiresAt: row.accessExpiresAt,
    createdAt: row.createdAt,
    deviceId: row.deviceId,
    id: row.id,
    refreshExpiresAt: row.refreshExpiresAt,
    refreshTokenHash: row.refreshTokenHash,
    revokedAt: row.revokedAt,
    userId: row.userId,
  };
};

export const findSessionById = async (
  env: BackendEnv,
  sessionId: string,
): Promise<SessionRecord | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              user_id AS userId,
              device_id AS deviceId,
              refresh_token_hash AS refreshTokenHash,
              access_expires_at AS accessExpiresAt,
              refresh_expires_at AS refreshExpiresAt,
              created_at AS createdAt,
              revoked_at AS revokedAt
         FROM sessions
        WHERE id = ?
        LIMIT 1`,
    )
    .bind(sessionId)
    .first<SessionRow>();

  return row ? mapSessionRow(row) : null;
};

export const findSessionByRefreshTokenHash = async (
  env: BackendEnv,
  refreshTokenHash: string,
): Promise<SessionRecord | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              user_id AS userId,
              device_id AS deviceId,
              refresh_token_hash AS refreshTokenHash,
              access_expires_at AS accessExpiresAt,
              refresh_expires_at AS refreshExpiresAt,
              created_at AS createdAt,
              revoked_at AS revokedAt
         FROM sessions
        WHERE refresh_token_hash = ?
        LIMIT 1`,
    )
    .bind(refreshTokenHash)
    .first<SessionRow>();

  return row ? mapSessionRow(row) : null;
};

export const insertSession = async (env: BackendEnv, session: SessionRecord): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `INSERT INTO sessions
         (id, user_id, device_id, refresh_token_hash, access_expires_at, refresh_expires_at, created_at, revoked_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      session.id,
      session.userId,
      session.deviceId,
      session.refreshTokenHash,
      session.accessExpiresAt,
      session.refreshExpiresAt,
      session.createdAt,
      session.revokedAt,
    )
    .run();
};

export const revokeSession = async (
  env: BackendEnv,
  sessionId: string,
  revokedAt: string,
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare('UPDATE sessions SET revoked_at = ? WHERE id = ?')
    .bind(revokedAt, sessionId)
    .run();
};

export const rotateSessionRefreshToken = async (
  env: BackendEnv,
  input: {
    readonly accessExpiresAt: string;
    readonly refreshExpiresAt: string;
    readonly refreshTokenHash: string;
    readonly sessionId: string;
  },
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `UPDATE sessions
          SET refresh_token_hash = ?,
              access_expires_at = ?,
              refresh_expires_at = ?,
              revoked_at = NULL
        WHERE id = ?`,
    )
    .bind(input.refreshTokenHash, input.accessExpiresAt, input.refreshExpiresAt, input.sessionId)
    .run();
};
