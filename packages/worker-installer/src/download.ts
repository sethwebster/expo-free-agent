import { execSync } from 'child_process';
import { createWriteStream, mkdirSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { pipeline } from 'stream/promises';
import * as tar from 'tar';

const APP_NAME = 'FreeAgent.app';
// Direct download URL - update this when you publish new versions
const DOWNLOAD_URL = process.env.FREEAGENT_DOWNLOAD_URL || 'https://github.com/sethwebster/expo-free-agent/releases/latest/download/FreeAgent.app.tar.gz';
const VERSION = '0.1.12';

export interface DownloadProgress {
  percent: number;
  transferred: number;
  total: number;
}

export interface ReleaseInfo {
  version: string;
  download_url: string;
}

async function downloadBinaryAttempt(
  url: string,
  tempDir: string,
  filename: string,
  onProgress?: (progress: DownloadProgress) => void
): Promise<string> {
  const downloadPath = join(tempDir, filename);

  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Download failed: ${response.statusText}`);
  }

  const contentLength = parseInt(response.headers.get('content-length') || '0');
  let downloaded = 0;

  const fileStream = createWriteStream(downloadPath);

  // Wait for stream to finish writing before returning
  await new Promise<void>((resolve, reject) => {
    fileStream.on('finish', resolve);
    fileStream.on('error', reject);

    if (response.body) {
      const reader = response.body.getReader();

      const pump = async () => {
        try {
          while (true) {
            const { done, value } = await reader.read();

            if (done) {
              fileStream.end();
              break;
            }

            downloaded += value.length;

            // Check if stream is ready for more data
            if (!fileStream.write(value)) {
              await new Promise(resolve => fileStream.once('drain', resolve));
            }

            if (onProgress && contentLength > 0) {
              onProgress({
                percent: (downloaded / contentLength) * 100,
                transferred: downloaded,
                total: contentLength
              });
            }
          }
        } catch (error) {
          fileStream.destroy();
          reject(error);
        }
      };

      pump();
    } else {
      fileStream.end();
    }
  });

  return downloadPath;
}

export interface DownloadOptions {
  onProgress?: (progress: DownloadProgress) => void;
  onRetry?: (attempt: number, maxRetries: number, error: Error) => void;
  maxRetries?: number;
}

export async function downloadBinary(
  url: string,
  options: DownloadOptions = {}
): Promise<string> {
  const { onProgress, onRetry, maxRetries = 3 } = options;

  const tempDir = join(tmpdir(), `expo-free-agent-${Date.now()}`);
  mkdirSync(tempDir, { recursive: true });

  const filename = url.split('/').pop() || 'download.tar.gz';
  const downloadPath = join(tempDir, filename);

  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      if (attempt > 1) {
        // Exponential backoff: 1s, 2s, 4s
        const delay = Math.pow(2, attempt - 1) * 1000;
        await new Promise(resolve => setTimeout(resolve, delay));

        // Clean up partial download
        try {
          rmSync(downloadPath, { force: true });
        } catch {
          // Ignore cleanup errors
        }

        if (onRetry) {
          onRetry(attempt, maxRetries, lastError!);
        }
      }

      return await downloadBinaryAttempt(url, tempDir, filename, onProgress);
    } catch (error) {
      lastError = error as Error;

      if (attempt === maxRetries) {
        // Cleanup temp dir on final failure
        try {
          rmSync(tempDir, { recursive: true, force: true });
        } catch {
          // Ignore cleanup errors
        }
        throw new Error(`Download failed after ${maxRetries} attempts: ${lastError.message}`);
      }
    }
  }

  // Shouldn't reach here but TypeScript needs it
  throw lastError || new Error('Download failed');
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
  onProgress?: (progress: DownloadProgress) => void,
  onRetry?: (attempt: number, maxRetries: number, error: Error) => void
): Promise<{ appPath: string; version: string }> {
  const tarballPath = await downloadBinary(DOWNLOAD_URL, { onProgress, onRetry });
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
