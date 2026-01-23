-- Central Controller Database Schema

CREATE TABLE IF NOT EXISTS workers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'idle', -- idle, building, offline
  capabilities TEXT NOT NULL, -- JSON: platforms, xcode_version, etc.
  registered_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  builds_completed INTEGER DEFAULT 0,
  builds_failed INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS builds (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, assigned, building, completed, failed
  platform TEXT NOT NULL, -- ios, android
  source_path TEXT NOT NULL, -- local file path to zip
  certs_path TEXT, -- local file path to certs
  result_path TEXT, -- local file path to IPA/APK
  worker_id TEXT,
  submitted_at INTEGER NOT NULL,
  started_at INTEGER,
  completed_at INTEGER,
  error_message TEXT,
  FOREIGN KEY (worker_id) REFERENCES workers(id)
);

CREATE TABLE IF NOT EXISTS build_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  build_id TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  level TEXT NOT NULL, -- info, warn, error
  message TEXT NOT NULL,
  FOREIGN KEY (build_id) REFERENCES builds(id)
);

CREATE INDEX IF NOT EXISTS idx_builds_status ON builds(status);
CREATE INDEX IF NOT EXISTS idx_builds_worker ON builds(worker_id);
CREATE INDEX IF NOT EXISTS idx_logs_build ON build_logs(build_id);
