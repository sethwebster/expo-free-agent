export interface PreflightResult {
  check: string;
  status: 'ok' | 'warn' | 'error';
  message: string;
  details?: string;
}

export interface WorkerConfiguration {
  controllerURL: string;
  apiKey: string;
  workerID?: string;
  publicIdentifier?: string;  // Unique identifier safe for public display (no PII)
  deviceName?: string;
  pollIntervalSeconds?: number;
  maxCPUPercent?: number;
  maxMemoryGB?: number;
  maxConcurrentBuilds?: number;
  vmDiskSizeGB?: number;
  reuseVMs?: boolean;
  cleanupAfterBuild?: boolean;
  autoStart?: boolean;
  onlyWhenIdle?: boolean;
  buildTimeoutMinutes?: number;
}

export interface WorkerCapabilities {
  cpuCores: number;
  memoryGB: number;
  diskGB: number;
  xcodeVersion?: string;
  tartVersion?: string;
  platform: string;
  architecture: string;
}

export interface RegistrationResponse {
  workerID: string;
  publicIdentifier: string;
  message: string;
}

export interface InstallOptions {
  controllerUrl?: string;
  apiKey?: string;
  skipLaunch?: boolean;
  verbose?: boolean;
  forceReinstall?: boolean;
  autoAccept?: boolean;
  autoRestart?: boolean;
}
