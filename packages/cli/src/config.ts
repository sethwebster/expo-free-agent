import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import { existsSync } from 'fs';

interface Config {
  controllerUrl: string;
  apiKey?: string;
}

const OLD_CONFIG_DIR = path.join(os.homedir(), '.expo-controller');
const CONFIG_DIR = path.join(os.homedir(), '.expo-free-agent');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');
const OLD_CONFIG_FILE = path.join(OLD_CONFIG_DIR, 'config.json');
const OLD_TOKENS_FILE = path.join(OLD_CONFIG_DIR, 'build-tokens.json');
const NEW_TOKENS_FILE = path.join(CONFIG_DIR, 'build-tokens.json');

const DEFAULT_CONFIG: Config = {
  controllerUrl: 'http://localhost:3000',
};

/**
 * Migrate old .expo-controller directory to .expo-free-agent
 */
async function migrateOldConfig(): Promise<void> {
  if (!existsSync(OLD_CONFIG_DIR)) {
    return; // Nothing to migrate
  }

  // Create new config dir if it doesn't exist
  await fs.mkdir(CONFIG_DIR, { recursive: true });

  // Migrate config.json
  if (existsSync(OLD_CONFIG_FILE) && !existsSync(CONFIG_FILE)) {
    try {
      await fs.copyFile(OLD_CONFIG_FILE, CONFIG_FILE);
      console.log(`Migrated config from ${OLD_CONFIG_FILE} to ${CONFIG_FILE}`);
    } catch (error) {
      console.warn('Failed to migrate config:', error);
    }
  }

  // Migrate build-tokens.json
  if (existsSync(OLD_TOKENS_FILE) && !existsSync(NEW_TOKENS_FILE)) {
    try {
      await fs.copyFile(OLD_TOKENS_FILE, NEW_TOKENS_FILE);
      console.log(`Migrated build tokens from ${OLD_TOKENS_FILE} to ${NEW_TOKENS_FILE}`);
    } catch (error) {
      console.warn('Failed to migrate build tokens:', error);
    }
  }

  // Optionally remove old directory (commented out for safety)
  // await fs.rm(OLD_CONFIG_DIR, { recursive: true, force: true });
}

export async function loadConfig(): Promise<Config> {
  // Run migration if old config exists
  await migrateOldConfig();

  try {
    const data = await fs.readFile(CONFIG_FILE, 'utf-8');
    return { ...DEFAULT_CONFIG, ...JSON.parse(data) };
  } catch {
    return DEFAULT_CONFIG;
  }
}

export async function saveConfig(config: Partial<Config>): Promise<void> {
  await fs.mkdir(CONFIG_DIR, { recursive: true });
  const current = await loadConfig();
  const updated = { ...current, ...config };

  // Atomic write: write to temp file, then rename
  const tempFile = `${CONFIG_FILE}.${process.pid}.tmp`;

  try {
    await fs.writeFile(tempFile, JSON.stringify(updated, null, 2), { mode: 0o600 });
    await fs.rename(tempFile, CONFIG_FILE);
  } catch (error) {
    // Clean up temp file on error
    try {
      await fs.unlink(tempFile);
    } catch {}
    throw error;
  }
}

export async function getControllerUrl(): Promise<string> {
  // Prefer environment variable
  const envUrl = process.env.EXPO_CONTROLLER_URL;
  if (envUrl) {
    return envUrl;
  }

  // Fall back to config file
  const config = await loadConfig();
  return config.controllerUrl;
}

export async function getApiKey(): Promise<string | undefined> {
  // Prefer environment variable
  const envKey = process.env.EXPO_CONTROLLER_API_KEY;
  if (envKey) {
    return envKey;
  }

  // Fall back to config file
  const config = await loadConfig();
  return config.apiKey;
}

export function getAuthBaseUrl(): string {
  // Prefer environment variable
  const envUrl = process.env.AUTH_BASE_URL;
  if (envUrl) {
    return envUrl;
  }

  // Default to production landing page
  return 'https://expo-free-agent.pages.dev';
}
