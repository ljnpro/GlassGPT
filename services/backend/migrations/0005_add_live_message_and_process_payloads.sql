ALTER TABLE messages ADD COLUMN thinking TEXT;
ALTER TABLE messages ADD COLUMN annotations_json TEXT;
ALTER TABLE messages ADD COLUMN tool_calls_json TEXT;
ALTER TABLE messages ADD COLUMN file_path_annotations_json TEXT;
ALTER TABLE messages ADD COLUMN agent_trace_json TEXT;

ALTER TABLE runs ADD COLUMN process_snapshot_json TEXT;
