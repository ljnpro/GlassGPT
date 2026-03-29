CREATE TABLE IF NOT EXISTS rate_limit_windows (
  bucket_key TEXT PRIMARY KEY,
  window_start_ms INTEGER NOT NULL,
  request_count INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_windows_updated_at_ms
  ON rate_limit_windows(updated_at_ms);
