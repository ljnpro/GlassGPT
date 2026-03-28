import type { MessageRecord } from '../../domain/message-model.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface MessageRow extends MessageRecord {}

const mapMessageRow = (row: MessageRow): MessageRecord => {
  return {
    completedAt: row.completedAt,
    content: row.content,
    conversationId: row.conversationId,
    createdAt: row.createdAt,
    id: row.id,
    role: row.role,
    runId: row.runId,
    serverCursor: row.serverCursor,
  };
};

export const listMessagesForConversation = async (
  env: BackendEnv,
  conversationId: string,
): Promise<MessageRecord[]> => {
  const database = createBackendDatabase(env).raw;
  const result = await database
    .prepare(
      `SELECT id,
              conversation_id AS conversationId,
              run_id AS runId,
              role,
              content,
              created_at AS createdAt,
              completed_at AS completedAt,
              server_cursor AS serverCursor
         FROM messages
        WHERE conversation_id = ?
        ORDER BY created_at ASC, id ASC`,
    )
    .bind(conversationId)
    .all<MessageRow>();

  return result.results.map(mapMessageRow);
};

export const findUserMessageByRunId = async (
  env: BackendEnv,
  runId: string,
): Promise<MessageRecord | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              conversation_id AS conversationId,
              run_id AS runId,
              role,
              content,
              created_at AS createdAt,
              completed_at AS completedAt,
              server_cursor AS serverCursor
         FROM messages
        WHERE run_id = ?
          AND role = 'user'
        LIMIT 1`,
    )
    .bind(runId)
    .first<MessageRow>();

  return row ? mapMessageRow(row) : null;
};

export const insertMessage = async (env: BackendEnv, message: MessageRecord): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `INSERT INTO messages
         (id, conversation_id, run_id, role, content, server_cursor, created_at, completed_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      message.id,
      message.conversationId,
      message.runId,
      message.role,
      message.content,
      message.serverCursor,
      message.createdAt,
      message.completedAt,
    )
    .run();
};

export const updateMessageServerCursor = async (
  env: BackendEnv,
  messageId: string,
  serverCursor: string,
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `UPDATE messages
          SET server_cursor = ?
        WHERE id = ?`,
    )
    .bind(serverCursor, messageId)
    .run();
};
