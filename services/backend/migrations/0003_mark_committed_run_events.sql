ALTER TABLE run_events
ADD COLUMN committed INTEGER NOT NULL DEFAULT 0;

UPDATE run_events
SET committed = 1
WHERE committed = 0;

CREATE INDEX IF NOT EXISTS idx_run_events_committed_cursor
  ON run_events(committed, cursor_sequence);
