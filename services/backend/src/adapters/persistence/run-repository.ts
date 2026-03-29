import type { RunRecord } from '../../domain/run-model.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface RunRow extends RunRecord {}

const mapRunRow = (row: RunRow): RunRecord => {
  return {
    conversationId: row.conversationId,
    createdAt: row.createdAt,
    id: row.id,
    kind: row.kind,
    lastEventCursor: row.lastEventCursor,
    processSnapshotJSON: row.processSnapshotJSON,
    stage: row.stage,
    status: row.status,
    updatedAt: row.updatedAt,
    userId: row.userId,
    visibleSummary: row.visibleSummary,
  };
};

export const findRunById = async (env: BackendEnv, runId: string): Promise<RunRecord | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              conversation_id AS conversationId,
              user_id AS userId,
              kind,
              status,
              stage,
              visible_summary AS visibleSummary,
              process_snapshot_json AS processSnapshotJSON,
              created_at AS createdAt,
              updated_at AS updatedAt,
              last_event_cursor AS lastEventCursor
         FROM runs
        WHERE id = ?
        LIMIT 1`,
    )
    .bind(runId)
    .first<RunRow>();

  return row ? mapRunRow(row) : null;
};

export const findRunByIdForUser = async (
  env: BackendEnv,
  runId: string,
  userId: string,
): Promise<RunRecord | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              conversation_id AS conversationId,
              user_id AS userId,
              kind,
              status,
              stage,
              visible_summary AS visibleSummary,
              process_snapshot_json AS processSnapshotJSON,
              created_at AS createdAt,
              updated_at AS updatedAt,
              last_event_cursor AS lastEventCursor
         FROM runs
        WHERE id = ?
          AND user_id = ?
        LIMIT 1`,
    )
    .bind(runId, userId)
    .first<RunRow>();

  return row ? mapRunRow(row) : null;
};

export interface RunStreamProjection {
  readonly conversationId: string;
  readonly id: string;
  readonly processSnapshotJSON: string | null;
  readonly stage: string | null;
  readonly status: string;
  readonly visibleSummary: string | null;
}

export const findRunStreamProjection = async (
  env: BackendEnv,
  runId: string,
  userId: string,
): Promise<RunStreamProjection | null> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT id,
              conversation_id AS conversationId,
              status,
              stage,
              visible_summary AS visibleSummary,
              process_snapshot_json AS processSnapshotJSON
         FROM runs
        WHERE id = ?
          AND user_id = ?
        LIMIT 1`,
    )
    .bind(runId, userId)
    .first<RunStreamProjection>();

  return row ?? null;
};

export const listRunsForConversation = async (
  env: BackendEnv,
  conversationId: string,
): Promise<RunRecord[]> => {
  const database = createBackendDatabase(env).raw;
  const result = await database
    .prepare(
      `SELECT id,
              conversation_id AS conversationId,
              user_id AS userId,
              kind,
              status,
              stage,
              visible_summary AS visibleSummary,
              process_snapshot_json AS processSnapshotJSON,
              created_at AS createdAt,
              updated_at AS updatedAt,
              last_event_cursor AS lastEventCursor
         FROM runs
        WHERE conversation_id = ?
        ORDER BY created_at ASC, id ASC`,
    )
    .bind(conversationId)
    .all<RunRow>();

  return result.results.map(mapRunRow);
};

export const insertRun = async (env: BackendEnv, run: RunRecord): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `INSERT INTO runs
         (
           id,
           conversation_id,
           user_id,
           kind,
           status,
           stage,
           visible_summary,
           process_snapshot_json,
           created_at,
           updated_at,
           last_event_cursor
         )
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      run.id,
      run.conversationId,
      run.userId,
      run.kind,
      run.status,
      run.stage,
      run.visibleSummary,
      run.processSnapshotJSON,
      run.createdAt,
      run.updatedAt,
      run.lastEventCursor,
    )
    .run();
};

export const updateRun = async (env: BackendEnv, run: RunRecord): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `UPDATE runs
          SET status = ?,
              stage = ?,
              visible_summary = ?,
              process_snapshot_json = ?,
              updated_at = ?,
              last_event_cursor = ?
        WHERE id = ?`,
    )
    .bind(
      run.status,
      run.stage,
      run.visibleSummary,
      run.processSnapshotJSON,
      run.updatedAt,
      run.lastEventCursor,
      run.id,
    )
    .run();
};
