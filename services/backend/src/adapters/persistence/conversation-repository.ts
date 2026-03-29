import type {
  ConversationListCursor,
  ConversationListPage,
} from '../../application/conversation-list-pagination.js';
import type { ConversationRecord } from '../../domain/conversation-model.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface ConversationRow extends ConversationRecord {}

const mapConversationRow = (row: ConversationRow): ConversationRecord => {
  return {
    agentWorkerReasoningEffort: row.agentWorkerReasoningEffort ?? null,
    createdAt: row.createdAt,
    id: row.id,
    lastRunId: row.lastRunId,
    lastSyncCursor: row.lastSyncCursor,
    model: row.model ?? null,
    mode: row.mode,
    reasoningEffort: row.reasoningEffort ?? null,
    serviceTier: row.serviceTier ?? null,
    title: row.title,
    updatedAt: row.updatedAt,
    userId: row.userId,
  };
};

export const listConversationsForUser = async (
  env: BackendEnv,
  userId: string,
  input: {
    readonly cursor: ConversationListCursor | null;
    readonly limit: number;
  },
): Promise<ConversationListPage> => {
  const database = createBackendDatabase(env).raw;
  const pageSize = input.limit + 1;
  const query = input.cursor
    ? database
        .prepare(
          `SELECT id,
                  user_id AS userId,
                  title,
                  mode,
                  created_at AS createdAt,
                  updated_at AS updatedAt,
                  last_run_id AS lastRunId,
                  last_sync_cursor AS lastSyncCursor,
                  model,
                  reasoning_effort AS reasoningEffort,
                  agent_worker_reasoning_effort AS agentWorkerReasoningEffort,
                  service_tier AS serviceTier
             FROM conversations
            WHERE user_id = ?
              AND (
                updated_at < ?
                OR (updated_at = ? AND id < ?)
              )
            ORDER BY updated_at DESC, id DESC
            LIMIT ?`,
        )
        .bind(userId, input.cursor.updatedAt, input.cursor.updatedAt, input.cursor.id, pageSize)
    : database
        .prepare(
          `SELECT id,
                  user_id AS userId,
                  title,
                  mode,
                  created_at AS createdAt,
                  updated_at AS updatedAt,
                  last_run_id AS lastRunId,
                  last_sync_cursor AS lastSyncCursor,
                  model,
                  reasoning_effort AS reasoningEffort,
                  agent_worker_reasoning_effort AS agentWorkerReasoningEffort,
                  service_tier AS serviceTier
             FROM conversations
            WHERE user_id = ?
            ORDER BY updated_at DESC, id DESC
            LIMIT ?`,
        )
        .bind(userId, pageSize);
  const result = await query.all<ConversationRow>();
  const rows = result.results.map(mapConversationRow);
  const hasMore = rows.length > input.limit;
  const items = hasMore ? rows.slice(0, input.limit) : rows;
  const lastItem = items.at(-1) ?? null;

  return {
    hasMore,
    items,
    nextCursor:
      hasMore && lastItem
        ? {
            id: lastItem.id,
            updatedAt: lastItem.updatedAt,
          }
        : null,
  };
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
              last_sync_cursor AS lastSyncCursor,
              model,
              reasoning_effort AS reasoningEffort,
              agent_worker_reasoning_effort AS agentWorkerReasoningEffort,
              service_tier AS serviceTier
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
         (
           id,
           user_id,
           title,
           mode,
           created_at,
           updated_at,
           last_run_id,
           last_sync_cursor,
           model,
           reasoning_effort,
           agent_worker_reasoning_effort,
           service_tier
         )
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
      conversation.model,
      conversation.reasoningEffort,
      conversation.agentWorkerReasoningEffort,
      conversation.serviceTier,
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

export const updateConversationConfiguration = async (
  env: BackendEnv,
  input: {
    readonly conversationId: string;
    readonly model: ConversationRecord['model'];
    readonly reasoningEffort: ConversationRecord['reasoningEffort'];
    readonly agentWorkerReasoningEffort: ConversationRecord['agentWorkerReasoningEffort'];
    readonly serviceTier: ConversationRecord['serviceTier'];
    readonly updatedAt: string;
  },
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `UPDATE conversations
          SET updated_at = ?,
              model = ?,
              reasoning_effort = ?,
              agent_worker_reasoning_effort = ?,
              service_tier = ?
        WHERE id = ?`,
    )
    .bind(
      input.updatedAt,
      input.model,
      input.reasoningEffort,
      input.agentWorkerReasoningEffort,
      input.serviceTier,
      input.conversationId,
    )
    .run();
};
