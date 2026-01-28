/**
 * Distributed controller mode
 */
export type ControllerMode = 'standalone' | 'distributed';

/**
 * Configuration value object for controller settings
 *
 * Security model: localhost-only prototype with shared API key
 * - Designed for trusted network environments
 * - Single shared API key for all workers (MVP simplification)
 * - NOT production-ready (needs per-worker keys, rate limiting, etc.)
 */
export interface ControllerConfig {
  // Server
  port: number;
  dbPath: string;
  storagePath: string;

  // Security - MVP "trust network" approach
  // IMPORTANT: This is a shared secret for localhost-only prototype
  // Production would need per-worker API keys stored in DB
  apiKey: string;

  // Worker configuration
  baseImageId: string;  // Tart VM template name (e.g., ghcr.io/sethwebster/expo-free-agent-base:latest)

  // Upload limits (in bytes)
  maxSourceFileSize: number;  // Default: 500MB (large iOS apps)
  maxCertsFileSize: number;   // Default: 10MB (certs are small)
  maxResultFileSize: number;  // Default: 1GB (built IPAs can be large)

  // Distributed controller settings
  mode: ControllerMode;              // standalone or distributed
  controllerId: string;              // unique controller ID (UUID)
  controllerName: string;            // human-readable name
  parentControllerUrl?: string;      // parent controller to register with
  registrationTtl: number;           // milliseconds, default 5 minutes
  heartbeatInterval: number;         // milliseconds, default 2 minutes
  expirationCheckInterval: number;   // milliseconds, default 1 minute
}

/**
 * Default configuration values
 */
export const DEFAULT_CONFIG: Omit<ControllerConfig, 'port' | 'dbPath' | 'storagePath'> = {
  // Generate random API key if not provided
  // In production, this should be set via environment variable
  apiKey: process.env.CONTROLLER_API_KEY || 'dev-insecure-key-change-in-production',

  // Worker configuration
  baseImageId: process.env.BASE_IMAGE_ID || 'ghcr.io/sethwebster/expo-free-agent-base:0.1.23',

  // Upload limits
  maxSourceFileSize: 500 * 1024 * 1024,   // 500MB
  maxCertsFileSize: 10 * 1024 * 1024,      // 10MB
  maxResultFileSize: 1024 * 1024 * 1024,   // 1GB

  // Distributed controller defaults
  mode: (process.env.CONTROLLER_MODE as ControllerMode) || 'standalone',
  controllerId: process.env.CONTROLLER_ID || crypto.randomUUID(),
  controllerName: process.env.CONTROLLER_NAME || os.hostname(),
  parentControllerUrl: process.env.PARENT_CONTROLLER_URL,
  registrationTtl: 5 * 60 * 1000,         // 5 minutes
  heartbeatInterval: 2 * 60 * 1000,       // 2 minutes
  expirationCheckInterval: 60 * 1000,     // 1 minute
};

/**
 * Validate and merge configuration
 */
export function createConfig(partial: Partial<ControllerConfig> & Pick<ControllerConfig, 'port' | 'dbPath' | 'storagePath'>): ControllerConfig {
  const config = {
    ...DEFAULT_CONFIG,
    ...partial,
  };

  // Validate required fields
  if (!config.port || config.port < 1 || config.port > 65535) {
    throw new Error('Invalid port number');
  }

  if (!config.dbPath) {
    throw new Error('Database path required');
  }

  if (!config.storagePath) {
    throw new Error('Storage path required');
  }

  if (!config.apiKey || config.apiKey.length < 16) {
    throw new Error('API key must be at least 16 characters');
  }

  // Warn about insecure default
  if (config.apiKey === 'dev-insecure-key-change-in-production') {
    console.warn('⚠️  WARNING: Using default API key. Set CONTROLLER_API_KEY environment variable for production.');
  }

  return config;
}
