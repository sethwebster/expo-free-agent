import { execSync } from 'child_process';
import { createWriteStream, mkdirSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { pipeline } from 'stream/promises';
import * as tar from 'tar';

const APP_NAME = 'FreeAgent.app';
// Direct download URL - update this when you publish new versions
const DOWNLOAD_URL = process.env.FREEAGENT_DOWNLOAD_URL || 'https://github.com/sethwebster/expo-free-agent/releases/latest/download/FreeAgent.app.tar.gz';
const VERSION = '0.1.3';

export interface DownloadProgress {
  percent: number;
  transferred: number;
  total: number;
}

export interface ReleaseInfo {
  version: string;
  download_url: string;
}

export async function downloadBinary(
  url: string,
  onProgress?: (progress: DownloadProgress) => void
): Promise<string> {
  const tempDir = join(tmpdir(), `expo-free-agent-${Date.now()}`);
  mkdirSync(tempDir, { recursive: true });

  const filename = url.split('/').pop() || 'download.tar.gz';
  const downloadPath = join(tempDir, filename);

  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Download failed: ${response.statusText}`);
  }

  const contentLength = parseInt(response.headers.get('content-length') || '0');
  let downloaded = 0;

  const fileStream = createWriteStream(downloadPath);

  if (response.body) {
    const reader = response.body.getReader();

    try {
      while (true) {
        const { done, value } = await reader.read();

        if (done) break;

        downloaded += value.length;
        fileStream.write(value);

        if (onProgress && contentLength > 0) {
          onProgress({
            percent: (downloaded / contentLength) * 100,
            transferred: downloaded,
            total: contentLength
          });
        }
      }
    } finally {
      fileStream.end();
    }
  }

  return downloadPath;
}

export async function extractApp(tarballPath: string, destination: string): Promise<string> {
  const extractDir = join(tmpdir(), `expo-free-agent-extract-${Date.now()}`);
  mkdirSync(extractDir, { recursive: true });

  await tar.x({
    file: tarballPath,
    cwd: extractDir
  });

  return join(extractDir, APP_NAME);
}

export function verifyCodeSignature(appPath: string): boolean {
  try {
    execSync(`codesign --verify --deep --strict "${appPath}"`, {
      stdio: 'pipe'
    });
    return true;
  } catch {
    return false;
  }
}

export function getSigningInfo(appPath: string): string | null {
  try {
    const output = execSync(`codesign -dv "${appPath}" 2>&1`, {
      encoding: 'utf-8'
    });
    return output;
  } catch {
    return null;
  }
}

export async function downloadAndVerifyRelease(
  onProgress?: (progress: DownloadProgress) => void
): Promise<{ appPath: string; version: string }> {
  const tarballPath = await downloadBinary(DOWNLOAD_URL, onProgress);
  const appPath = await extractApp(tarballPath, tmpdir());

  // Cleanup tarball
  rmSync(tarballPath);

  return {
    appPath,
    version: VERSION
  };
}

export function cleanupDownload(path: string): void {
  try {
    rmSync(path, { recursive: true, force: true });
  } catch (error) {
    console.warn(`Failed to cleanup ${path}:`, error);
  }
}
