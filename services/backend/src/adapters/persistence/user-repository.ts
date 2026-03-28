import type { UserRecord } from '../../application/auth-records.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface UserRow extends UserRecord {}

const mapUserRow = (row: UserRow): UserRecord => {
  return {
    appleSubject: row.appleSubject,
    createdAt: row.createdAt,
    displayName: row.displayName,
    email: row.email,
    id: row.id,
  };
};

export const findUserById = async (env: BackendEnv, userId: string): Promise<UserRecord | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              apple_subject AS appleSubject,
              display_name AS displayName,
              email,
              created_at AS createdAt
         FROM users
        WHERE id = ?
        LIMIT 1`,
    )
    .bind(userId)
    .first<UserRow>();

  return row ? mapUserRow(row) : null;
};

export const upsertAppleUser = async (
  env: BackendEnv,
  input: {
    readonly appleSubject: string;
    readonly displayName: string | null;
    readonly email: string | null;
    readonly timestamp: string;
    readonly userId: string;
  },
): Promise<UserRecord> => {
  const database = createBackendDatabase(env).raw;
  const existing = await database
    .prepare(
      `SELECT id,
              apple_subject AS appleSubject,
              display_name AS displayName,
              email,
              created_at AS createdAt
         FROM users
        WHERE apple_subject = ?
        LIMIT 1`,
    )
    .bind(input.appleSubject)
    .first<UserRow>();

  if (existing) {
    const nextDisplayName = input.displayName ?? existing.displayName;
    const nextEmail = input.email ?? existing.email;
    await database
      .prepare(
        `UPDATE users
            SET display_name = ?,
                email = ?,
                updated_at = ?
          WHERE id = ?`,
      )
      .bind(nextDisplayName, nextEmail, input.timestamp, existing.id)
      .run();

    return {
      appleSubject: existing.appleSubject,
      createdAt: existing.createdAt,
      displayName: nextDisplayName,
      email: nextEmail,
      id: existing.id,
    };
  }

  await database
    .prepare(
      `INSERT INTO users (id, apple_subject, display_name, email, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      input.userId,
      input.appleSubject,
      input.displayName,
      input.email,
      input.timestamp,
      input.timestamp,
    )
    .run();

  return {
    appleSubject: input.appleSubject,
    createdAt: input.timestamp,
    displayName: input.displayName,
    email: input.email,
    id: input.userId,
  };
};
