import { describe, test, expect, beforeAll, afterAll } from 'bun:test';
import { ControllerServer } from '../server';
import { createConfig } from '../domain/Config';
import { mkdirSync, rmSync, existsSync } from 'fs';
import { join } from 'path';

describe('Controller Integration Tests', () => {
  const testDir = join(process.cwd(), '.test-integration');
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
      port: 3001, // Use different port to avoid conflicts
      dbPath,
      storagePath,
      apiKey,
    });

    server = new ControllerServer(config);
    await server.start();
    baseUrl = `http://localhost:3001`;
  });

  afterAll(async () => {
    await server.stop();

    // Clean up
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
  });

  test('health check should work without auth', async () => {
    const response = await fetch(`${baseUrl}/health`);
    expect(response.status).toBe(200);

    const data = await response.json();
    expect(data.status).toBe('ok');
  });

  test('API endpoints should require authentication', async () => {
    // No API key - should fail
    const response1 = await fetch(`${baseUrl}/api/builds/abc123/status`);
    expect(response1.status).toBe(401);

    // Wrong API key - should fail
    const response2 = await fetch(`${baseUrl}/api/builds/abc123/status`, {
      headers: { 'X-API-Key': 'wrong-key' },
    });
    expect(response2.status).toBe(403);

    // Correct API key - should work (404 for non-existent build is expected)
    const response3 = await fetch(`${baseUrl}/api/builds/abc123/status`, {
      headers: { 'X-API-Key': apiKey },
    });
    expect(response3.status).toBe(404); // Build not found, but auth passed
  });

  test('worker registration should work with valid API key', async () => {
    const response = await fetch(`${baseUrl}/api/workers/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      },
      body: JSON.stringify({
        name: 'Test Worker',
        capabilities: { platforms: ['ios'], xcode_version: '15.0' },
      }),
    });

    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.status).toBe('registered');
    expect(data.id).toBeDefined();
  });

  test('worker poll should work', async () => {
    // Register worker first
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

    const { id: workerId } = await registerResponse.json();

    // Poll for jobs
    const pollResponse = await fetch(`${baseUrl}/api/workers/poll?worker_id=${workerId}`, {
      headers: { 'X-API-Key': apiKey },
    });

    expect(pollResponse.status).toBe(200);
    const data = await pollResponse.json();
    expect(data.job).toBeNull(); // No jobs available initially
  });
});
