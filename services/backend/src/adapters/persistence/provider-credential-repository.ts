import type { ProviderCredentialRecord } from '../../application/auth-records.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface ProviderCredentialRow extends ProviderCredentialRecord {}

const mapProviderCredentialRow = (row: ProviderCredentialRow): ProviderCredentialRecord => {
  return {
    checkedAt: row.checkedAt,
    ciphertext: row.ciphertext,
    createdAt: row.createdAt,
    id: row.id,
    keyVersion: row.keyVersion,
    lastErrorSummary: row.lastErrorSummary,
    nonce: row.nonce,
    provider: row.provider,
    status: row.status,
    updatedAt: row.updatedAt,
    userId: row.userId,
  };
};

export const findProviderCredential = async (
  env: BackendEnv,
  userId: string,
  provider: 'openai',
): Promise<ProviderCredentialRecord | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              user_id AS userId,
              provider,
              ciphertext,
              nonce,
              key_version AS keyVersion,
              status,
              checked_at AS checkedAt,
              last_error_summary AS lastErrorSummary,
              created_at AS createdAt,
              updated_at AS updatedAt
         FROM provider_credentials
        WHERE user_id = ?
          AND provider = ?
        LIMIT 1`,
    )
    .bind(userId, provider)
    .first<ProviderCredentialRow>();

  return row ? mapProviderCredentialRow(row) : null;
};

export const deleteProviderCredential = async (
  env: BackendEnv,
  userId: string,
  provider: 'openai',
  _updatedAt: string,
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `DELETE FROM provider_credentials
        WHERE user_id = ?
          AND provider = ?`,
    )
    .bind(userId, provider)
    .run();
};

export const upsertProviderCredential = async (
  env: BackendEnv,
  credential: ProviderCredentialRecord,
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `INSERT INTO provider_credentials
         (id, user_id, provider, ciphertext, nonce, key_version, status, checked_at, last_error_summary, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, provider) DO UPDATE SET
         ciphertext = excluded.ciphertext,
         nonce = excluded.nonce,
         key_version = excluded.key_version,
         status = excluded.status,
         checked_at = excluded.checked_at,
         last_error_summary = excluded.last_error_summary,
         updated_at = excluded.updated_at`,
    )
    .bind(
      credential.id,
      credential.userId,
      credential.provider,
      credential.ciphertext,
      credential.nonce,
      credential.keyVersion,
      credential.status,
      credential.checkedAt,
      credential.lastErrorSummary,
      credential.createdAt,
      credential.updatedAt,
    )
    .run();
};
