import { describe, test, expect, beforeAll, afterAll } from 'bun:test';
import { ControllerServer } from '../server';
import { createConfig } from '../domain/Config';
import { mkdirSync, rmSync, existsSync, writeFileSync, readFileSync } from 'fs';
import { join } from 'path';
import archiver from 'archiver';

describe('Controller E2E Tests', () => {
  const testDir = join(process.cwd(), '.test-e2e');
  const dbPath = join(testDir, 'test.db');
  const storagePath = join(testDir, 'storage');
  const apiKey = 'test-api-key-1234567890';

  let server: ControllerServer;
  let baseUrl: string;

  beforeAll(async () => {
    // Clean up and create test directories
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
    mkdirSync(testDir, { recursive: true });

    // Create server
    const config = createConfig({
      port: 3002, // Use different port
      dbPath,
      storagePath,
      apiKey,
    });

    server = new ControllerServer(config);
    await server.start();
    baseUrl = `http://localhost:3002`;
  });

  afterAll(async () => {
    await server.stop();

    // Clean up
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('Authentication', () => {
    test('health endpoint should not require auth', async () => {
      const response = await fetch(`${baseUrl}/health`);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.status).toBe('ok');
      expect(data.queue).toBeDefined();
      expect(data.storage).toBeDefined();
    });

    test('API endpoints should reject missing API key', async () => {
      const response = await fetch(`${baseUrl}/api/builds/test123/status`);
      expect(response.status).toBe(401);

      const data = await response.json();
      expect(data.error).toContain('X-API-Key');
    });

    test('API endpoints should reject invalid API key', async () => {
      const response = await fetch(`${baseUrl}/api/builds/test123/status`, {
        headers: { 'X-API-Key': 'invalid-key' },
      });
      expect(response.status).toBe(403);

      const data = await response.json();
      expect(data.error).toContain('Invalid');
    });

    test('API endpoints should accept valid API key', async () => {
      const response = await fetch(`${baseUrl}/api/builds/nonexistent/status`, {
        headers: { 'X-API-Key': apiKey },
      });
      // 404 is fine - auth passed, build not found
      expect(response.status).toBe(404);
    });
  });

  describe('Worker Registration', () => {
    test('should register worker with valid data', async () => {
      const response = await fetch(`${baseUrl}/api/workers/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: JSON.stringify({
          name: 'Test Worker 1',
          capabilities: {
            platforms: ['ios'],
            xcode_version: '15.0',
          },
        }),
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.status).toBe('registered');
      expect(data.id).toBeDefined();
      expect(typeof data.id).toBe('string');
    });

    test('should reject registration without name', async () => {
      const response = await fetch(`${baseUrl}/api/workers/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: JSON.stringify({
          capabilities: { platforms: ['ios'] },
        }),
      });

      expect(response.status).toBe(400);
    });

    test('should reject registration without capabilities', async () => {
      const response = await fetch(`${baseUrl}/api/workers/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: JSON.stringify({
          name: 'Worker',
        }),
      });

      expect(response.status).toBe(400);
    });
  });

  describe('Build Submission', () => {
    test('should submit build with source file', async () => {
      const form = new FormData();

      // Create test zip file
      const zipPath = join(testDir, 'test-source.zip');
      await createTestZip(zipPath, { 'app.json': '{"expo": {"name": "Test"}}' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');
      form.append('platform', 'ios');

      const response = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });

      if (response.status !== 200) {
        const error = await response.text();
        console.error('Submit error:', error);
      }
      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.id).toBeDefined();
      expect(data.status).toBe('pending');
      expect(data.submitted_at).toBeDefined();
    });

    test('should submit build with source and certs', async () => {
      const form = new FormData();

      const sourcePath = join(testDir, 'source-with-certs.zip');
      const certsPath = join(testDir, 'certs.zip');

      await createTestZip(sourcePath, { 'package.json': '{}' });
      await createTestZip(certsPath, { 'cert.p12': 'fake-cert' });

      const sourceBuffer = readFileSync(sourcePath);
      const certsBuffer = readFileSync(certsPath);
      const sourceBlob = new Blob([sourceBuffer], { type: 'application/zip' });
      const certsBlob = new Blob([certsBuffer], { type: 'application/zip' });

      form.append('source', sourceBlob, 'source.zip');
      form.append('certs', certsBlob, 'certs.zip');
      form.append('platform', 'ios');

      const response = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.id).toBeDefined();
    });

    test('should reject build without source file', async () => {
      const form = new FormData();
      form.append('platform', 'ios');

      const response = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });

      expect(response.status).toBe(400);
      const data = await response.json();
      expect(data.error).toContain('Source file required');
    });

    test('should reject build without platform', async () => {
      const form = new FormData();
      const zipPath = join(testDir, 'no-platform.zip');
      await createTestZip(zipPath, { 'test.txt': 'data' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');

      const response = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });

      expect(response.status).toBe(400);
      const data = await response.json();
      expect(data.error).toContain('platform');
    });

    test('should reject build with invalid platform', async () => {
      const form = new FormData();
      const zipPath = join(testDir, 'invalid-platform.zip');
      await createTestZip(zipPath, { 'test.txt': 'data' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');
      form.append('platform', 'windows');

      const response = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });

      expect(response.status).toBe(400);
      const data = await response.json();
      expect(data.error).toContain('platform');
    });
  });

  describe('Build Status', () => {
    let buildId: string;

    beforeAll(async () => {
      // Submit a build
      const form = new FormData();
      const zipPath = join(testDir, 'status-test.zip');
      await createTestZip(zipPath, { 'test.txt': 'data' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');
      form.append('platform', 'ios');

      const response = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });

      const data = await response.json();
      buildId = data.id;
    });

    test('should return build status', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/status`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.id).toBe(buildId);
      expect(data.status).toBe('pending');
      expect(data.platform).toBe('ios');
      expect(data.submitted_at).toBeDefined();
    });

    test('should return 404 for non-existent build', async () => {
      const response = await fetch(`${baseUrl}/api/builds/nonexistent/status`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(404);
    });
  });

  describe('Worker Polling', () => {
    let workerId: string;
    let buildId: string;

    test('worker should receive assigned job', async () => {
      // Register worker
      const registerResponse = await fetch(`${baseUrl}/api/workers/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: JSON.stringify({
          name: 'Poll Test Worker',
          capabilities: { platforms: ['ios'] },
        }),
      });
      const registerData = await registerResponse.json();
      workerId = registerData.id;

      // Submit a build
      const form = new FormData();
      const zipPath = join(testDir, 'poll-test.zip');
      await createTestZip(zipPath, { 'test.txt': 'data' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');
      form.append('platform', 'ios');

      const submitResponse = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });
      const submitData = await submitResponse.json();

      // Now poll for a job (may get this build or an earlier pending one)
      const response = await fetch(`${baseUrl}/api/workers/poll?worker_id=${workerId}`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.job).toBeDefined();
      // Store the actual assigned build ID for next test
      buildId = data.job.id;
      expect(data.job.platform).toBe('ios');
      expect(data.job.source_url).toContain('/api/builds/');
    });

    test('worker should get same job on subsequent poll', async () => {
      const response = await fetch(`${baseUrl}/api/workers/poll?worker_id=${workerId}`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.job.id).toBe(buildId);
    });

    test('poll should fail without worker_id', async () => {
      const response = await fetch(`${baseUrl}/api/workers/poll`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(400);
    });

    test('poll should fail with invalid worker_id', async () => {
      const response = await fetch(`${baseUrl}/api/workers/poll?worker_id=invalid`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(404);
    });
  });

  describe('File Download', () => {
    let workerId: string;
    let buildId: string;

    beforeAll(async () => {
      // Register worker
      const registerResponse = await fetch(`${baseUrl}/api/workers/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: JSON.stringify({
          name: 'Download Test Worker',
          capabilities: { platforms: ['ios'] },
        }),
      });
      const registerData = await registerResponse.json();
      workerId = registerData.id;

      // Submit build with certs
      const form = new FormData();
      const sourcePath = join(testDir, 'download-source.zip');
      const certsPath = join(testDir, 'download-certs.zip');

      await createTestZip(sourcePath, { 'test.txt': 'source-content' });
      await createTestZip(certsPath, { 'cert.txt': 'cert-content' });

      const sourceBuffer = readFileSync(sourcePath);
      const certsBuffer = readFileSync(certsPath);
      const sourceBlob = new Blob([sourceBuffer], { type: 'application/zip' });
      const certsBlob = new Blob([certsBuffer], { type: 'application/zip' });

      form.append('source', sourceBlob, 'source.zip');
      form.append('certs', certsBlob, 'certs.zip');
      form.append('platform', 'ios');

      const submitResponse = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });
      const submitData = await submitResponse.json();
      buildId = submitData.id;

      // Assign to worker and capture actual assigned build ID
      const pollResponse = await fetch(`${baseUrl}/api/workers/poll?worker_id=${workerId}`, {
        headers: { 'X-API-Key': apiKey },
      });
      const pollData = await pollResponse.json();
      // Update buildId to match what was actually assigned
      buildId = pollData.job.id;
    });

    test('worker should download source file', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/source`, {
        headers: {
          'X-API-Key': apiKey,
          'X-Worker-Id': workerId,
        },
      });

      expect(response.status).toBe(200);
      expect(response.headers.get('content-type')).toBe('application/zip');

      const buffer = await response.arrayBuffer();
      expect(buffer.byteLength).toBeGreaterThan(0);
    });

    test('worker should download certs file', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/certs`, {
        headers: {
          'X-API-Key': apiKey,
          'X-Worker-Id': workerId,
        },
      });

      expect(response.status).toBe(200);
      expect(response.headers.get('content-type')).toBe('application/zip');

      const buffer = await response.arrayBuffer();
      expect(buffer.byteLength).toBeGreaterThan(0);
    });

    test('download should fail without worker header', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/source`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(401);
    });

    test('download should fail with wrong worker', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/source`, {
        headers: {
          'X-API-Key': apiKey,
          'X-Worker-Id': 'wrong-worker',
        },
      });

      expect(response.status).toBe(403);
    });
  });

  describe('Build Upload and Download', () => {
    let workerId: string;
    let buildId: string;

    beforeAll(async () => {
      // Register worker
      const registerResponse = await fetch(`${baseUrl}/api/workers/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: JSON.stringify({
          name: 'Upload Test Worker',
          capabilities: { platforms: ['ios'] },
        }),
      });
      const registerData = await registerResponse.json();
      workerId = registerData.id;

      // Submit and assign build
      const form = new FormData();
      const zipPath = join(testDir, 'upload-test.zip');
      await createTestZip(zipPath, { 'test.txt': 'data' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');
      form.append('platform', 'ios');

      const submitResponse = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });
      const submitData = await submitResponse.json();
      buildId = submitData.id;

      await fetch(`${baseUrl}/api/workers/poll?worker_id=${workerId}`, {
        headers: { 'X-API-Key': apiKey },
      });
    });

    test('worker should upload successful build result', async () => {
      const form = new FormData();
      const resultPath = join(testDir, 'result.ipa');
      await createTestZip(resultPath, { 'app.ipa': 'fake-ipa-content' });

      const buffer = readFileSync(resultPath);
      const blob = new Blob([buffer], { type: 'application/octet-stream' });
      form.append('result', blob, 'build.ipa');
      form.append('build_id', buildId);
      form.append('worker_id', workerId);
      form.append('success', 'true');

      const response = await fetch(`${baseUrl}/api/workers/upload`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.status).toBe('success');
    });

    test('build status should show completed', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/status`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.status).toBe('completed');
      expect(data.completed_at).toBeDefined();
    });

    test('should download completed build', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/download`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(200);
      expect(response.headers.get('content-disposition')).toContain('.ipa');

      const buffer = await response.arrayBuffer();
      expect(buffer.byteLength).toBeGreaterThan(0);
    });
  });

  describe('Build Failure', () => {
    let workerId: string;
    let buildId: string;

    beforeAll(async () => {
      // Register worker
      const registerResponse = await fetch(`${baseUrl}/api/workers/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: JSON.stringify({
          name: 'Failure Test Worker',
          capabilities: { platforms: ['ios'] },
        }),
      });
      const registerData = await registerResponse.json();
      workerId = registerData.id;

      // Submit and assign build
      const form = new FormData();
      const zipPath = join(testDir, 'failure-test.zip');
      await createTestZip(zipPath, { 'test.txt': 'data' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');
      form.append('platform', 'ios');

      const submitResponse = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });
      const submitData = await submitResponse.json();
      buildId = submitData.id;

      await fetch(`${baseUrl}/api/workers/poll?worker_id=${workerId}`, {
        headers: { 'X-API-Key': apiKey },
      });
    });

    test('worker should report build failure', async () => {
      const form = new FormData();
      form.append('build_id', buildId);
      form.append('worker_id', workerId);
      form.append('success', 'false');
      form.append('error_message', 'Build failed: compilation error');

      const response = await fetch(`${baseUrl}/api/workers/upload`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.status).toBe('failed');
    });

    test('build status should show failed with error', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/status`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.status).toBe('failed');
      expect(data.error_message).toBe('Build failed: compilation error');
    });

    test('download should fail for failed build', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/download`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(400);
    });
  });

  describe('Build Logs', () => {
    let buildId: string;

    beforeAll(async () => {
      const form = new FormData();
      const zipPath = join(testDir, 'logs-test.zip');
      await createTestZip(zipPath, { 'test.txt': 'data' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');
      form.append('platform', 'ios');

      const response = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });
      const data = await response.json();
      buildId = data.id;
    });

    test('should retrieve build logs', async () => {
      const response = await fetch(`${baseUrl}/api/builds/${buildId}/logs`, {
        headers: { 'X-API-Key': apiKey },
      });

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.build_id).toBe(buildId);
      expect(Array.isArray(data.logs)).toBe(true);
      expect(data.logs.length).toBeGreaterThan(0);
      expect(data.logs[0].message).toBe('Build submitted');
    });
  });

  describe('Queue Persistence', () => {
    test('queue state should persist across restart', async () => {
      // Submit build
      const form = new FormData();
      const zipPath = join(testDir, 'persistence-test.zip');
      await createTestZip(zipPath, { 'test.txt': 'data' });

      const buffer = readFileSync(zipPath);
      const blob = new Blob([buffer], { type: 'application/zip' });
      form.append('source', blob, 'source.zip');
      form.append('platform', 'ios');

      const submitResponse = await fetch(`${baseUrl}/api/builds/submit`, {
        method: 'POST',
        headers: {
          'X-API-Key': apiKey,
        },
        body: form,
      });
      const { id: buildId } = await submitResponse.json();

      // Check it's in queue
      const healthBefore = await fetch(`${baseUrl}/health`);
      const healthDataBefore = await healthBefore.json();
      expect(healthDataBefore.queue.pending).toBeGreaterThan(0);

      // Restart server
      await server.stop();

      const config = createConfig({
        port: 3002,
        dbPath,
        storagePath,
        apiKey,
      });
      server = new ControllerServer(config);
      await server.start();

      // Check build still exists
      const statusResponse = await fetch(`${baseUrl}/api/builds/${buildId}/status`, {
        headers: { 'X-API-Key': apiKey },
      });
      expect(statusResponse.status).toBe(200);

      const statusData = await statusResponse.json();
      expect(statusData.status).toBe('pending');

      // Check queue restored
      const healthAfter = await fetch(`${baseUrl}/health`);
      const healthDataAfter = await healthAfter.json();
      expect(healthDataAfter.queue.pending).toBeGreaterThan(0);
    });
  });
});

// Helper function to create test zip files
async function createTestZip(outputPath: string, files: Record<string, string>): Promise<void> {
  return new Promise((resolve, reject) => {
    const output = require('fs').createWriteStream(outputPath);
    const archive = archiver('zip', { zlib: { level: 9 } });

    output.on('close', () => resolve());
    archive.on('error', (err: Error) => reject(err));

    archive.pipe(output);

    for (const [filename, content] of Object.entries(files)) {
      archive.append(content, { name: filename });
    }

    archive.finalize();
  });
}
