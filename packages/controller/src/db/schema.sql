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
  access_token TEXT NOT NULL, -- unique token for build submitter access
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

CREATE TABLE IF NOT EXISTS diagnostics (
  id TEXT PRIMARY KEY,
  worker_id TEXT NOT NULL,
  status TEXT NOT NULL, -- healthy, warning, critical
  run_at INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  auto_fixed INTEGER DEFAULT 0, -- SQLite boolean (0 or 1)
  checks TEXT NOT NULL, -- JSON array of check results
  FOREIGN KEY (worker_id) REFERENCES workers(id)
);

CREATE TABLE IF NOT EXISTS cpu_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  build_id TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  cpu_percent REAL NOT NULL, -- 0-100% CPU usage
  memory_mb REAL NOT NULL, -- Memory usage in MB
  FOREIGN KEY (build_id) REFERENCES builds(id)
);

-- Distributed controller tables
CREATE TABLE IF NOT EXISTS controller_nodes (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  name TEXT NOT NULL,
  registered_at INTEGER NOT NULL,
  last_heartbeat_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  is_active INTEGER DEFAULT 1,
  metadata TEXT
);

CREATE TABLE IF NOT EXISTS event_log (
  id TEXT PRIMARY KEY,
  sequence INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  payload TEXT NOT NULL,
  source_controller_id TEXT NOT NULL,
  previous_hash TEXT,
  event_hash TEXT NOT NULL,
  UNIQUE(sequence)
);

CREATE TABLE IF NOT EXISTS event_propagation (
  event_id TEXT NOT NULL,
  controller_id TEXT NOT NULL,
  propagated_at INTEGER NOT NULL,
  PRIMARY KEY (event_id, controller_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_builds_status ON builds(status);
CREATE INDEX IF NOT EXISTS idx_builds_worker ON builds(worker_id);
CREATE INDEX IF NOT EXISTS idx_builds_access_token ON builds(access_token);
CREATE INDEX IF NOT EXISTS idx_logs_build ON build_logs(build_id);
CREATE INDEX IF NOT EXISTS idx_diagnostics_worker ON diagnostics(worker_id);
CREATE INDEX IF NOT EXISTS idx_diagnostics_run_at ON diagnostics(run_at);
CREATE INDEX IF NOT EXISTS idx_cpu_snapshots_build ON cpu_snapshots(build_id);
CREATE INDEX IF NOT EXISTS idx_cpu_snapshots_timestamp ON cpu_snapshots(timestamp);
CREATE INDEX IF NOT EXISTS idx_controller_nodes_active ON controller_nodes(is_active, expires_at);
CREATE INDEX IF NOT EXISTS idx_event_log_sequence ON event_log(sequence);
CREATE INDEX IF NOT EXISTS idx_event_log_entity ON event_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_event_log_source ON event_log(source_controller_id);
CREATE INDEX IF NOT EXISTS idx_event_propagation_event ON event_propagation(event_id);
