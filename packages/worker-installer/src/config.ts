import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import type { WorkerConfiguration } from './types.js';

const CONFIG_DIR = join(homedir(), 'Library', 'Application Support', 'FreeAgent');
const CONFIG_FILE = join(CONFIG_DIR, 'config.json');

export function ensureConfigDirectory(): void {
  if (!existsSync(CONFIG_DIR)) {
    mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  }
}

export function saveConfiguration(config: WorkerConfiguration): void {
  ensureConfigDirectory();
  writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), { mode: 0o600 });
}

export function loadConfiguration(): WorkerConfiguration | null {
  if (!existsSync(CONFIG_FILE)) {
    return null;
  }

  try {
    const content = readFileSync(CONFIG_FILE, 'utf-8');
    return JSON.parse(content);
  } catch (error) {
    console.warn(`Warning: Could not parse config file: ${error}`);
    return null;
  }
}

export function configExists(): boolean {
  return existsSync(CONFIG_FILE);
}

export function getConfigPath(): string {
  return CONFIG_FILE;
}
