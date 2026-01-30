# Testing Guide

Comprehensive test suite for Expo Free Agent distributed build system.

## Overview

Three test levels:
1. **Unit/Integration Tests** - Component-level tests (Bun test runner)
2. **E2E Tests** - Full system flow (bash script)
3. **Manual Tests** - Real VM builds

## Quick Start

```bash
# Run all tests
bun run test:all

# Run specific test suite
bun run test:controller    # Controller tests
bun run test:cli          # CLI tests
bun run test:e2e          # End-to-end test

# Run from packages
cd packages/controller && bun test
cd cli && bun test
```

## Test Structure

```
expo-free-agent/
├── packages/controller/src/__tests__/
│   ├── integration.test.ts    # Basic integration tests
│   └── e2e.test.ts            # Comprehensive E2E tests
├── cli/src/__tests__/
│   └── integration.test.ts    # CLI integration tests
├── test/
│   ├── mock-worker.ts         # Mock Free Agent worker
│   └── fixtures/
│       ├── minimal-expo-app/  # Test Expo project
│       ├── test-helpers.ts    # Shared utilities
│       └── README.md          # Fixtures documentation
└── test-e2e.sh                # End-to-end bash script
```

## Controller Tests

**Location:** `packages/controller/src/__tests__/`

### Integration Tests (`integration.test.ts`)

Basic tests for controller functionality:
- Health check endpoint
- API authentication
- Worker registration
- Worker polling

**Run:**
```bash
cd packages/controller
bun test src/__tests__/integration.test.ts
```

### E2E Tests (`e2e.test.ts`)

Comprehensive tests covering:

**Authentication:**
- Health endpoint (no auth)
- Missing API key rejection
- Invalid API key rejection
- Valid API key acceptance

**Worker Registration:**
- Valid registration
- Missing name rejection
- Missing capabilities rejection

**Build Submission:**
- Source file only
- Source + certs
- Missing source rejection
- Missing platform rejection
- Invalid platform rejection

**Build Status:**
- Get build status
- Non-existent build (404)

**Worker Polling:**
- Receive assigned job
- Get same job on subsequent poll
- Missing worker_id rejection
- Invalid worker_id rejection

**File Download:**
- Download source (worker auth)
- Download certs (worker auth)
- Missing worker header rejection
- Wrong worker rejection

**Build Upload:**
- Upload successful result
- Verify completed status
- Download completed build

**Build Failure:**
- Report build failure
- Verify failed status with error
- Download rejection for failed build

**Build Logs:**
- Retrieve build logs
- Verify log entries

**Queue Persistence:**
- Submit build
- Restart controller
- Verify queue restored

**Run:**
```bash
cd packages/controller
bun test src/__tests__/e2e.test.ts
```

## CLI Tests

**Location:** `packages/cli/src/__tests__/integration.test.ts`

Tests for CLI API client:

**Authentication:**
- Reject missing API key
- Accept valid API key

**Build Submission:**
- Submit with project file
- Reject missing project
- Handle large files

**Build Status:**
- Get build status
- Handle non-existent build
- Poll status multiple times

**Build Download:**
- Download completed build
- Track download progress
- Handle download failures
- Prevent path traversal

**List Builds:**
- List all builds
- Handle empty list

**Error Handling:**
- Retry on timeout
- Fail after max retries
- Handle malformed JSON
- Handle server errors

**Config Management:**
- Initialize with config URL
- Handle missing config

**Concurrent Requests:**
- Multiple simultaneous requests
- Parallel downloads without leaks

**Input Validation:**
- Validate build ID format
- Validate file paths
- Reject oversized files

**Run:**
```bash
cd cli
bun test
```

## Mock Worker

**Location:** `test/mock-worker.ts`

Simulates Free Agent behavior for testing without real VMs.

**Features:**
- Worker registration
- Job polling
- Source/certs download
- Build simulation (configurable delay)
- Result upload
- Failure simulation (configurable rate)

**Usage:**
```bash
# Basic usage
bun test/mock-worker.ts

# Custom configuration
bun test/mock-worker.ts \
  --url http://localhost:3000 \
  --api-key your-api-key \
  --name "Test Worker" \
  --platform ios \
  --poll-interval 5000 \
  --build-delay 3000 \
  --failure-rate 0.2

# Get help
bun test/mock-worker.ts --help
```

**Options:**
- `--url` - Controller URL (default: http://localhost:3000)
- `--api-key` - API key (default: dev-insecure-key-change-in-production)
- `--name` - Worker name (default: Mock Worker)
- `--platform` - ios or android (default: ios)
- `--poll-interval` - Poll interval in ms (default: 5000)
- `--build-delay` - Build simulation delay in ms (default: 3000)
- `--failure-rate` - Probability of failure 0-1 (default: 0)

## E2E Test Script

**Location:** `test-e2e.sh`

Bash script testing complete system flow.

**Steps:**
1. Start controller on port 3100
2. Create test Expo project
3. Submit build via API
4. Start mock worker
5. Wait for build completion
6. Verify build status
7. Download build result
8. Verify build logs
9. Test concurrent builds
10. Verify queue stats

**Run:**
```bash
./test-e2e.sh
```

**Output:**
- Colored progress indicators
- Detailed step logging
- Error messages with context
- Test artifacts in `.test-e2e-integration/`

**Test Artifacts:**
- `controller.log` - Controller output
- `worker.log` - Mock worker output
- `result.ipa` - Downloaded build
- `project.zip` - Submitted project

## Test Helpers

**Location:** `test/fixtures/test-helpers.ts`

Shared utilities for tests.

**Functions:**
- `createTestExpoProject(dir)` - Create minimal Expo project
- `zipDirectory(sourceDir, outputPath)` - Zip directory
- `createZipWithFiles(outputPath, files)` - Create zip with specific files
- `createFakeCertificate(outputPath)` - Fake .p12 cert
- `createFakeProvisioningProfile(outputPath)` - Fake .mobileprovision
- `waitFor(condition, timeoutMs)` - Wait for async condition
- `retry(operation, maxRetries)` - Retry with backoff
- `formatBytes(bytes)` - Human-readable bytes
- `isValidBuildId(buildId)` - Validate nanoid format
- `isValidWorkerId(workerId)` - Validate nanoid format

**Constants:**
- `expectedResponses` - Expected API response shapes
- `invalidInputs` - Test cases for negative testing

See `test/fixtures/README.md` for detailed documentation.

## Running Tests in CI/CD

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Bun
        uses: oven-sh/setup-bun@v1

      - name: Install dependencies
        run: bun install

      - name: Run controller tests
        run: bun run test:controller

      - name: Run CLI tests
        run: bun run test:cli

      - name: Run E2E tests
        run: bun run test:e2e
```

## Test Coverage

Critical paths covered:
- ✅ Authentication (API key validation)
- ✅ Build submission (upload)
- ✅ Worker registration
- ✅ Worker polling (job assignment)
- ✅ File download (source/certs with auth)
- ✅ Build result upload
- ✅ Build status tracking
- ✅ Build logs
- ✅ Queue persistence across restarts
- ✅ Error handling (missing files, invalid data)
- ✅ Concurrent operations
- ✅ Input validation
- ✅ Path traversal prevention

## Writing New Tests

### Controller Test Example

```typescript
import { describe, test, expect } from 'bun:test';

describe('New Feature', () => {
  test('should do something', async () => {
    const response = await fetch(`${baseUrl}/api/new-endpoint`, {
      headers: { 'X-API-Key': apiKey },
    });

    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data).toMatchObject(expectedShape);
  });
});
```

### CLI Test Example

```typescript
import { test, expect } from 'bun:test';
import { APIClient } from '../api-client';

test('should handle new scenario', async () => {
  const client = new APIClient(mockUrl);
  const result = await client.newMethod();

  expect(result).toBeDefined();
});
```

### Using Test Helpers

```typescript
import {
  createTestExpoProject,
  zipDirectory,
  waitFor
} from '../test/fixtures/test-helpers';

const projectDir = join(testDir, 'project');
createTestExpoProject(projectDir);

const zipPath = join(testDir, 'project.zip');
await zipDirectory(projectDir, zipPath);

await waitFor(async () => {
  const status = await apiClient.getBuildStatus(buildId);
  return status.status === 'completed';
}, 30000);
```

## Debugging Tests

### View Test Output

```bash
# Verbose output
bun test --verbose

# Watch mode
bun test --watch

# Specific test file
bun test path/to/test.ts
```

### Debug E2E Script

```bash
# Keep test artifacts
TEST_DIR=".test-e2e-integration"
./test-e2e.sh

# View logs after failure
cat .test-e2e-integration/controller.log
cat .test-e2e-integration/worker.log
```

### Common Issues

**Port already in use:**
```bash
# Find process using port
lsof -i :3000

# Kill process
kill -9 <PID>
```

**Test database locked:**
```bash
# Remove old test databases
rm -rf .test-*
```

**Mock worker not connecting:**
- Check controller is running
- Verify API key matches
- Check firewall/network

## Performance Benchmarks

Expected test durations:
- Controller integration: ~5s
- Controller E2E: ~30s
- CLI integration: ~10s
- E2E script: ~60s
- Full suite: ~2min

## Best Practices

1. **Isolation** - Each test creates own data, no shared state
2. **Cleanup** - Always cleanup in afterAll hooks
3. **Async** - Use async/await, not callbacks
4. **Timeouts** - Set reasonable timeouts for async operations
5. **Assertions** - Multiple specific assertions over single generic
6. **Negative Tests** - Test error cases, not just happy path
7. **Real Data** - Use realistic test data (actual zip files, etc)
8. **No Flake** - Tests must be deterministic, no random failures

## Troubleshooting

### Tests Hang

Check for:
- Missing await on async operations
- Infinite loops in polling logic
- Server not starting (check port availability)

### Tests Fail Intermittently

Check for:
- Race conditions (multiple workers claiming same build)
- Timing issues (increase timeouts)
- Cleanup not completing before next test

### Tests Fail in CI but Pass Locally

Check for:
- Environment differences (ports, paths)
- Missing dependencies
- Timing differences (slower CI machines)

## Future Test Coverage

Areas for expansion:
- Load testing (hundreds of concurrent builds)
- Stress testing (worker failures, network issues)
- Security testing (injection attacks, auth bypass attempts)
- Performance testing (large file uploads, many workers)
- Real iOS/Android builds (integration with actual VMs)
