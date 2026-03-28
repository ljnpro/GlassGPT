import type { ConversationRecord } from '../../domain/conversation-model.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface ConversationRow extends ConversationRecord {}

const mapConversationRow = (row: ConversationRow): ConversationRecord => {
  return {
    createdAt: row.createdAt,
    id: row.id,
    lastRunId: row.lastRunId,
    lastSyncCursor: row.lastSyncCursor,
    mode: row.mode,
    title: row.title,
    updatedAt: row.updatedAt,
    userId: row.userId,
  };
};

export const listConversationsForUser = async (
  env: BackendEnv,
  userId: string,
): Promise<ConversationRecord[]> => {
  const database = createBackendDatabase(env).raw;
  const result = await database
    .prepare(
      `SELECT id,
              user_id AS userId,
              title,
              mode,
              created_at AS createdAt,
              updated_at AS updatedAt,
              last_run_id AS lastRunId,
              last_sync_cursor AS lastSyncCursor
         FROM conversations
        WHERE user_id = ?
        ORDER BY updated_at DESC, created_at DESC`,
    )
    .bind(userId)
    .all<ConversationRow>();

  return result.results.map(mapConversationRow);
};

export const findConversationByIdForUser = async (
  env: BackendEnv,
  conversationId: string,
  userId: string,
): Promise<ConversationRecord | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              user_id AS userId,
              title,
              mode,
              created_at AS createdAt,
              updated_at AS updatedAt,
              last_run_id AS lastRunId,
              last_sync_cursor AS lastSyncCursor
         FROM conversations
        WHERE id = ?
          AND user_id = ?
        LIMIT 1`,
    )
    .bind(conversationId, userId)
    .first<ConversationRow>();

  return row ? mapConversationRow(row) : null;
};

export const insertConversation = async (
  env: BackendEnv,
  conversation: ConversationRecord,
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `INSERT INTO conversations
         (id, user_id, title, mode, created_at, updated_at, last_run_id, last_sync_cursor)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      conversation.id,
      conversation.userId,
      conversation.title,
      conversation.mode,
      conversation.createdAt,
      conversation.updatedAt,
      conversation.lastRunId,
      conversation.lastSyncCursor,
    )
    .run();
};

export const updateConversationPointers = async (
  env: BackendEnv,
  input: {
    readonly conversationId: string;
    readonly lastRunId: string | null;
    readonly lastSyncCursor: string | null;
    readonly updatedAt: string;
  },
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `UPDATE conversations
          SET updated_at = ?,
              last_run_id = ?,
              last_sync_cursor = ?
        WHERE id = ?`,
    )
    .bind(input.updatedAt, input.lastRunId, input.lastSyncCursor, input.conversationId)
    .run();
};
