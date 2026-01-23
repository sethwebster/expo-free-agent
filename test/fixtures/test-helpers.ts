/**
 * Test Helpers
 * Shared utilities for integration tests
 */

import { mkdirSync, writeFileSync } from 'fs';
import { join } from 'path';
import archiver from 'archiver';
import { createWriteStream } from 'fs';

/**
 * Create a minimal Expo project for testing
 */
export function createTestExpoProject(dir: string): void {
  mkdirSync(dir, { recursive: true });

  // app.json
  writeFileSync(
    join(dir, 'app.json'),
    JSON.stringify(
      {
        expo: {
          name: 'Test App',
          slug: 'test-app',
          version: '1.0.0',
          platforms: ['ios', 'android'],
          ios: {
            bundleIdentifier: 'com.test.app',
          },
          android: {
            package: 'com.test.app',
          },
        },
      },
      null,
      2
    )
  );

  // package.json
  writeFileSync(
    join(dir, 'package.json'),
    JSON.stringify(
      {
        name: 'test-app',
        version: '1.0.0',
        main: 'index.js',
        dependencies: {
          expo: '^50.0.0',
          react: '18.2.0',
          'react-native': '0.73.0',
        },
      },
      null,
      2
    )
  );

  // index.js
  writeFileSync(
    join(dir, 'index.js'),
    `
import { registerRootComponent } from 'expo';
import App from './App';

registerRootComponent(App);
`.trim()
  );

  // App.js
  writeFileSync(
    join(dir, 'App.js'),
    `
import React from 'react';
import { View, Text } from 'react-native';

export default function App() {
  return (
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
      <Text>Test App</Text>
    </View>
  );
}
`.trim()
  );
}

/**
 * Create a zip file from directory
 */
export async function zipDirectory(sourceDir: string, outputPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const output = createWriteStream(outputPath);
    const archive = archiver('zip', { zlib: { level: 9 } });

    output.on('close', () => resolve());
    archive.on('error', (err) => reject(err));

    archive.pipe(output);
    archive.directory(sourceDir, false);
    archive.finalize();
  });
}

/**
 * Create a zip file with specific files
 */
export async function createZipWithFiles(
  outputPath: string,
  files: Record<string, string>
): Promise<void> {
  return new Promise((resolve, reject) => {
    const output = createWriteStream(outputPath);
    const archive = archiver('zip', { zlib: { level: 9 } });

    output.on('close', () => resolve());
    archive.on('error', (err) => reject(err));

    archive.pipe(output);

    for (const [filename, content] of Object.entries(files)) {
      archive.append(content, { name: filename });
    }

    archive.finalize();
  });
}

/**
 * Create fake signing certificate (for testing invalid certs)
 */
export function createFakeCertificate(outputPath: string): void {
  writeFileSync(
    outputPath,
    `-----BEGIN CERTIFICATE-----
FAKE_CERTIFICATE_FOR_TESTING
THIS_IS_NOT_A_REAL_CERTIFICATE
-----END CERTIFICATE-----`
  );
}

/**
 * Create fake provisioning profile (for testing invalid profiles)
 */
export function createFakeProvisioningProfile(outputPath: string): void {
  writeFileSync(
    outputPath,
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Name</key>
  <string>Test Profile</string>
  <key>TeamIdentifier</key>
  <array>
    <string>FAKE123456</string>
  </array>
</dict>
</plist>`
  );
}

/**
 * Expected API response shapes for validation
 */
export const expectedResponses = {
  buildSubmission: {
    id: expect.any(String),
    status: 'pending',
    submitted_at: expect.any(Number),
  },

  buildStatus: {
    id: expect.any(String),
    status: expect.stringMatching(/^(pending|assigned|building|completed|failed)$/),
    platform: expect.stringMatching(/^(ios|android)$/),
    submitted_at: expect.any(Number),
  },

  workerRegistration: {
    id: expect.any(String),
    status: 'registered',
  },

  workerPoll: {
    job: expect.any(Object),
  },

  buildLogs: {
    build_id: expect.any(String),
    logs: expect.arrayContaining([
      expect.objectContaining({
        timestamp: expect.any(Number),
        level: expect.stringMatching(/^(info|warn|error)$/),
        message: expect.any(String),
      }),
    ]),
  },
};

/**
 * Invalid test inputs for negative testing
 */
export const invalidInputs = {
  buildSubmission: [
    {
      name: 'missing source',
      data: { platform: 'ios' },
      expectedError: /source.*required/i,
    },
    {
      name: 'missing platform',
      data: { source: 'file.zip' },
      expectedError: /platform.*required/i,
    },
    {
      name: 'invalid platform',
      data: { source: 'file.zip', platform: 'windows' },
      expectedError: /platform/i,
    },
  ],

  workerRegistration: [
    {
      name: 'missing name',
      data: { capabilities: { platforms: ['ios'] } },
      expectedError: /name.*required/i,
    },
    {
      name: 'missing capabilities',
      data: { name: 'Worker' },
      expectedError: /capabilities.*required/i,
    },
  ],

  workerPoll: [
    {
      name: 'missing worker_id',
      data: {},
      expectedError: /worker_id.*required/i,
    },
    {
      name: 'invalid worker_id',
      data: { worker_id: 'nonexistent' },
      expectedStatus: 404,
    },
  ],
};

/**
 * Wait for condition with timeout
 */
export async function waitFor(
  condition: () => Promise<boolean>,
  timeoutMs: number = 10000,
  intervalMs: number = 100
): Promise<void> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    if (await condition()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  throw new Error(`Timeout after ${timeoutMs}ms waiting for condition`);
}

/**
 * Retry operation with exponential backoff
 */
export async function retry<T>(
  operation: () => Promise<T>,
  maxRetries: number = 3,
  delayMs: number = 1000
): Promise<T> {
  let lastError: Error | undefined;

  for (let i = 0; i < maxRetries; i++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error as Error;
      if (i < maxRetries - 1) {
        await new Promise((resolve) => setTimeout(resolve, delayMs * Math.pow(2, i)));
      }
    }
  }

  throw lastError || new Error('Operation failed after retries');
}

/**
 * Format bytes for display
 */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

/**
 * Validate build ID format
 */
export function isValidBuildId(buildId: string): boolean {
  // nanoid generates 21 character alphanumeric IDs
  return /^[A-Za-z0-9_-]{21}$/.test(buildId);
}

/**
 * Validate worker ID format
 */
export function isValidWorkerId(workerId: string): boolean {
  return /^[A-Za-z0-9_-]{21}$/.test(workerId);
}
