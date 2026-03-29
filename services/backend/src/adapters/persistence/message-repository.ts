import type { MessageRecord } from '../../domain/message-model.js';
import { createBackendDatabase } from './d1-database.js';
import type { BackendEnv } from './env.js';

interface MessageRow extends MessageRecord {}

const mapMessageRow = (row: MessageRow): MessageRecord => {
  return {
    agentTraceJSON: row.agentTraceJSON,
    annotationsJSON: row.annotationsJSON,
    completedAt: row.completedAt,
    content: row.content,
    conversationId: row.conversationId,
    createdAt: row.createdAt,
    filePathAnnotationsJSON: row.filePathAnnotationsJSON,
    id: row.id,
    role: row.role,
    runId: row.runId,
    serverCursor: row.serverCursor,
    thinking: row.thinking,
    toolCallsJSON: row.toolCallsJSON,
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
              thinking,
              created_at AS createdAt,
              completed_at AS completedAt,
              server_cursor AS serverCursor,
              annotations_json AS annotationsJSON,
              tool_calls_json AS toolCallsJSON,
              file_path_annotations_json AS filePathAnnotationsJSON,
              agent_trace_json AS agentTraceJSON
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
              thinking,
              created_at AS createdAt,
              completed_at AS completedAt,
              server_cursor AS serverCursor,
              annotations_json AS annotationsJSON,
              tool_calls_json AS toolCallsJSON,
              file_path_annotations_json AS filePathAnnotationsJSON,
              agent_trace_json AS agentTraceJSON
         FROM messages
        WHERE run_id = ?
          AND role = 'user'
        LIMIT 1`,
    )
    .bind(runId)
    .first<MessageRow>();

  return row ? mapMessageRow(row) : null;
};

export const findAssistantMessageByRunId = async (
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
              thinking,
              created_at AS createdAt,
              completed_at AS completedAt,
              server_cursor AS serverCursor,
              annotations_json AS annotationsJSON,
              tool_calls_json AS toolCallsJSON,
              file_path_annotations_json AS filePathAnnotationsJSON,
              agent_trace_json AS agentTraceJSON
         FROM messages
        WHERE run_id = ?
          AND role = 'assistant'
        ORDER BY created_at DESC, id DESC
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
         (
           id,
           conversation_id,
           run_id,
           role,
           content,
           thinking,
           server_cursor,
           created_at,
           completed_at,
           annotations_json,
           tool_calls_json,
           file_path_annotations_json,
           agent_trace_json
         )
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      message.id,
      message.conversationId,
      message.runId,
      message.role,
      message.content,
      message.thinking,
      message.serverCursor,
      message.createdAt,
      message.completedAt,
      message.annotationsJSON,
      message.toolCallsJSON,
      message.filePathAnnotationsJSON,
      message.agentTraceJSON,
    )
    .run();
};

export const updateMessage = async (env: BackendEnv, message: MessageRecord): Promise<void> => {
  const database = createBackendDatabase(env).raw;
  await database
    .prepare(
      `UPDATE messages
          SET content = ?,
              thinking = ?,
              completed_at = ?,
              server_cursor = ?,
              annotations_json = ?,
              tool_calls_json = ?,
              file_path_annotations_json = ?,
              agent_trace_json = ?
        WHERE id = ?`,
    )
    .bind(
      message.content,
      message.thinking,
      message.completedAt,
      message.serverCursor,
      message.annotationsJSON,
      message.toolCallsJSON,
      message.filePathAnnotationsJSON,
      message.agentTraceJSON,
      message.id,
    )
    .run();
};
