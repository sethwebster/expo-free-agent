#!/usr/bin/env bun

/**
 * Mock Worker - Simulates Free Agent behavior for testing
 *
 * Polls controller for jobs, downloads source, simulates build, uploads result
 * Useful for testing controller without real VMs
 */

import { mkdirSync, existsSync, rmSync, writeFileSync, readFileSync, createWriteStream } from 'fs';
import { join } from 'path';
import { pipeline } from 'stream/promises';
import archiver from 'archiver';

interface MockWorkerConfig {
  controllerUrl: string;
  apiKey: string;
  workerName: string;
  platform: 'ios' | 'android';
  pollIntervalMs?: number;
  buildDelayMs?: number;
  failureRate?: number; // 0-1, probability of build failure
}

class MockWorker {
  private config: MockWorkerConfig;
  private workerId: string | null = null;
  private accessToken: string | null = null;
  private workDir: string;
  private running = false;
  private currentBuild: string | null = null;

  constructor(config: MockWorkerConfig) {
    this.config = {
      pollIntervalMs: 5000,
      buildDelayMs: 3000,
      failureRate: 0,
      ...config,
    };
    this.workDir = join(process.cwd(), '.mock-worker', this.config.workerName);
  }

  async start() {
    console.log(`[${this.config.workerName}] Starting mock worker`);

    // Setup work directory
    if (existsSync(this.workDir)) {
      rmSync(this.workDir, { recursive: true, force: true });
    }
    mkdirSync(this.workDir, { recursive: true });

    // Register with controller
    await this.register();

    // Start polling loop
    this.running = true;
    await this.pollLoop();
  }

  async stop() {
    console.log(`[${this.config.workerName}] Stopping mock worker`);
    this.running = false;

    // Cleanup
    if (existsSync(this.workDir)) {
      rmSync(this.workDir, { recursive: true, force: true });
    }
  }

  private async register() {
    console.log(`[${this.config.workerName}] Registering with controller`);

    const response = await fetch(`${this.config.controllerUrl}/api/workers/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': this.config.apiKey,
      },
      body: JSON.stringify({
        name: this.config.workerName,
        capabilities: {
          platforms: [this.config.platform],
          xcode_version: this.config.platform === 'ios' ? '15.0' : undefined,
          gradle_version: this.config.platform === 'android' ? '8.0' : undefined,
        },
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Registration failed: ${error}`);
    }

    const data = await response.json();
    this.workerId = data.id;
    this.accessToken = data.access_token;

    console.log(`[${this.config.workerName}] Registered with ID: ${this.workerId}`);
  }

  private async pollLoop() {
    while (this.running) {
      try {
        await this.poll();
      } catch (error) {
        console.error(`[${this.config.workerName}] Poll error:`, error);
      }

      // Wait before next poll
      await new Promise((resolve) => setTimeout(resolve, this.config.pollIntervalMs));
    }
  }

  private async poll() {
    if (!this.workerId || !this.accessToken) {
      throw new Error('Worker not registered');
    }

    const response = await fetch(
      `${this.config.controllerUrl}/api/workers/poll`,
      {
        headers: {
          'X-Worker-Token': this.accessToken,
        },
      }
    );

    if (!response.ok) {
      throw new Error(`Poll failed: ${response.statusText}`);
    }

    const data = await response.json();

    // Update access token (controller rotates it on each poll)
    if (data.access_token) {
      this.accessToken = data.access_token;
    }

    if (data.job) {
      await this.handleJob(data.job);
    } else {
      console.log(`[${this.config.workerName}] No jobs available`);
    }
  }

  private async handleJob(job: any) {
    console.log(`[${this.config.workerName}] Received job: ${job.id}`);
    this.currentBuild = job.id;

    try {
      // Download source
      console.log(`[${this.config.workerName}] Downloading source...`);
      const sourcePath = join(this.workDir, `${job.id}-source.zip`);
      await this.downloadFile(job.source_url, sourcePath);

      // Download certs if provided
      let certsPath: string | null = null;
      if (job.certs_url) {
        console.log(`[${this.config.workerName}] Downloading certs...`);
        certsPath = join(this.workDir, `${job.id}-certs.zip`);
        await this.downloadFile(job.certs_url, certsPath);
      }

      // Simulate build
      console.log(`[${this.config.workerName}] Building...`);
      await this.simulateBuild();

      // Check if build should fail
      const shouldFail = Math.random() < this.config.failureRate!;

      if (shouldFail) {
        console.log(`[${this.config.workerName}] Build failed (simulated)`);
        await this.uploadFailure(job.id, 'Simulated build failure');
      } else {
        // Create fake result
        const extension = job.platform === 'ios' ? 'ipa' : 'apk';
        const resultPath = join(this.workDir, `${job.id}.${extension}`);
        await this.createFakeResult(resultPath, job.id);

        // Upload result
        console.log(`[${this.config.workerName}] Uploading result...`);
        await this.uploadResult(job.id, resultPath);

        console.log(`[${this.config.workerName}] Build completed successfully`);
      }
    } catch (error) {
      console.error(`[${this.config.workerName}] Build error:`, error);
      await this.uploadFailure(
        job.id,
        error instanceof Error ? error.message : String(error)
      );
    } finally {
      this.currentBuild = null;
    }
  }

  private async downloadFile(url: string, outputPath: string): Promise<void> {
    const fullUrl = url.startsWith('http')
      ? url
      : `${this.config.controllerUrl}${url}`;

    const response = await fetch(fullUrl, {
      headers: {
        'X-Worker-Token': this.accessToken!,
      },
    });

    if (!response.ok) {
      throw new Error(`Download failed: ${response.statusText}`);
    }

    if (!response.body) {
      throw new Error('Response body is empty');
    }

    const fileStream = createWriteStream(outputPath);
    await pipeline(response.body as any, fileStream);
  }

  private async simulateBuild(): Promise<void> {
    // Simulate build time
    await new Promise((resolve) => setTimeout(resolve, this.config.buildDelayMs));
  }

  private async createFakeResult(outputPath: string, buildId: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const output = createWriteStream(outputPath);
      const archive = archiver('zip', { zlib: { level: 9 } });

      output.on('close', () => resolve());
      archive.on('error', (err) => reject(err));

      archive.pipe(output);

      // Add fake app content
      archive.append(`Mock build result for ${buildId}`, {
        name: this.config.platform === 'ios' ? 'App.app' : 'app.apk',
      });
      archive.append(JSON.stringify({ buildId, platform: this.config.platform }), {
        name: 'metadata.json',
      });

      archive.finalize();
    });
  }

  private async uploadResult(buildId: string, resultPath: string): Promise<void> {
    const form = new FormData();
    const buffer = readFileSync(resultPath);
    const blob = new Blob([buffer], { type: 'application/octet-stream' });
    form.append('result', blob, `build.${this.config.platform === 'ios' ? 'ipa' : 'apk'}`);
    form.append('build_id', buildId);
    form.append('worker_id', this.workerId!);
    form.append('success', 'true');

    const response = await fetch(`${this.config.controllerUrl}/api/workers/upload`, {
      method: 'POST',
      headers: {
        'X-Worker-Token': this.accessToken!,
      },
      body: form,
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Upload failed: ${error}`);
    }
  }

  private async uploadFailure(buildId: string, errorMessage: string): Promise<void> {
    const form = new FormData();
    form.append('build_id', buildId);
    form.append('worker_id', this.workerId!);
    form.append('success', 'false');
    form.append('error_message', errorMessage);

    const response = await fetch(`${this.config.controllerUrl}/api/workers/upload`, {
      method: 'POST',
      headers: {
        'X-Worker-Token': this.accessToken!,
      },
      body: form,
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Failure upload failed: ${error}`);
    }
  }
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    console.log(`
Mock Worker - Simulates Free Agent for testing

Usage:
  bun test/mock-worker.ts [options]

Options:
  --url <url>          Controller URL (default: http://localhost:3000)
  --api-key <key>      API key (default: dev-insecure-key-change-in-production)
  --name <name>        Worker name (default: Mock Worker)
  --platform <ios|android>  Platform (default: ios)
  --poll-interval <ms>      Poll interval in ms (default: 5000)
  --build-delay <ms>        Build simulation delay in ms (default: 3000)
  --failure-rate <0-1>      Probability of build failure (default: 0)
  --help, -h                Show this help

Examples:
  # Start basic worker
  bun test/mock-worker.ts

  # Start worker with custom config
  bun test/mock-worker.ts --url http://localhost:3000 --name "Test Worker" --platform ios

  # Start worker that fails 20% of builds
  bun test/mock-worker.ts --failure-rate 0.2
`);
    process.exit(0);
  }

  const getArg = (name: string, defaultValue: string) => {
    const index = args.indexOf(name);
    return index !== -1 && args[index + 1] ? args[index + 1] : defaultValue;
  };

  const config: MockWorkerConfig = {
    controllerUrl: getArg('--url', 'http://localhost:3000'),
    apiKey: getArg('--api-key', 'dev-insecure-key-change-in-production'),
    workerName: getArg('--name', 'Mock Worker'),
    platform: getArg('--platform', 'ios') as 'ios' | 'android',
    pollIntervalMs: parseInt(getArg('--poll-interval', '5000')),
    buildDelayMs: parseInt(getArg('--build-delay', '3000')),
    failureRate: parseFloat(getArg('--failure-rate', '0')),
  };

  const worker = new MockWorker(config);

  // Handle shutdown
  process.on('SIGINT', async () => {
    console.log('\nShutting down...');
    await worker.stop();
    process.exit(0);
  });

  process.on('SIGTERM', async () => {
    await worker.stop();
    process.exit(0);
  });

  try {
    await worker.start();
  } catch (error) {
    console.error('Worker error:', error);
    process.exit(1);
  }
}

// Run if executed directly
if (import.meta.main) {
  main();
}

export { MockWorker, type MockWorkerConfig };
