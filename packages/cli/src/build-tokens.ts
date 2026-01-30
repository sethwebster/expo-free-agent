import fs from 'fs/promises';
import path from 'path';
import os from 'os';

interface BuildTokens {
  [buildId: string]: string;
}

const CONFIG_DIR = path.join(os.homedir(), '.expo-free-agent');
const TOKENS_FILE = path.join(CONFIG_DIR, 'build-tokens.json');

/**
 * Load all stored build tokens
 */
export async function loadBuildTokens(): Promise<BuildTokens> {
  try {
    const data = await fs.readFile(TOKENS_FILE, 'utf-8');
    return JSON.parse(data);
  } catch {
    return {};
  }
}

/**
 * Save a build token for a specific build ID
 */
export async function saveBuildToken(buildId: string, token: string): Promise<void> {
  await fs.mkdir(CONFIG_DIR, { recursive: true });
  const tokens = await loadBuildTokens();
  tokens[buildId] = token;

  // Atomic write
  const tempFile = `${TOKENS_FILE}.${process.pid}.tmp`;

  try {
    await fs.writeFile(tempFile, JSON.stringify(tokens, null, 2), { mode: 0o600 });
    await fs.rename(tempFile, TOKENS_FILE);
  } catch (error) {
    try {
      await fs.unlink(tempFile);
    } catch {}
    throw error;
  }
}

/**
 * Get the stored token for a specific build ID
 */
export async function getBuildToken(buildId: string): Promise<string | undefined> {
  const tokens = await loadBuildTokens();
  return tokens[buildId];
}

/**
 * Delete a build token (e.g., after download completes)
 */
export async function deleteBuildToken(buildId: string): Promise<void> {
  const tokens = await loadBuildTokens();
  delete tokens[buildId];

  const tempFile = `${TOKENS_FILE}.${process.pid}.tmp`;

  try {
    await fs.writeFile(tempFile, JSON.stringify(tokens, null, 2), { mode: 0o600 });
    await fs.rename(tempFile, TOKENS_FILE);
  } catch (error) {
    try {
      await fs.unlink(tempFile);
    } catch {}
    throw error;
  }
}
