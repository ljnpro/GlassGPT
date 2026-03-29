import type { BackendRuntimeContext } from '../../application/runtime-context.js';

export interface RateLimitWindowRecord {
  readonly bucketKey: string;
  readonly requestCount: number;
  readonly updatedAtMs: number;
  readonly windowStartMs: number;
}

interface RateLimitWindowRow {
  readonly bucketKey: string;
  readonly requestCount: number;
  readonly updatedAtMs: number;
  readonly windowStartMs: number;
}

const mapRateLimitWindowRecord = (row: RateLimitWindowRow): RateLimitWindowRecord => {
  return {
    bucketKey: row.bucketKey,
    requestCount: row.requestCount,
    updatedAtMs: row.updatedAtMs,
    windowStartMs: row.windowStartMs,
  };
};

export const loadRateLimitWindow = async (
  env: BackendRuntimeContext,
  bucketKey: string,
): Promise<RateLimitWindowRecord | null> => {
  const row = await env.GLASSGPT_DB.prepare(
    `SELECT bucket_key AS bucketKey,
            request_count AS requestCount,
            updated_at_ms AS updatedAtMs,
            window_start_ms AS windowStartMs
       FROM rate_limit_windows
      WHERE bucket_key = ?`,
  )
    .bind(bucketKey)
    .first<RateLimitWindowRow>();

  return row ? mapRateLimitWindowRecord(row) : null;
};

export const saveRateLimitWindow = async (
  env: BackendRuntimeContext,
  record: RateLimitWindowRecord,
): Promise<void> => {
  await env.GLASSGPT_DB.prepare(
    `INSERT INTO rate_limit_windows (
       bucket_key,
       window_start_ms,
       request_count,
       updated_at_ms
     ) VALUES (?, ?, ?, ?)
     ON CONFLICT(bucket_key) DO UPDATE SET
       window_start_ms = excluded.window_start_ms,
       request_count = excluded.request_count,
       updated_at_ms = excluded.updated_at_ms`,
  )
    .bind(record.bucketKey, record.windowStartMs, record.requestCount, record.updatedAtMs)
    .run();
};

export const pruneRateLimitWindows = async (
  env: BackendRuntimeContext,
  olderThanMs: number,
): Promise<void> => {
  await env.GLASSGPT_DB.prepare('DELETE FROM rate_limit_windows WHERE updated_at_ms < ?')
    .bind(olderThanMs)
    .run();
};
