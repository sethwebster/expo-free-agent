import fs from 'fs/promises';
import path from 'path';
import os from 'os';

interface Config {
  controllerUrl: string;
  apiKey?: string;
}

const CONFIG_DIR = path.join(os.homedir(), '.expo-controller');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

const DEFAULT_CONFIG: Config = {
  controllerUrl: 'http://localhost:3000',
};

export async function loadConfig(): Promise<Config> {
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
