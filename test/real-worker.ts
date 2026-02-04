#!/usr/bin/env bun

/**
 * Real Worker - Full integration test with actual Tart VMs
 *
 * Tests complete flow:
 * - Worker registration
 * - Polling for jobs
 * - Tart VM creation
 * - Bootstrap script execution
 * - OTP → VM token exchange
 * - Certificate installation (iOS)
 * - Real build execution inside VM
 * - Artifact upload
 * - VM cleanup
 */

import { mkdirSync, existsSync, rmSync, writeFileSync, readFileSync } from 'fs';
import { join } from 'path';
import { $ } from 'bun';

interface RealWorkerConfig {
  controllerUrl: string;
  apiKey: string;
  workerName: string;
  platform: 'ios' | 'android';
  pollIntervalMs?: number;
  baseVMImage: string;  // e.g., "sequoia-vanilla" or "ghcr.io/sethwebster/expo-free-agent-base:latest"
  buildTimeout?: number;  // Max time for build in seconds
  vmControllerUrl?: string;  // Optional override URL for VM to access controller (e.g., ngrok URL)
}

interface BuildJob {
  id: string;
  platform: string;
  source_url: string;
  certs_url?: string;
  submitted_at: string;
  otp: string;  // OTP token for VM authentication
}

interface VMStatus {
  status: 'ready' | 'failed';
  vm_token?: string;
  error?: string;
}

class RealWorker {
  private config: RealWorkerConfig;
  private workerId: string | null = null;
  private accessToken: string | null = null;
  private workDir: string;
  private running = false;
  private currentBuild: string | null = null;
  private currentVM: string | null = null;

  constructor(config: RealWorkerConfig) {
    this.config = {
      pollIntervalMs: 5000,
      buildTimeout: 1800, // 30 minutes
      ...config,
    };
    this.workDir = join(process.cwd(), 'worker', this.config.workerName);
  }

  async start() {
    console.log(`[${this.config.workerName}] Starting real worker with Tart VMs`);

    // Verify prerequisites
    await this.checkPrerequisites();

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
    console.log(`[${this.config.workerName}] Stopping real worker`);
    this.running = false;

    // Cleanup any running VMs
    if (this.currentVM) {
      await this.cleanupVM(this.currentVM);
    }

    // Cleanup work directory
    if (existsSync(this.workDir)) {
      rmSync(this.workDir, { recursive: true, force: true });
    }
  }

  private async checkPrerequisites() {
    console.log(`[${this.config.workerName}] Checking prerequisites...`);

    // Check Tart is installed
    try {
      const result = await $`/opt/homebrew/bin/tart --version`.quiet();
      console.log(`[${this.config.workerName}] ✓ Tart installed: ${result.stdout.toString().trim()}`);
    } catch (error) {
      throw new Error('Tart not found. Install with: brew install cirruslabs/cli/tart');
    }

    // Check base image exists (prefer local test image)
    const images = await $`/opt/homebrew/bin/tart list`.text();
    const localImage = 'expo-free-agent-base-local';

    if (this.config.baseVMImage === 'ghcr.io/sethwebster/expo-free-agent-base:latest') {
      // Auto-detect: prefer local test image if available
      if (images.split('\n').some(line => line.split(/\s+/)[1] === localImage)) {
        this.config.baseVMImage = localImage;
        console.log(`[${this.config.workerName}] ✓ Using local test image: ${localImage}`);
        console.log(`[${this.config.workerName}]   (Built with latest local scripts)`);
      } else {
        console.log(`[${this.config.workerName}] ✓ Base VM image available: ${this.config.baseVMImage}`);
        console.log(`[${this.config.workerName}]   For local testing: ./vm-setup/setup-local-test-image.sh`);
      }
    } else if (!images.includes(this.config.baseVMImage)) {
      throw new Error(`Base VM image '${this.config.baseVMImage}' not found. Available images:\n${images}`);
    } else {
      console.log(`[${this.config.workerName}] ✓ Base VM image available: ${this.config.baseVMImage}`);
    }

    // Check free-agent-bootstrap.sh exists
    const bootstrapPath = join(process.cwd(), 'free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh');
    if (!existsSync(bootstrapPath)) {
      throw new Error(`Bootstrap script not found at ${bootstrapPath}`);
    }
    console.log(`[${this.config.workerName}] ✓ Bootstrap script found`);
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
          xcode_version: this.config.platform === 'ios' ? '16.2' : undefined,
          gradle_version: this.config.platform === 'android' ? '8.0' : undefined,
          tart_version: (await $`/opt/homebrew/bin/tart --version`.text()).trim(),
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

    console.log(`[${this.config.workerName}] ✓ Registered with ID: ${this.workerId}`);
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

  private async handleJob(job: BuildJob) {
    console.log(`[${this.config.workerName}] Received job: ${job.id}`);
    this.currentBuild = job.id;

    // Use job ID directly - Tart doesn't allow hyphens in VM names
    const vmName = job.id;
    this.currentVM = vmName;

    try {
      // Step 1: Clone VM from base image
      console.log(`[${this.config.workerName}] Cloning VM from ${this.config.baseVMImage}...`);
      await this.cloneVM(vmName);

      // Step 2: Prepare build config directory
      console.log(`[${this.config.workerName}] Preparing build config...`);
      const buildConfigDir = await this.prepareBuildConfig(job);

      // Step 3: Start VM with mounted config
      console.log(`[${this.config.workerName}] Starting VM...`);
      await this.startVM(vmName, buildConfigDir);

      // Step 4: Wait for bootstrap to complete
      console.log(`[${this.config.workerName}] Waiting for VM bootstrap...`);
      const vmStatus = await this.waitForBootstrap(buildConfigDir);

      if (vmStatus.status === 'failed') {
        throw new Error(`VM bootstrap failed: ${vmStatus.error}`);
      }

      console.log(`[${this.config.workerName}] ✓ VM bootstrapped successfully`);

      // Step 5: Wait for build completion
      console.log(`[${this.config.workerName}] Waiting for build to complete...`);
      await this.waitForBuildCompletion(buildConfigDir);

      console.log(`[${this.config.workerName}] ✓ Build completed successfully`);

    } catch (error) {
      console.error(`[${this.config.workerName}] Build failed:`, error);

      // Report failure to controller
      await this.uploadFailure(job.id, error instanceof Error ? error.message : String(error));
    } finally {
      // Step 6: Cleanup VM
      if (this.currentVM) {
        console.log(`[${this.config.workerName}] Cleaning up VM...`);
        await this.cleanupVM(this.currentVM);
        this.currentVM = null;
      }
      this.currentBuild = null;
    }
  }

  private async cloneVM(vmName: string) {
    await $`/opt/homebrew/bin/tart clone ${this.config.baseVMImage} ${vmName}`.quiet();
  }

  private async prepareBuildConfig(job: BuildJob): Promise<string> {
    // Use simple alphanumeric directory name for Tart compatibility
    const buildConfigDir = join(this.workDir, job.id, 'config');
    mkdirSync(buildConfigDir, { recursive: true });

    // Get controller URL accessible from VM
    // Use vmControllerUrl if provided (e.g., ngrok URL), otherwise try to make it accessible
    let vmAccessibleUrl = this.config.vmControllerUrl || this.config.controllerUrl;

    if (!this.config.vmControllerUrl) {
      // No override URL provided - try to make localhost accessible
      if (vmAccessibleUrl.includes('localhost') || vmAccessibleUrl.includes('127.0.0.1')) {
        // For Tart VMs, the host is accessible at the bridge gateway (192.168.64.1 by default)
        const hostIP = '192.168.64.1';
        vmAccessibleUrl = vmAccessibleUrl.replace(/localhost|127\.0\.0\.1/, hostIP);
        console.log(`[${this.config.workerName}] Controller URL for VM: ${vmAccessibleUrl} (host: ${hostIP})`);
      }
    } else {
      console.log(`[${this.config.workerName}] Using provided VM controller URL: ${vmAccessibleUrl}`);
    }

    // Write build-config.json
    const config = {
      build_id: job.id,
      build_token: job.otp,  // OTP token for VM authentication
      controller_url: vmAccessibleUrl,
      platform: job.platform,
    };

    writeFileSync(
      join(buildConfigDir, 'build-config.json'),
      JSON.stringify(config, null, 2)
    );

    // Copy bootstrap script
    const bootstrapSource = join(
      process.cwd(),
      'free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh'
    );
    const bootstrapDest = join(buildConfigDir, 'bootstrap.sh');

    const bootstrapContent = readFileSync(bootstrapSource, 'utf-8');
    writeFileSync(bootstrapDest, bootstrapContent, { mode: 0o755 });

    return buildConfigDir;
  }

  private async startVM(vmName: string, buildConfigDir: string) {
    // Start VM in background with mounted directory
    // Tart --dir format: [name:]path[:options]
    // Mounts to /Volumes/My Shared Files/<name> inside VM
    // Stub script expects "build-config" as the mount name
    const tartProcess = Bun.spawn([
      '/opt/homebrew/bin/tart',
      'run',
      '--dir',
      `build-config:${buildConfigDir}`,
      vmName
    ], {
      stdout: 'inherit',
      stderr: 'inherit',
    });

    // Give VM a few seconds to start
    await new Promise(resolve => setTimeout(resolve, 5000));

    // VM will auto-run bootstrap script via LaunchAgent
    console.log(`[${this.config.workerName}] VM started, bootstrap should begin automatically`);
  }

  private async waitForBootstrap(buildConfigDir: string, timeoutSec: number = 300): Promise<VMStatus> {
    const readyFile = join(buildConfigDir, 'vm-ready');
    const startTime = Date.now();

    while (Date.now() - startTime < timeoutSec * 1000) {
      if (existsSync(readyFile)) {
        const content = readFileSync(readyFile, 'utf-8');
        const status: VMStatus = JSON.parse(content);
        return status;
      }

      // Check progress file for updates
      const progressFile = join(buildConfigDir, 'progress.json');
      if (existsSync(progressFile)) {
        const progress = JSON.parse(readFileSync(progressFile, 'utf-8'));
        console.log(`[${this.config.workerName}] VM progress: ${progress.phase} (${progress.progress_percent}%) - ${progress.message}`);
      }

      await new Promise(resolve => setTimeout(resolve, 2000));
    }

    throw new Error(`VM bootstrap timeout after ${timeoutSec}s`);
  }

  private async waitForBuildCompletion(buildConfigDir: string): Promise<void> {
    const completeFile = join(buildConfigDir, 'build-complete');
    const errorFile = join(buildConfigDir, 'build-error');
    const startTime = Date.now();
    const timeoutMs = this.config.buildTimeout! * 1000;

    while (Date.now() - startTime < timeoutMs) {
      // Check for completion
      if (existsSync(completeFile)) {
        const result = JSON.parse(readFileSync(completeFile, 'utf-8'));
        console.log(`[${this.config.workerName}] Build completed at ${result.completed_at}`);
        return;
      }

      // Check for errors
      if (existsSync(errorFile)) {
        const error = JSON.parse(readFileSync(errorFile, 'utf-8'));
        throw new Error(`Build failed: ${error.error}`);
      }

      // Check progress
      const progressFile = join(buildConfigDir, 'progress.json');
      if (existsSync(progressFile)) {
        const progress = JSON.parse(readFileSync(progressFile, 'utf-8'));
        console.log(`[${this.config.workerName}] Build progress: ${progress.phase} (${progress.progress_percent}%) - ${progress.message}`);
      }

      await new Promise(resolve => setTimeout(resolve, 5000));
    }

    throw new Error(`Build timeout after ${this.config.buildTimeout}s`);
  }

  private async cleanupVM(vmName: string) {
    try {
      // Stop VM if running
      await $`/opt/homebrew/bin/tart stop ${vmName}`.quiet();
      await new Promise(resolve => setTimeout(resolve, 2000));
    } catch (error) {
      // VM might already be stopped
    }

    try {
      // Delete VM
      await $`/opt/homebrew/bin/tart delete ${vmName}`.quiet();
      console.log(`[${this.config.workerName}] ✓ VM deleted: ${vmName}`);
    } catch (error) {
      console.error(`[${this.config.workerName}] Failed to delete VM:`, error);
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
Real Worker - Full integration test with Tart VMs

Usage:
  bun test/real-worker.ts [options]

Options:
  --url <url>              Controller URL (required)
  --api-key <key>          API key (required)
  --name <name>            Worker name (default: "Real Worker")
  --platform <ios|android> Platform (default: "ios")
  --base-image <name>      Tart base image (default: "ghcr.io/sethwebster/expo-free-agent-base:latest")
  --poll-interval <ms>     Poll interval (default: 5000)
  --build-timeout <sec>    Build timeout (default: 1800)
  --vm-controller-url <url> Override URL for VM access (e.g., ngrok URL)
  --help, -h               Show this help

Prerequisites:
  - Tart installed: brew install cirruslabs/cli/tart
  - Base VM image: tart pull ghcr.io/sethwebster/expo-free-agent-base:latest
  - Bootstrap script at: free-agent/Sources/WorkerCore/Resources/free-agent-bootstrap.sh

Example:
  # Pull base image first
  tart pull ghcr.io/sethwebster/expo-free-agent-base:latest

  # Run worker
  bun test/real-worker.ts \\
    --url http://localhost:4444 \\
    --api-key e2e-test-api-key-minimum-32-characters-long \\
    --platform ios
`);
    process.exit(0);
  }

  const config: RealWorkerConfig = {
    controllerUrl: args[args.indexOf('--url') + 1] || 'http://localhost:4444',
    apiKey: args[args.indexOf('--api-key') + 1] || 'test-api-key',
    workerName: args[args.indexOf('--name') + 1] || 'Real Worker',
    platform: (args[args.indexOf('--platform') + 1] as 'ios' | 'android') || 'ios',
    baseVMImage: args[args.indexOf('--base-image') + 1] || 'ghcr.io/sethwebster/expo-free-agent-base:latest',
    pollIntervalMs: args.includes('--poll-interval')
      ? parseInt(args[args.indexOf('--poll-interval') + 1])
      : undefined,
    buildTimeout: args.includes('--build-timeout')
      ? parseInt(args[args.indexOf('--build-timeout') + 1])
      : undefined,
    vmControllerUrl: args.includes('--vm-controller-url')
      ? args[args.indexOf('--vm-controller-url') + 1]
      : undefined,
  };

  const worker = new RealWorker(config);

  // Handle graceful shutdown
  process.on('SIGINT', async () => {
    console.log('\nShutting down...');
    await worker.stop();
    process.exit(0);
  });

  try {
    await worker.start();
  } catch (error) {
    console.error('Worker error:', error);
    await worker.stop();
    process.exit(1);
  }
}

main();
