import { mkdirSync, existsSync, createWriteStream, createReadStream, unlinkSync, readFileSync } from 'fs';
import { join, resolve } from 'path';
import type { Readable } from 'stream';
import AdmZip from 'adm-zip';

/**
 * Local filesystem storage service
 * Stores build artifacts, source zips, and certs
 */
export class FileStorage {
  private storagePath: string;

  constructor(storagePath: string) {
    this.storagePath = storagePath;
    this.ensureDirectories();
  }

  private ensureDirectories() {
    const dirs = [
      this.storagePath,
      join(this.storagePath, 'builds'),
      join(this.storagePath, 'certs'),
      join(this.storagePath, 'results'),
    ];

    for (const dir of dirs) {
      if (!existsSync(dir)) {
        mkdirSync(dir, { recursive: true });
      }
    }
  }

  /**
   * Save build source zip
   */
  saveBuildSource(buildId: string, stream: Readable): Promise<string> {
    const filePath = join(this.storagePath, 'builds', `${buildId}.zip`);
    return this.saveStream(stream, filePath);
  }

  /**
   * Save build certs/credentials
   */
  saveBuildCerts(buildId: string, stream: Readable): Promise<string> {
    const filePath = join(this.storagePath, 'certs', `${buildId}.zip`);
    return this.saveStream(stream, filePath);
  }

  /**
   * Save build result (IPA/APK)
   */
  saveBuildResult(buildId: string, stream: Readable, extension: string): Promise<string> {
    const filePath = join(this.storagePath, 'results', `${buildId}.${extension}`);
    return this.saveStream(stream, filePath);
  }

  /**
   * Get build source path
   */
  getBuildSourcePath(buildId: string): string {
    return join(this.storagePath, 'builds', `${buildId}.zip`);
  }

  /**
   * Get build certs path
   */
  getBuildCertsPath(buildId: string): string {
    return join(this.storagePath, 'certs', `${buildId}.zip`);
  }

  /**
   * Get build result path
   */
  getBuildResultPath(buildId: string, extension: string): string {
    return join(this.storagePath, 'results', `${buildId}.${extension}`);
  }

  /**
   * Check if build source exists
   */
  buildSourceExists(buildId: string): boolean {
    return existsSync(this.getBuildSourcePath(buildId));
  }

  /**
   * Check if build result exists
   */
  buildResultExists(buildId: string, extension: string): boolean {
    return existsSync(this.getBuildResultPath(buildId, extension));
  }

  /**
   * Create read stream for file
   * SECURITY: Validates path is inside storage directory to prevent path traversal
   */
  createReadStream(filePath: string): Readable {
    const normalized = resolve(filePath);
    const storageRoot = resolve(this.storagePath);

    // Prevent path traversal - ensure file is inside storage directory
    if (!normalized.startsWith(storageRoot)) {
      throw new Error('Path traversal attempt blocked: file must be inside storage directory');
    }

    if (!existsSync(normalized)) {
      throw new Error('File not found');
    }

    return createReadStream(normalized);
  }

  /**
   * Delete build artifacts
   */
  deleteBuildArtifacts(buildId: string) {
    const files = [
      join(this.storagePath, 'builds', `${buildId}.zip`),
      join(this.storagePath, 'certs', `${buildId}.zip`),
      join(this.storagePath, 'results', `${buildId}.ipa`),
      join(this.storagePath, 'results', `${buildId}.apk`),
    ];

    for (const file of files) {
      try {
        if (existsSync(file)) {
          unlinkSync(file);
        }
      } catch (err) {
        console.error(`Failed to delete ${file}:`, err);
      }
    }
  }

  /**
   * Save stream to file
   */
  private saveStream(stream: Readable, filePath: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const writeStream = createWriteStream(filePath);

      stream.pipe(writeStream);

      writeStream.on('finish', () => resolve(filePath));
      writeStream.on('error', reject);
      stream.on('error', reject);
    });
  }

  /**
   * Get storage stats
   */
  getStats() {
    // Could be enhanced with actual disk usage calculations
    return {
      path: this.storagePath,
      exists: existsSync(this.storagePath),
    };
  }

  /**
   * Read and unzip certificate bundle
   * Extracts P12 certificate, password, and provisioning profiles
   */
  readBuildCerts(certsPath: string): Buffer {
    const normalized = resolve(certsPath);
    const storageRoot = resolve(this.storagePath);

    // Prevent path traversal
    if (!normalized.startsWith(storageRoot)) {
      throw new Error('Path traversal attempt blocked: file must be inside storage directory');
    }

    if (!existsSync(normalized)) {
      throw new Error('Certs file not found');
    }

    return readFileSync(normalized);
  }
}

export interface CertsBundle {
  p12: Buffer;
  password: string;
  profiles: Buffer[];
}

/**
 * Unzip certificate bundle and extract components
 * @param zipBuffer - ZIP file containing P12, password.txt, and provisioning profiles
 * @returns Extracted certificate components
 */
export function unzipCerts(zipBuffer: Buffer): CertsBundle {
  const zip = new AdmZip(zipBuffer);
  const entries = zip.getEntries();

  let p12: Buffer | null = null;
  let password = '';
  const profiles: Buffer[] = [];

  for (const entry of entries) {
    if (entry.entryName.endsWith('.p12')) {
      p12 = entry.getData();
    } else if (entry.entryName === 'password.txt') {
      password = entry.getData().toString('utf-8').trim();
    } else if (entry.entryName.endsWith('.mobileprovision')) {
      profiles.push(entry.getData());
    }
  }

  if (!p12) {
    throw new Error('No P12 certificate found in bundle');
  }

  return { p12, password, profiles };
}
