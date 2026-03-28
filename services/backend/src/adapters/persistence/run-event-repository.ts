import { formatCursorSequence } from '../../application/ids.js';
import type { ArtifactRecord } from '../../domain/artifact-model.js';
import type { ConversationRecord } from '../../domain/conversation-model.js';
import type { MessageRecord } from '../../domain/message-model.js';
import type { RunEventInsertRecord, RunEventRecord } from '../../domain/run-event-model.js';
import type { RunRecord } from '../../domain/run-model.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface RunEventRow {
  readonly cursorSequence: number;
  readonly id: string;
  readonly runId: string;
  readonly conversationId: string;
  readonly kind: RunEventRecord['kind'];
  readonly stage: RunEventRecord['stage'];
  readonly textDelta: string | null;
  readonly progressLabel: string | null;
  readonly artifactId: string | null;
  readonly runSnapshotJSON: string | null;
  readonly conversationSnapshotJSON: string | null;
  readonly messageSnapshotJSON: string | null;
  readonly artifactSnapshotJSON: string | null;
  readonly createdAt: string;
}

interface D1RunResultMeta {
  readonly last_row_id?: number;
}

interface D1RunResult {
  readonly meta?: D1RunResultMeta;
}

const parseSnapshot = <T>(value: string | null): T | null => {
  return value ? (JSON.parse(value) as T) : null;
};

const mapRunEventRow = (row: RunEventRow): RunEventRecord => {
  return {
    artifactId: row.artifactId,
    artifact: parseSnapshot<ArtifactRecord>(row.artifactSnapshotJSON),
    conversationId: row.conversationId,
    conversation: parseSnapshot<ConversationRecord>(row.conversationSnapshotJSON),
    createdAt: row.createdAt,
    cursor: formatCursorSequence(row.cursorSequence),
    id: row.id,
    kind: row.kind,
    message: parseSnapshot<MessageRecord>(row.messageSnapshotJSON),
    progressLabel: row.progressLabel,
    run: parseSnapshot<RunRecord>(row.runSnapshotJSON),
    runId: row.runId,
    stage: row.stage,
    textDelta: row.textDelta,
  };
};

const findCursorSequenceByEventId = async (env: BackendEnv, eventId: string): Promise<number> => {
  const database = createBackendDatabase(env).raw;
  const row = await database
    .prepare(
      `SELECT cursor_sequence AS cursorSequence
         FROM run_events
        WHERE id = ?
        LIMIT 1`,
    )
    .bind(eventId)
    .first<{ readonly cursorSequence: number }>();

  if (!row) {
    throw new Error(`run_event_cursor_sequence_missing:${eventId}`);
  }

  return row.cursorSequence;
};

export const insertRunEvent = async (
  env: BackendEnv,
  event: RunEventInsertRecord,
): Promise<RunEventRecord> => {
  const database = createBackendDatabase(env).raw;
  const result = (await database
    .prepare(
      `INSERT INTO run_events
         (id, run_id, conversation_id, kind, stage, text_delta, progress_label, artifact_id, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      event.id,
      event.runId,
      event.conversationId,
      event.kind,
      event.stage,
      event.textDelta,
      event.progressLabel,
      event.artifactId,
      event.createdAt,
    )
    .run()) as D1RunResult;

  const cursorSequence =
    result.meta?.last_row_id ?? (await findCursorSequenceByEventId(env, event.id));
  return {
    artifact: null,
    artifactId: event.artifactId,
    conversation: null,
    conversationId: event.conversationId,
    createdAt: event.createdAt,
    cursor: formatCursorSequence(cursorSequence),
    id: event.id,
    kind: event.kind,
    message: null,
    progressLabel: event.progressLabel,
    run: null,
    runId: event.runId,
    stage: event.stage,
    textDelta: event.textDelta,
  };
};

export const updateRunEventSnapshots = async (
  env: BackendEnv,
  event: RunEventRecord,
): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `UPDATE run_events
          SET run_snapshot_json = ?,
              conversation_snapshot_json = ?,
              message_snapshot_json = ?,
              artifact_snapshot_json = ?,
              committed = 1
        WHERE id = ?`,
    )
    .bind(
      event.run ? JSON.stringify(event.run) : null,
      event.conversation ? JSON.stringify(event.conversation) : null,
      event.message ? JSON.stringify(event.message) : null,
      event.artifact ? JSON.stringify(event.artifact) : null,
      event.id,
    )
    .run();
};

export const listRunEventsForUser = async (
  env: BackendEnv,
  userId: string,
  afterCursorSequence: number | null,
  limit: number,
): Promise<RunEventRecord[]> => {
  const database = createBackendDatabase(env).raw;
  const cursorClause = afterCursorSequence ? 'AND run_events.cursor_sequence > ?' : '';
  const statement = database.prepare(
    `SELECT run_events.cursor_sequence AS cursorSequence,
            run_events.id,
            run_events.run_id AS runId,
            run_events.conversation_id AS conversationId,
            run_events.kind,
            run_events.stage,
            run_events.text_delta AS textDelta,
            run_events.progress_label AS progressLabel,
            run_events.artifact_id AS artifactId,
            run_events.run_snapshot_json AS runSnapshotJSON,
            run_events.conversation_snapshot_json AS conversationSnapshotJSON,
            run_events.message_snapshot_json AS messageSnapshotJSON,
            run_events.artifact_snapshot_json AS artifactSnapshotJSON,
            run_events.created_at AS createdAt
      FROM run_events
      JOIN runs ON runs.id = run_events.run_id
      WHERE runs.user_id = ?
        AND run_events.committed = 1
        ${cursorClause}
      ORDER BY run_events.cursor_sequence ASC
      LIMIT ?`,
  );

  const result = afterCursorSequence
    ? await statement.bind(userId, afterCursorSequence, limit).all<RunEventRow>()
    : await statement.bind(userId, limit).all<RunEventRow>();

  return result.results.map(mapRunEventRow);
};
