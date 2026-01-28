import fs from 'fs';
import { createWriteStream } from 'fs';
import { getControllerUrl, getApiKey } from './config.js';
import { z } from 'zod';

// Validation schemas
const BuildSubmissionResponseSchema = z.object({
  id: z.string(),
}).transform((data) => ({ buildId: data.id }));

const BuildStatusSchema = z.object({
  id: z.string(),
  status: z.enum(['pending', 'assigned', 'building', 'completed', 'failed']),
  platform: z.string().nullable().optional(),
  worker_id: z.string().nullable().optional(),
  submitted_at: z.number().nullable().optional(),
  started_at: z.number().nullable().optional(),
  completed_at: z.number().nullable().optional(),
  error_message: z.string().nullable().optional(),
}).transform((data) => ({
  id: data.id,
  status: data.status,
  createdAt: data.submitted_at ? new Date(data.submitted_at).toISOString() : undefined,
  completedAt: data.completed_at ? new Date(data.completed_at).toISOString() : undefined,
  error: data.error_message || undefined,
}));

const BuildSchema = z.object({
  id: z.string(),
  status: z.string(),
  createdAt: z.string(),
  completedAt: z.string().optional(),
});

const BuildsArraySchema = z.array(BuildSchema);

// Exported types
export type BuildSubmission = {
  projectPath: string;
  certPath?: string;
  profilePath?: string;
  appleId?: string;
};

export type BuildStatus = z.infer<typeof BuildStatusSchema>;
export type Build = z.infer<typeof BuildSchema>;

// Config
const FETCH_TIMEOUT_MS = 30_000;
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 1000;
const MAX_UPLOAD_SIZE_BYTES = 500 * 1024 * 1024; // 500MB

export class APIClient {
  private baseUrl: string;
  private apiKey?: string;

  constructor(baseUrl?: string, apiKey?: string) {
    this.baseUrl = baseUrl || '';
    this.apiKey = apiKey;
  }

  async init(): Promise<void> {
    if (!this.baseUrl) {
      this.baseUrl = await getControllerUrl();
    }
    if (!this.apiKey) {
      this.apiKey = await getApiKey();

      // If still no API key, show helpful message
      if (!this.apiKey) {
        throw new Error(
          'API key not found. Run `expo-free-agent login` to authenticate.\n' +
          'Alternatively, set the EXPO_CONTROLLER_API_KEY environment variable.'
        );
      }
    }
  }

  private async fetchWithTimeout(
    url: string,
    options: RequestInit = {},
    retries = MAX_RETRIES
  ): Promise<Response> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    // Add API key header if available
    // Handle both plain objects (from form.getHeaders()) and Headers instances
    let headers: RequestInit['headers'];
    if (this.apiKey) {
      if (options.headers && typeof options.headers === 'object' && !(options.headers instanceof Headers)) {
        // Plain object (e.g., from form.getHeaders())
        headers = {
          ...options.headers as Record<string, string>,
          'X-API-Key': this.apiKey,
        };
      } else {
        // Headers instance or undefined
        headers = new Headers(options.headers);
        (headers as Headers).set('X-API-Key', this.apiKey);
      }
    } else {
      headers = options.headers;
    }

    try {
      const response = await fetch(url, {
        ...options,
        headers,
        signal: controller.signal,
      });

      clearTimeout(timeout);
      return response;
    } catch (error) {
      clearTimeout(timeout);

      // Retry on network errors or timeouts
      if (retries > 0 && (error instanceof Error && error.name === 'AbortError')) {
        await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
        return this.fetchWithTimeout(url, options, retries - 1);
      }

      throw error;
    }
  }

  async submitBuild(submission: BuildSubmission): Promise<{ buildId: string }> {
    await this.init();

    // Validate inputs
    if (!submission.projectPath || submission.projectPath.trim() === '') {
      throw new Error('Project path is required');
    }

    // Validate file sizes before upload
    const projectStats = await fs.promises.stat(submission.projectPath);
    if (projectStats.size > MAX_UPLOAD_SIZE_BYTES) {
      throw new Error(
        `Project file too large: ${formatBytes(projectStats.size)}. Maximum: ${formatBytes(MAX_UPLOAD_SIZE_BYTES)}`
      );
    }

    if (submission.certPath) {
      const certStats = await fs.promises.stat(submission.certPath);
      if (certStats.size > MAX_UPLOAD_SIZE_BYTES) {
        throw new Error(
          `Certificate file too large: ${formatBytes(certStats.size)}. Maximum: ${formatBytes(MAX_UPLOAD_SIZE_BYTES)}`
        );
      }
    }

    if (submission.profilePath) {
      const profileStats = await fs.promises.stat(submission.profilePath);
      if (profileStats.size > MAX_UPLOAD_SIZE_BYTES) {
        throw new Error(
          `Profile file too large: ${formatBytes(profileStats.size)}. Maximum: ${formatBytes(MAX_UPLOAD_SIZE_BYTES)}`
        );
      }
    }

    // Read files into buffers and create native FormData with Blobs
    const projectBuffer = await fs.promises.readFile(submission.projectPath);
    const projectBlob = new Blob([projectBuffer], { type: 'application/gzip' });

    // Use native FormData (works with fetch)
    const form = new FormData();
    form.append('source', projectBlob, 'project.tar.gz');
    form.append('platform', 'ios'); // TODO: detect from project or pass as param

    if (submission.certPath) {
      const certBuffer = await fs.promises.readFile(submission.certPath);
      const certBlob = new Blob([certBuffer], { type: 'application/zip' });
      form.append('certs', certBlob, 'certs.zip');
    }

    if (submission.profilePath) {
      const profileBuffer = await fs.promises.readFile(submission.profilePath);
      const profileBlob = new Blob([profileBuffer], { type: 'application/octet-stream' });
      form.append('profile', profileBlob, 'profile.mobileprovision');
    }

    if (submission.appleId) {
      form.append('appleId', submission.appleId);
    }

    // Apple password from env var only - never from CLI args
    const applePassword = process.env.EXPO_APPLE_PASSWORD;
    if (applePassword) {
      form.append('applePassword', applePassword);
    }

    const response = await this.fetchWithTimeout(`${this.baseUrl}/api/builds/submit`, {
      method: 'POST',
      body: form as any,
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Build submission failed: ${error}`);
    }

    const json = await response.json();
    return BuildSubmissionResponseSchema.parse(json);
  }

  async getBuildStatus(buildId: string): Promise<BuildStatus> {
    await this.init();

    if (!buildId || buildId.trim() === '') {
      throw new Error('Build ID is required');
    }

    const response = await this.fetchWithTimeout(`${this.baseUrl}/api/builds/${buildId}/status`);

    if (!response.ok) {
      throw new Error(`Failed to get build status: ${response.statusText}`);
    }

    const json = await response.json();
    return BuildStatusSchema.parse(json);
  }

  async downloadBuild(
    buildId: string,
    outputPath: string,
    onProgress?: (downloadedBytes: number) => void
  ): Promise<void> {
    await this.init();

    // Validate output path to prevent path traversal
    const resolvedPath = validateOutputPath(outputPath);

    const response = await this.fetchWithTimeout(`${this.baseUrl}/api/builds/${buildId}/download`);

    if (!response.ok) {
      throw new Error(`Failed to download build: ${response.statusText}`);
    }

    if (!response.body) {
      throw new Error('Response body is empty');
    }

    // Stream to disk instead of loading into memory
    const fileStream = createWriteStream(resolvedPath);
    const reader = response.body.getReader();

    let downloadedBytes = 0;

    try {
      while (true) {
        const { done, value } = await reader.read();

        if (done) break;

        downloadedBytes += value.length;
        fileStream.write(value);

        if (onProgress) {
          onProgress(downloadedBytes);
        }
      }

      fileStream.end();

      // Wait for file stream to finish
      await new Promise<void>((resolve, reject) => {
        fileStream.on('finish', () => resolve());
        fileStream.on('error', reject);
      });
    } catch (error) {
      // Clean up partial file on error
      fileStream.close();
      try {
        await fs.promises.unlink(resolvedPath);
      } catch {}
      throw error;
    }
  }

  async listBuilds(): Promise<Build[]> {
    await this.init();

    const response = await this.fetchWithTimeout(`${this.baseUrl}/api/builds`);

    if (!response.ok) {
      throw new Error(`Failed to list builds: ${response.statusText}`);
    }

    const json = await response.json();
    return BuildsArraySchema.parse(json);
  }

  async cancelBuild(buildId: string): Promise<void> {
    await this.init();

    if (!buildId || buildId.trim() === '') {
      throw new Error('Build ID is required');
    }

    const response = await this.fetchWithTimeout(`${this.baseUrl}/api/builds/${buildId}/cancel`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Failed to cancel build: ${error}`);
    }
  }

  async getDiagnostics(workerId: string, limit?: number): Promise<any> {
    await this.init();

    if (!workerId || workerId.trim() === '') {
      throw new Error('Worker ID is required');
    }

    const url = limit
      ? `${this.baseUrl}/api/diagnostics/${workerId}?limit=${limit}`
      : `${this.baseUrl}/api/diagnostics/${workerId}`;

    const response = await this.fetchWithTimeout(url);

    if (!response.ok) {
      if (response.status === 404) {
        throw new Error('Worker not found or no diagnostics available');
      }
      throw new Error(`Failed to get diagnostics: ${response.statusText}`);
    }

    return response.json();
  }

  async getLatestDiagnostic(workerId: string): Promise<any> {
    await this.init();

    if (!workerId || workerId.trim() === '') {
      throw new Error('Worker ID is required');
    }

    const response = await this.fetchWithTimeout(`${this.baseUrl}/api/diagnostics/${workerId}/latest`);

    if (!response.ok) {
      if (response.status === 404) {
        throw new Error('Worker not found or no diagnostics available');
      }
      throw new Error(`Failed to get latest diagnostic: ${response.statusText}`);
    }

    return response.json();
  }
}

export const apiClient = new APIClient();

// Helper functions

function validateOutputPath(outputPath: string): string {
  const path = require('path');

  // Resolve to absolute path
  const resolved = path.resolve(outputPath);

  // Ensure path doesn't escape current working directory
  const cwd = process.cwd();
  if (!resolved.startsWith(cwd)) {
    throw new Error(
      `Invalid output path: must be within current directory. Got: ${resolved}, expected to start with: ${cwd}`
    );
  }

  // Check for suspicious patterns
  if (outputPath.includes('..')) {
    throw new Error('Invalid output path: path traversal detected');
  }

  return resolved;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}
