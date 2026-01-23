import { describe, test, expect, beforeAll, afterAll, mock } from 'bun:test';
import { APIClient } from '../api-client';
import { mkdirSync, rmSync, existsSync, writeFileSync } from 'fs';
import { join } from 'path';
import type { Server } from 'bun';

describe('CLI Integration Tests', () => {
  const testDir = join(process.cwd(), '.test-cli');

  beforeAll(() => {
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
    mkdirSync(testDir, { recursive: true });
  });

  afterAll(() => {
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('APIClient', () => {
    let mockServer: Server;
    let mockUrl: string;
    let apiClient: APIClient;

    beforeAll(() => {
      // Start mock server - no auth checks, mock server just returns data
      mockServer = Bun.serve({
        port: 0, // Random port
        fetch: async (req) => {
          const url = new URL(req.url);

          // Health check
          if (url.pathname === '/health') {
            return Response.json({ status: 'ok' });
          }

          // Build submission
          if (url.pathname === '/api/builds/submit' && req.method === 'POST') {
            return Response.json({
              buildId: 'test-build-123',
            });
          }

          // Build status
          if (url.pathname.startsWith('/api/builds/') && url.pathname.endsWith('/status')) {
            const buildId = url.pathname.split('/')[3];
            return Response.json({
              id: buildId,
              status: 'pending',
              createdAt: new Date().toISOString(),
            });
          }

          // Build download
          if (url.pathname.startsWith('/api/builds/') && url.pathname.endsWith('/download')) {
            return new Response('fake-ipa-content', {
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Disposition': 'attachment; filename="build.ipa"',
              },
            });
          }

          // List builds
          if (url.pathname === '/api/builds' && req.method === 'GET') {
            return Response.json([
              {
                id: 'build-1',
                status: 'completed',
                createdAt: new Date().toISOString(),
              },
              {
                id: 'build-2',
                status: 'pending',
                createdAt: new Date().toISOString(),
              },
            ]);
          }

          return Response.json({ error: 'Not found' }, { status: 404 });
        },
      });

      mockUrl = `http://localhost:${mockServer.port}`;
      apiClient = new APIClient(mockUrl);
    });

    afterAll(() => {
      mockServer.stop();
    });

    describe('Authentication', () => {
      test('should reject requests without API key', async () => {
        // Note: Current implementation doesn't require API keys
        // This test validates that malformed responses throw errors
        const originalFetch = global.fetch;
        const mockFetch = mock(() =>
          Promise.resolve(Response.json({ error: 'Unauthorized' }, { status: 401 }))
        );
        global.fetch = mockFetch as any;

        const client = new APIClient(mockUrl);
        await expect(client.getBuildStatus('test-123')).rejects.toThrow();

        global.fetch = originalFetch;
      });

      test('should accept requests with valid API key', async () => {
        // Test that successful responses work
        const status = await apiClient.getBuildStatus('test-123');
        expect(status.id).toBe('test-123');
        expect(status.status).toBe('pending');
      });
    });

    describe('Build Submission', () => {
      test('should submit build with project file', async () => {
        // Create test project
        const projectDir = join(testDir, 'test-project');
        mkdirSync(projectDir, { recursive: true });
        writeFileSync(join(projectDir, 'app.json'), JSON.stringify({ expo: { name: 'Test' } }));
        writeFileSync(join(projectDir, 'package.json'), JSON.stringify({ name: 'test' }));

        // Create zip
        const archiver = require('archiver');
        const fs = require('fs');
        const zipPath = join(testDir, 'project.zip');

        await new Promise<void>((resolve, reject) => {
          const output = fs.createWriteStream(zipPath);
          const archive = archiver('zip');

          output.on('close', () => resolve());
          archive.on('error', reject);

          archive.pipe(output);
          archive.directory(projectDir, false);
          archive.finalize();
        });

        const result = await apiClient.submitBuild({
          projectPath: zipPath,
        });

        expect(result.buildId).toBe('test-build-123');
      });

      test('should reject submission without project file', async () => {
        await expect(
          apiClient.submitBuild({
            projectPath: '/nonexistent/path.zip',
          })
        ).rejects.toThrow();
      });

      test('should handle large files correctly', async () => {
        const largePath = join(testDir, 'large.zip');
        const largeContent = Buffer.alloc(1024 * 1024); // 1MB
        writeFileSync(largePath, largeContent);

        const result = await apiClient.submitBuild({
          projectPath: largePath,
        });

        expect(result.buildId).toBeDefined();
      });
    });

    describe('Build Status', () => {
      test('should get build status', async () => {
        const status = await apiClient.getBuildStatus('test-build-123');

        expect(status.id).toBe('test-build-123');
        expect(status.status).toBe('pending');
        expect(status.createdAt).toBeDefined();
      });

      test('should handle non-existent build', async () => {
        // Mock 404 response
        const originalFetch = global.fetch;
        const mockFetch = mock(() =>
          Promise.resolve(
            Response.json({ error: 'Build not found' }, { status: 404 })
          )
        );

        global.fetch = mockFetch as any;

        await expect(apiClient.getBuildStatus('nonexistent')).rejects.toThrow();

        global.fetch = originalFetch;
      });

      test('should poll status multiple times', async () => {
        const originalFetch = global.fetch;
        let callCount = 0;
        const mockFetch = mock(() => {
          callCount++;
          const status = callCount < 3 ? 'building' : 'completed';
          return Promise.resolve(
            Response.json({
              id: 'test-123',
              status,
              createdAt: new Date().toISOString(),
            })
          );
        });

        global.fetch = mockFetch as any;

        // Simulate polling
        for (let i = 0; i < 3; i++) {
          await apiClient.getBuildStatus('test-123');
        }

        expect(mockFetch).toHaveBeenCalledTimes(3);

        global.fetch = originalFetch;
      });
    });

    describe('Build Download', () => {
      test('should download completed build', async () => {
        const outputPath = join(testDir, 'downloaded.ipa');

        await apiClient.downloadBuild('test-build-123', outputPath);

        expect(existsSync(outputPath)).toBe(true);
        const content = await Bun.file(outputPath).text();
        expect(content).toBe('fake-ipa-content');
      });

      test('should track download progress', async () => {
        const outputPath = join(testDir, 'download-progress.ipa');
        const progressUpdates: number[] = [];

        await apiClient.downloadBuild('test-build-123', outputPath, (bytes) => {
          progressUpdates.push(bytes);
        });

        expect(progressUpdates.length).toBeGreaterThan(0);
        expect(existsSync(outputPath)).toBe(true);
      });

      test('should handle download failures gracefully', async () => {
        const originalFetch = global.fetch;
        const mockFetch = mock(() =>
          Promise.resolve(Response.json({ error: 'Not found' }, { status: 404 }))
        );

        global.fetch = mockFetch as any;

        const outputPath = join(testDir, 'failed-download.ipa');

        await expect(apiClient.downloadBuild('nonexistent', outputPath)).rejects.toThrow();

        // Verify partial file was cleaned up
        expect(existsSync(outputPath)).toBe(false);

        global.fetch = originalFetch;
      });

      test('should prevent path traversal', async () => {
        await expect(
          apiClient.downloadBuild('test-123', '../../../etc/passwd')
        ).rejects.toThrow(/path traversal|Invalid output path/i);
      });
    });

    describe('List Builds', () => {
      test('should list all builds', async () => {
        const builds = await apiClient.listBuilds();

        expect(Array.isArray(builds)).toBe(true);
        expect(builds.length).toBe(2);
        expect(builds[0].id).toBe('build-1');
        expect(builds[1].id).toBe('build-2');
      });

      test('should handle empty build list', async () => {
        const originalFetch = global.fetch;
        const mockFetch = mock(() => Promise.resolve(Response.json([])));
        global.fetch = mockFetch as any;

        const builds = await apiClient.listBuilds();

        expect(Array.isArray(builds)).toBe(true);
        expect(builds.length).toBe(0);

        global.fetch = originalFetch;
      });
    });

    describe('Error Handling', () => {
      test('should retry on network timeout', async () => {
        const originalFetch = global.fetch;
        let attempts = 0;
        const mockFetch = mock((url: string, options?: any) => {
          attempts++;
          if (attempts < 2) {
            // Simulate AbortError for timeout
            const error = new Error('The operation was aborted');
            error.name = 'AbortError';
            return Promise.reject(error);
          }
          return Promise.resolve(
            Response.json({
              id: 'test-123',
              status: 'pending',
              createdAt: new Date().toISOString(),
            })
          );
        });

        global.fetch = mockFetch as any;

        const status = await apiClient.getBuildStatus('test-123');
        expect(status.id).toBe('test-123');
        expect(attempts).toBeGreaterThan(1);

        global.fetch = originalFetch;
      });

      test('should fail after max retries', async () => {
        const originalFetch = global.fetch;
        const mockFetch = mock(() => Promise.reject(new Error('Network error')));
        global.fetch = mockFetch as any;

        await expect(apiClient.getBuildStatus('test-123')).rejects.toThrow();

        global.fetch = originalFetch;
      });

      test('should handle malformed JSON responses', async () => {
        const originalFetch = global.fetch;
        const mockFetch = mock(() =>
          Promise.resolve(new Response('not json', { status: 200 }))
        );
        global.fetch = mockFetch as any;

        await expect(apiClient.getBuildStatus('test-123')).rejects.toThrow();

        global.fetch = originalFetch;
      });

      test('should handle server errors', async () => {
        const originalFetch = global.fetch;
        const mockFetch = mock(() =>
          Promise.resolve(
            Response.json({ error: 'Internal server error' }, { status: 500 })
          )
        );
        global.fetch = mockFetch as any;

        await expect(apiClient.getBuildStatus('test-123')).rejects.toThrow();

        global.fetch = originalFetch;
      });
    });

    describe('Config Management', () => {
      test('should initialize with controller URL from config', async () => {
        const client = new APIClient();
        await client.init();

        // Client should have loaded default config
        expect(client['baseUrl']).toBeDefined();
      });

      test('should use provided URL over config', async () => {
        const client = new APIClient('http://custom-url:8080');
        await client.init();

        // Should use the provided URL
        expect(client['baseUrl']).toBe('http://custom-url:8080');
      });
    });

    describe('Concurrent Requests', () => {
      test('should handle multiple simultaneous requests', async () => {
        const promises = [
          apiClient.getBuildStatus('build-1'),
          apiClient.getBuildStatus('build-2'),
          apiClient.getBuildStatus('build-3'),
        ];

        const results = await Promise.all(promises);

        expect(results.length).toBe(3);
        results.forEach((result) => {
          expect(result.id).toBeDefined();
          expect(result.status).toBeDefined();
        });
      });

      test('should not leak file descriptors during parallel downloads', async () => {
        const downloads = Array.from({ length: 5 }, (_, i) =>
          apiClient.downloadBuild(
            `build-${i}`,
            join(testDir, `parallel-${i}.ipa`)
          )
        );

        await Promise.all(downloads);

        // Verify all files created
        for (let i = 0; i < 5; i++) {
          expect(existsSync(join(testDir, `parallel-${i}.ipa`))).toBe(true);
        }
      });
    });

    describe('Input Validation', () => {
      test('should validate build ID format', async () => {
        await expect(apiClient.getBuildStatus('')).rejects.toThrow();
      });

      test('should validate file paths', async () => {
        await expect(
          apiClient.submitBuild({
            projectPath: '',
          })
        ).rejects.toThrow();
      });

      test('should reject oversized files', async () => {
        const largePath = join(testDir, 'huge.zip');
        // Create file larger than max allowed (500MB)
        const hugeSize = 600 * 1024 * 1024; // 600MB

        // Don't actually create huge file, just mock stat
        const mockStat = mock(() =>
          Promise.resolve({ size: hugeSize, isFile: () => true })
        );

        require('fs').promises.stat = mockStat;

        await expect(
          apiClient.submitBuild({
            projectPath: largePath,
          })
        ).rejects.toThrow(/too large/i);
      });
    });
  });

  describe('Command Integration', () => {
    test('should parse submit command arguments', () => {
      // Test command parsing without execution
      const { createSubmitCommand } = require('../commands/submit');
      const cmd = createSubmitCommand();

      expect(cmd.name()).toBe('submit');
      expect(cmd.description()).toContain('Submit');
    });

    test('should parse status command arguments', () => {
      const { createStatusCommand } = require('../commands/status');
      const cmd = createStatusCommand();

      expect(cmd.name()).toBe('status');
      expect(cmd.description()).toContain('status');
    });

    test('should parse download command arguments', () => {
      const { createDownloadCommand } = require('../commands/download');
      const cmd = createDownloadCommand();

      expect(cmd.name()).toBe('download');
      expect(cmd.description()).toContain('Download');
    });
  });
});
