// Shared type definitions for CLI

/**
 * Log entry from build logs
 */
export interface LogEntry {
  timestamp: string;
  level: 'error' | 'warn' | 'info' | 'debug';
  message: string;
}

/**
 * Diagnostic check result
 */
export interface DiagnosticCheck {
  name: string;
  status: 'pass' | 'warn' | 'fail';
  message: string;
  duration_ms: number;
  auto_fixed?: boolean;
  details?: Record<string, unknown>;
}

/**
 * Diagnostic report
 */
export interface DiagnosticReport {
  status: 'healthy' | 'warning' | 'critical';
  run_at: string;
  duration_ms: number;
  auto_fixed: boolean;
  checks: DiagnosticCheck[];
}

/**
 * Diagnostics response
 */
export interface DiagnosticsResponse {
  worker_id: string;
  reports: DiagnosticReport[];
}

/**
 * Build status response (internal format before transformation)
 */
export interface BuildStatusResponse {
  id: string;
  status: 'pending' | 'assigned' | 'building' | 'completed' | 'failed';
  platform?: string | null;
  worker_id?: string | null;
  submitted_at?: number | null;
  started_at?: number | null;
  completed_at?: number | null;
  error_message?: string | null;
}

/**
 * Command options for logs command
 */
export interface LogsCommandOptions {
  apiKey?: string;
  controllerUrl?: string;
  follow?: boolean;
  watch?: boolean;
  tail?: boolean;
  interval?: string;
}

/**
 * Type guard to check if stdin has setRawMode (TTY)
 */
export interface TTYReadStream extends NodeJS.ReadStream {
  setRawMode(mode: boolean): this;
}

/**
 * Type guard for stdin
 */
export function isTTY(stream: NodeJS.ReadStream): stream is TTYReadStream {
  return typeof (stream as TTYReadStream).setRawMode === 'function';
}
