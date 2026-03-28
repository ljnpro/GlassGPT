DROP INDEX IF EXISTS idx_run_events_run_id;
DROP INDEX IF EXISTS idx_run_events_conversation_id;
DROP TABLE IF EXISTS run_events;

CREATE TABLE IF NOT EXISTS run_events (
  cursor_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  run_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  stage TEXT,
  text_delta TEXT,
  progress_label TEXT,
  artifact_id TEXT,
  run_snapshot_json TEXT,
  conversation_snapshot_json TEXT,
  message_snapshot_json TEXT,
  artifact_snapshot_json TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES runs(id),
  FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

CREATE INDEX IF NOT EXISTS idx_run_events_run_id ON run_events(run_id);
CREATE INDEX IF NOT EXISTS idx_run_events_conversation_id ON run_events(conversation_id);
