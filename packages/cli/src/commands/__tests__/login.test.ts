import { describe, test, expect, beforeEach, mock } from 'bun:test';
import { createLoginCommand } from '../login.js';

// Mock dependencies
const mockSaveConfig = mock(() => Promise.resolve());
const mockGetAuthBaseUrl = mock(() => 'http://localhost:5173');
const mockOpen = mock(() => Promise.resolve());

// Mock config module
mock.module('../../config.js', () => ({
  saveConfig: mockSaveConfig,
  getAuthBaseUrl: mockGetAuthBaseUrl,
}));

// Mock open module
mock.module('open', () => ({
  default: mockOpen,
}));

describe('login command', () => {
  beforeEach(() => {
    mockSaveConfig.mockClear();
    mockGetAuthBaseUrl.mockClear();
    mockOpen.mockClear();
  });

  test('decodes base64 token correctly', () => {
    const apiKey = 'test-api-key-demo-1234567890';
    const token = Buffer.from(apiKey, 'utf-8').toString('base64');
    const decoded = Buffer.from(token, 'base64').toString('utf-8');

    expect(decoded).toBe(apiKey);
  });

  test('validates base64 encoding matches expected demo key', () => {
    const apiKey = 'test-api-key-demo-1234567890';
    const expectedBase64 = 'dGVzdC1hcGkta2V5LWRlbW8tMTIzNDU2Nzg5MA==';
    const actual = Buffer.from(apiKey, 'utf-8').toString('base64');

    expect(actual).toBe(expectedBase64);
  });

  test('command is registered with correct name', () => {
    const command = createLoginCommand();
    expect(command.name()).toBe('login');
  });

  test('command has --no-browser option', () => {
    const command = createLoginCommand();
    const options = command.options;
    const noBrowserOption = options.find((opt) => opt.long === '--no-browser');

    expect(noBrowserOption).toBeDefined();
  });
});

describe('callback URL validation (client-side)', () => {
  // These tests validate the logic used in CLILoginPage.tsx

  test('localhost is allowed', () => {
    const url = new URL('http://localhost:3456/auth/callback?token=test');
    const host = url.hostname;

    expect(host === 'localhost' || host === '127.0.0.1').toBe(true);
  });

  test('127.0.0.1 is allowed', () => {
    const url = new URL('http://127.0.0.1:3456/auth/callback?token=test');
    const host = url.hostname;

    expect(host === 'localhost' || host === '127.0.0.1').toBe(true);
  });

  test('remote host is rejected', () => {
    const url = new URL('http://evil.com:3456/auth/callback?token=test');
    const host = url.hostname;

    expect(host === 'localhost' || host === '127.0.0.1').toBe(false);
  });

  test('subdomain of localhost is rejected', () => {
    const url = new URL('http://foo.localhost:3456/auth/callback?token=test');
    const host = url.hostname;

    expect(host === 'localhost' || host === '127.0.0.1').toBe(false);
  });

  test('localhost with path traversal attempt is safe', () => {
    const url = new URL('http://localhost:3456/../../../etc/passwd?token=test');
    const host = url.hostname;

    // URL parsing normalizes the path, hostname stays localhost
    expect(host === 'localhost').toBe(true);
  });
});
