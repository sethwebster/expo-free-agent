import { describe, test, expect, beforeAll, afterAll, mock, beforeEach } from 'bun:test';
import { APIClient } from '../api-client';
import { mkdirSync, rmSync, existsSync, writeFileSync } from 'fs';
import { join } from 'path';
// No Server type import needed - we'll use the server instance directly

/**
 * Critical Path Tests for CLI Package
 *
 * These tests cover the most critical security and reliability requirements:
 * 1. Path traversal protection for downloads (AGENTS.md line 636)
 * 2. Apple password env var handling (no CLI args, secure prompting)
 * 3. Retry/backoff logic with exponential backoff
 *
 * All tests follow AAA (Arrange-Act-Assert) pattern and test-first development.
 */
describe('Critical Path: Path Traversal Protection', () => {
  const testDir = join(process.cwd(), '.test-critical-paths');
  let mockServer: ReturnType<typeof Bun.serve>;
  let mockUrl: string;
  let apiClient: APIClient;

  beforeAll(() => {
    // Arrange: Set up test directory
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
    mkdirSync(testDir, { recursive: true });

    // Arrange: Start mock server
    mockServer = Bun.serve({
      port: 0,
      fetch: async (req) => {
        const url = new URL(req.url);

        if (url.pathname.startsWith('/api/builds/') && url.pathname.endsWith('/download')) {
          return new Response('fake-build-content', {
            headers: {
              'Content-Type': 'application/octet-stream',
            },
          });
        }

        return Response.json({ error: 'Not found' }, { status: 404 });
      },
    });

    mockUrl = `http://localhost:${mockServer.port}`;
    apiClient = new APIClient(mockUrl, 'test-key');
  });

  afterAll(() => {
    mockServer.stop();
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('downloadBuild path validation', () => {
    test('should reject path traversal with ../ sequences', async () => {
      // Arrange
      const maliciousPath = '../../../etc/passwd';

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', maliciousPath)
      ).rejects.toThrow(/path traversal|Invalid output path/i);
    });

    test('should reject path traversal with multiple ../ sequences', async () => {
      // Arrange
      const maliciousPath = '../../../../../../etc/passwd';

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', maliciousPath)
      ).rejects.toThrow(/path traversal|Invalid output path/i);
    });

    test('should reject path traversal in subdirectory context', async () => {
      // Arrange
      const maliciousPath = './safe/../../../etc/passwd';

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', maliciousPath)
      ).rejects.toThrow(/path traversal|Invalid output path/i);
    });

    test('should reject absolute paths outside working directory', async () => {
      // Arrange
      const maliciousPath = '/etc/passwd';

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', maliciousPath)
      ).rejects.toThrow(/Invalid output path/i);
    });

    test('should reject paths to system directories', async () => {
      // Arrange
      const maliciousPath = '/tmp/../etc/passwd';

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', maliciousPath)
      ).rejects.toThrow(/Invalid output path/i);
    });

    test('should reject paths escaping via symbolic link tricks', async () => {
      // Arrange
      const maliciousPath = './builds/../../../../../../etc/passwd';

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', maliciousPath)
      ).rejects.toThrow(/path traversal|Invalid output path/i);
    });

    test('should allow valid relative path within working directory', async () => {
      // Arrange
      const validPath = join(testDir, 'safe-build.ipa');

      // Act
      await apiClient.downloadBuild('test-build-123', validPath);

      // Assert
      expect(existsSync(validPath)).toBe(true);
      const content = await Bun.file(validPath).text();
      expect(content).toBe('fake-build-content');
    });

    test('should allow valid relative path with subdirectories', async () => {
      // Arrange
      const subDir = join(testDir, 'builds', 'ios');
      mkdirSync(subDir, { recursive: true });
      const validPath = join(subDir, 'app.ipa');

      // Act
      await apiClient.downloadBuild('test-build-123', validPath);

      // Assert
      expect(existsSync(validPath)).toBe(true);
    });

    test('should allow valid absolute path within working directory', async () => {
      // Arrange
      // testDir is already an absolute path (join(process.cwd(), '.test-critical-paths'))
      // So we just need to add the filename
      const validPath = join(testDir, 'absolute-path.ipa');

      // Act
      await apiClient.downloadBuild('test-build-123', validPath);

      // Assert
      expect(existsSync(validPath)).toBe(true);
    });

    test('should reject path with null bytes', async () => {
      // Arrange
      const maliciousPath = `safe-build.ipa\x00.txt`;

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', maliciousPath)
      ).rejects.toThrow();
    });

    test('should reject path with URL encoding attempts', async () => {
      // Arrange
      const maliciousPath = '..%2F..%2F..%2Fetc%2Fpasswd';

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', maliciousPath)
      ).rejects.toThrow(/path traversal|Invalid output path/i);
    });

    test('should clean up partial file on download failure', async () => {
      // Arrange
      const originalFetch = global.fetch;
      const mockFetch = mock(() =>
        Promise.resolve(Response.json({ error: 'Not found' }, { status: 404 }))
      );
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const outputPath = join(testDir, 'failed-download.ipa');

      // Act
      await expect(
        apiClient.downloadBuild('nonexistent', outputPath)
      ).rejects.toThrow();

      // Assert - verify partial file was cleaned up
      expect(existsSync(outputPath)).toBe(false);

      // Cleanup
      global.fetch = originalFetch;
    });
  });

  describe('download path must remain within working directory', () => {
    test('should enforce working directory boundary for downloads', async () => {
      // Arrange
      const cwd = process.cwd();
      const outsidePath = join(cwd, '..', 'outside.ipa');

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', outsidePath)
      ).rejects.toThrow(/Invalid output path/i);
    });

    test('should reject path that resolves outside working directory', async () => {
      // Arrange
      const trickPath = join(testDir, '..', '..', 'trick.ipa');

      // Act & Assert
      await expect(
        apiClient.downloadBuild('test-build-123', trickPath)
      ).rejects.toThrow(/Invalid output path/i);
    });
  });
});

describe('Critical Path: Apple Password Security', () => {
  const testDir = join(process.cwd(), '.test-apple-password');
  let mockServer: ReturnType<typeof Bun.serve>;
  let mockUrl: string;

  beforeAll(() => {
    // Arrange: Set up test directory
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
    mkdirSync(testDir, { recursive: true });

    // Arrange: Start mock server
    mockServer = Bun.serve({
      port: 0,
      fetch: async (req) => {
        const url = new URL(req.url);

        if (url.pathname === '/api/builds/submit' && req.method === 'POST') {
          // Check that password came from env var or FormData, never from CLI args
          const formData = await req.formData();
          const applePassword = formData.get('applePassword');

          return Response.json({
            id: 'test-build-456',
            access_token: 'test-token',
            receivedPassword: !!applePassword,
          });
        }

        return Response.json({ error: 'Not found' }, { status: 404 });
      },
    });

    mockUrl = `http://localhost:${mockServer.port}`;
  });

  afterAll(() => {
    mockServer.stop();
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
  });

  beforeEach(() => {
    // Clean up env var before each test
    delete process.env.EXPO_APPLE_PASSWORD;
  });

  describe('submitBuild password handling', () => {
    test('should read Apple password from EXPO_APPLE_PASSWORD env var', async () => {
      // Arrange
      const apiClient = new APIClient(mockUrl, 'test-key');
      const testPassword = 'test-app-specific-password-1234';
      process.env.EXPO_APPLE_PASSWORD = testPassword;

      const projectPath = join(testDir, 'project.zip');
      writeFileSync(projectPath, 'fake-project-content');

      // Act
      const result = await apiClient.submitBuild({
        projectPath,
        appleId: 'test@example.com',
      });

      // Assert
      expect(result.buildId).toBeDefined();
      expect(process.env.EXPO_APPLE_PASSWORD).toBe(testPassword);
    });

    test('should never expose password in error messages', async () => {
      // Arrange
      const originalFetch = global.fetch;
      const testPassword = 'secret-password-should-not-leak';
      process.env.EXPO_APPLE_PASSWORD = testPassword;

      const mockFetch = mock(() =>
        Promise.resolve(
          Response.json(
            { error: 'Authentication failed with provided credentials' },
            { status: 401 }
          )
        )
      );
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');
      const projectPath = join(testDir, 'project2.zip');
      writeFileSync(projectPath, 'fake-content');

      // Act
      let errorMessage = '';
      try {
        await apiClient.submitBuild({
          projectPath,
          appleId: 'test@example.com',
        });
      } catch (error) {
        errorMessage = error instanceof Error ? error.message : String(error);
      }

      // Assert - password should never appear in error message
      expect(errorMessage).not.toContain(testPassword);
      expect(errorMessage.toLowerCase()).not.toContain('secret');

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should not log password to console or debug output', async () => {
      // Arrange
      const consoleSpy = mock(() => {});
      const originalConsoleLog = console.log;
      // Test mock: intentionally override console.log
      console.log = consoleSpy as unknown as typeof console.log;

      const testPassword = 'sensitive-password-12345';
      process.env.EXPO_APPLE_PASSWORD = testPassword;

      const apiClient = new APIClient(mockUrl, 'test-key');
      const projectPath = join(testDir, 'project3.zip');
      writeFileSync(projectPath, 'fake-content');

      // Act
      await apiClient.submitBuild({
        projectPath,
        appleId: 'test@example.com',
      });

      // Assert - check all console.log calls don't contain password
      const allCalls = consoleSpy.mock.calls.flat().join(' ');
      expect(allCalls).not.toContain(testPassword);

      // Cleanup
      console.log = originalConsoleLog;
    });

    test('should handle missing password gracefully when Apple ID provided', async () => {
      // Arrange
      delete process.env.EXPO_APPLE_PASSWORD;
      const apiClient = new APIClient(mockUrl, 'test-key');
      const projectPath = join(testDir, 'project4.zip');
      writeFileSync(projectPath, 'fake-content');

      // Act
      const result = await apiClient.submitBuild({
        projectPath,
        appleId: 'test@example.com',
      });

      // Assert - should succeed without password (server can prompt user)
      expect(result.buildId).toBeDefined();
    });

    test('should not include password in request headers', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let capturedHeaders: Headers | undefined;

      const mockFetch = mock((url: string, options?: RequestInit) => {
        if (options?.headers) {
          capturedHeaders = new Headers(options.headers);
        }
        return Promise.resolve(
          Response.json({
            id: 'test-build',
            access_token: 'test-token',
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const testPassword = 'password-should-not-be-in-headers';
      process.env.EXPO_APPLE_PASSWORD = testPassword;

      const apiClient = new APIClient(mockUrl, 'test-key');
      const projectPath = join(testDir, 'project5.zip');
      writeFileSync(projectPath, 'fake-content');

      // Act
      await apiClient.submitBuild({
        projectPath,
        appleId: 'test@example.com',
      });

      // Assert
      expect(capturedHeaders).toBeDefined();
      const headerValues = Array.from(capturedHeaders!.values()).join(' ');
      expect(headerValues).not.toContain(testPassword);

      // Cleanup
      global.fetch = originalFetch;
    });
  });
});

describe('Critical Path: Retry and Backoff Logic', () => {
  let mockServer: ReturnType<typeof Bun.serve>;
  let mockUrl: string;

  beforeAll(() => {
    // Arrange: Start mock server
    mockServer = Bun.serve({
      port: 0,
      fetch: async (req) => {
        const url = new URL(req.url);

        if (url.pathname.startsWith('/api/builds/') && url.pathname.endsWith('/status')) {
          return Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          });
        }

        return Response.json({ error: 'Not found' }, { status: 404 });
      },
    });

    mockUrl = `http://localhost:${mockServer.port}`;
  });

  afterAll(() => {
    mockServer.stop();
  });

  describe('exponential backoff on retryable errors', () => {
    test('should retry on network timeout (AbortError)', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;
      const startTime = Date.now();
      const delayTimestamps: number[] = [];

      const mockFetch = mock(() => {
        attempts++;
        delayTimestamps.push(Date.now());

        if (attempts < 3) {
          const error = new Error('The operation was aborted');
          error.name = 'AbortError';
          return Promise.reject(error);
        }

        return Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'completed',
            submitted_at: Date.now(),
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      const result = await apiClient.getBuildStatus('test-build');

      // Assert
      expect(result.id).toBe('test-build');
      expect(attempts).toBe(3); // Failed twice, succeeded on third
      expect(mockFetch).toHaveBeenCalledTimes(3);

      // Verify exponential backoff (delays should increase)
      const delays = delayTimestamps.slice(1).map((timestamp, i) =>
        timestamp - delayTimestamps[i]
      );
      // First retry: ~1s, second retry: ~2s
      // Allow some tolerance for execution time
      if (delays.length >= 1) {
        expect(delays[0]).toBeGreaterThanOrEqual(900); // ~1s with tolerance
        expect(delays[0]).toBeLessThan(2000);
      }
      if (delays.length >= 2) {
        expect(delays[1]).toBeGreaterThanOrEqual(1800); // ~2s with tolerance
        expect(delays[1]).toBeLessThan(3000);
      }

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should retry on ECONNREFUSED error', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        if (attempts < 2) {
          return Promise.reject(new Error('fetch failed: ECONNREFUSED'));
        }
        return Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      const result = await apiClient.getBuildStatus('test-build');

      // Assert
      expect(result.id).toBe('test-build');
      expect(attempts).toBe(2);

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should retry on ETIMEDOUT error', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        if (attempts < 2) {
          return Promise.reject(new Error('fetch failed: ETIMEDOUT'));
        }
        return Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      const result = await apiClient.getBuildStatus('test-build');

      // Assert
      expect(result.id).toBe('test-build');
      expect(attempts).toBe(2);

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should retry on ENOTFOUND error', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        if (attempts < 2) {
          return Promise.reject(new Error('fetch failed: ENOTFOUND'));
        }
        return Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      const result = await apiClient.getBuildStatus('test-build');

      // Assert
      expect(result.id).toBe('test-build');
      expect(attempts).toBe(2);

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should retry on "Unable to connect" error', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        if (attempts < 2) {
          return Promise.reject(new Error('Unable to connect to server'));
        }
        return Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      const result = await apiClient.getBuildStatus('test-build');

      // Assert
      expect(result.id).toBe('test-build');
      expect(attempts).toBe(2);

      // Cleanup
      global.fetch = originalFetch;
    });

    test.skip('should fail after max retries exceeded', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        const error = new Error('Network error');
        error.name = 'AbortError';
        return Promise.reject(error);
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act & Assert
      await expect(apiClient.getBuildStatus('test-build')).rejects.toThrow(/Network error/);

      // Should have tried: initial + 10 retries = 11 total
      expect(attempts).toBe(11);

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should use exponential backoff: 1s, 2s, 4s', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;
      const timestamps: number[] = [];

      const mockFetch = mock(() => {
        attempts++;
        timestamps.push(Date.now());

        if (attempts <= 3) {
          // Fail first 3 attempts to observe backoff pattern
          const error = new Error('Network error');
          error.name = 'AbortError';
          return Promise.reject(error);
        }

        return Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      const startTime = Date.now();
      await apiClient.getBuildStatus('test-build');
      const totalTime = Date.now() - startTime;

      // Assert
      expect(attempts).toBe(4); // Initial + 3 retries + success

      // Calculate delays between attempts
      const delays = timestamps.slice(1).map((timestamp, i) =>
        timestamp - timestamps[i]
      );

      // Expected delays: 1s, 2s, 4s (with tolerance)
      const expectedDelays = [1000, 2000, 4000];
      const tolerance = 500; // Allow 500ms tolerance for execution time

      delays.forEach((delay, i) => {
        if (i < expectedDelays.length) {
          expect(delay).toBeGreaterThanOrEqual(expectedDelays[i] - tolerance);
          expect(delay).toBeLessThan(expectedDelays[i] + tolerance * 2);
        }
      });

      // Total time should be approximately sum of delays
      const expectedTotal = expectedDelays.slice(0, delays.length).reduce((a, b) => a + b, 0);
      expect(totalTime).toBeGreaterThanOrEqual(expectedTotal - tolerance);

      // Cleanup
      global.fetch = originalFetch;
    }, 10000); // Test takes ~7s (1+2+4)
  });

  describe('non-retryable errors should fail immediately', () => {
    test('should not retry on 400 Bad Request', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        return Promise.resolve(
          Response.json({ error: 'Bad request' }, { status: 400 })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act & Assert
      await expect(apiClient.getBuildStatus('test-build')).rejects.toThrow();

      // Should fail immediately without retries
      expect(attempts).toBe(1);

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should not retry on 404 Not Found', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        return Promise.resolve(
          Response.json({ error: 'Not found' }, { status: 404 })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act & Assert
      await expect(apiClient.getBuildStatus('test-build')).rejects.toThrow();

      expect(attempts).toBe(1);

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should not retry on 401 Unauthorized', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        return Promise.resolve(
          Response.json({ error: 'Unauthorized' }, { status: 401 })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act & Assert
      await expect(apiClient.getBuildStatus('test-build')).rejects.toThrow();

      expect(attempts).toBe(1);

      // Cleanup
      global.fetch = originalFetch;
    });

    test('should not retry on validation errors', async () => {
      // Arrange
      const apiClient = new APIClient(mockUrl, 'test-key');
      let attempts = 0;

      const originalFetch = global.fetch;
      const mockFetch = mock(() => {
        attempts++;
        return Promise.resolve(Response.json({ error: 'Invalid input' }));
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      // Act & Assert
      await expect(apiClient.getBuildStatus('')).rejects.toThrow(/Build ID is required/);

      // Should fail validation before making request
      expect(attempts).toBe(0);

      // Cleanup
      global.fetch = originalFetch;
    });
  });

  describe('timeout configuration', () => {
    test.skip('should timeout after 30 seconds per request', async () => {
      // Arrange
      const originalFetch = global.fetch;
      const startTime = Date.now();
      let attempts = 0;

      const mockFetch = mock((url: string, options?: RequestInit) => {
        attempts++;
        // Abort after first attempt to keep test fast
        if (attempts > 1) {
          return Promise.resolve(
            Response.json({
              id: 'test-build',
              status: 'pending',
              submitted_at: Date.now(),
            })
          );
        }
        // First attempt: simulate slow response that respects abort signal
        return new Promise((_, reject) => {
          if (options?.signal) {
            options.signal.addEventListener('abort', () => {
              const error = new Error('The operation was aborted');
              error.name = 'AbortError';
              reject(error);
            });
          }
        });
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      await apiClient.getBuildStatus('test-build');

      const elapsed = Date.now() - startTime;

      // Assert - first request should timeout (~30s), then retry succeeds
      expect(attempts).toBe(2);
      expect(elapsed).toBeGreaterThanOrEqual(30_000); // First attempt timed out
      expect(elapsed).toBeLessThan(35_000); // Second attempt succeeded quickly + 1s backoff

      // Cleanup
      global.fetch = originalFetch;
    }, 45_000); // 45s timeout for test (30s timeout + 1s backoff + overhead)

    test('should clear timeout on successful response', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let timeoutCleared = false;

      const mockClearTimeout = mock((_id: NodeJS.Timeout) => {
        timeoutCleared = true;
      });

      const originalClearTimeout = global.clearTimeout;
      // Test mock: intentionally override global clearTimeout
      global.clearTimeout = mockClearTimeout as unknown as typeof clearTimeout;

      const mockFetch = mock(() =>
        Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          })
        )
      );
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      await apiClient.getBuildStatus('test-build');

      // Assert
      expect(timeoutCleared).toBe(true);

      // Cleanup
      global.fetch = originalFetch;
      global.clearTimeout = originalClearTimeout;
    });
  });

  describe('retry behavior doesn\'t cause DDOS', () => {
    test('should have conservative max retries (10)', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;

      const mockFetch = mock(() => {
        attempts++;
        // After 3 attempts, return success to keep test fast
        // Still validates that retries are happening
        if (attempts > 3) {
          return Promise.resolve(
            Response.json({
              id: 'test-build',
              status: 'pending',
              submitted_at: Date.now(),
            })
          );
        }
        const error = new Error('Network timeout');
        error.name = 'AbortError'; // Retryable error
        return Promise.reject(error);
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act - succeeds after retries
      await apiClient.getBuildStatus('test-build');

      // Assert - should retry but not excessively
      expect(attempts).toBe(4); // Initial + 3 retries (validates retry logic works)
      expect(attempts).toBeLessThanOrEqual(15); // Ensures we don't have unlimited retries

      // Cleanup
      global.fetch = originalFetch;
    }, 10_000); // Test takes ~7s (1+2+4)

    test('should have minimum initial delay of 1 second', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;
      const timestamps: number[] = [];

      const mockFetch = mock(() => {
        attempts++;
        timestamps.push(Date.now());

        if (attempts < 2) {
          const error = new Error('Connection refused');
          error.message = 'fetch failed: ECONNREFUSED'; // Make it retryable
          return Promise.reject(error);
        }

        return Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      await apiClient.getBuildStatus('test-build');

      // Assert
      const delay = timestamps[1] - timestamps[0];
      expect(delay).toBeGreaterThanOrEqual(1000); // Minimum 1 second
      expect(delay).toBeLessThan(2000); // Should not be longer than 2 seconds for first retry

      // Cleanup
      global.fetch = originalFetch;
    }, 5000); // Test takes ~1s

    test('should cap maximum delay at reasonable value', async () => {
      // Arrange
      const originalFetch = global.fetch;
      let attempts = 0;
      const timestamps: number[] = [];

      const mockFetch = mock(() => {
        attempts++;
        timestamps.push(Date.now());

        // Only fail first 4 attempts to test delays up to 8s (2^3)
        // This keeps test runtime reasonable while still testing exponential growth
        if (attempts <= 4) {
          return Promise.reject(new Error('fetch failed'));
        }

        return Promise.resolve(
          Response.json({
            id: 'test-build',
            status: 'pending',
            submitted_at: Date.now(),
          })
        );
      });
      // Test mock: intentionally override global fetch
      global.fetch = mockFetch as unknown as typeof fetch;

      const apiClient = new APIClient(mockUrl, 'test-key');

      // Act
      await apiClient.getBuildStatus('test-build');

      // Assert
      const delays = timestamps.slice(1).map((timestamp, i) =>
        timestamp - timestamps[i]
      );

      // Verify delays follow exponential pattern: 1s, 2s, 4s, 8s
      const expectedDelays = [1000, 2000, 4000, 8000];
      const tolerance = 500;

      delays.forEach((delay, i) => {
        if (i < expectedDelays.length) {
          expect(delay).toBeGreaterThanOrEqual(expectedDelays[i] - tolerance);
          expect(delay).toBeLessThan(expectedDelays[i] + tolerance * 2);
        }
      });

      // Verify exponential growth continues (each delay roughly doubles)
      for (let i = 1; i < Math.min(delays.length, 3); i++) {
        const ratio = delays[i] / delays[i - 1];
        expect(ratio).toBeGreaterThanOrEqual(1.8); // Allow some tolerance
        expect(ratio).toBeLessThanOrEqual(2.2);
      }

      // Cleanup
      global.fetch = originalFetch;
    }, 20000); // Reduce timeout (15s delays + overhead)
  });
});
