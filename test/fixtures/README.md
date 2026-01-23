# Test Fixtures

Test data and helpers for integration tests.

## Minimal Expo App

A minimal Expo project for testing build submissions.

**Location:** `./minimal-expo-app/`

**Contents:**
- `app.json` - Expo configuration
- `package.json` - Dependencies
- `App.js` - Main component

**Usage:**
```typescript
import { createTestExpoProject, zipDirectory } from './test-helpers';

const projectDir = join(testDir, 'project');
createTestExpoProject(projectDir);

const zipPath = join(testDir, 'project.zip');
await zipDirectory(projectDir, zipPath);
```

## Test Helpers

Shared utilities for tests.

**Location:** `./test-helpers.ts`

### Functions

**`createTestExpoProject(dir: string)`**
Creates minimal Expo project in directory.

**`zipDirectory(sourceDir: string, outputPath: string)`**
Zips directory contents.

**`createZipWithFiles(outputPath: string, files: Record<string, string>)`**
Creates zip with specific files/content.

**`createFakeCertificate(outputPath: string)`**
Creates fake .p12 certificate for testing.

**`createFakeProvisioningProfile(outputPath: string)`**
Creates fake .mobileprovision for testing.

**`waitFor(condition: () => Promise<boolean>, timeoutMs?: number)`**
Waits for async condition with timeout.

**`retry(operation: () => Promise<T>, maxRetries?: number)`**
Retries operation with exponential backoff.

**`formatBytes(bytes: number): string`**
Human-readable byte formatting.

**`isValidBuildId(buildId: string): boolean`**
Validates nanoid build ID format.

**`isValidWorkerId(workerId: string): boolean`**
Validates nanoid worker ID format.

### Constants

**`expectedResponses`**
Expected API response shapes for validation:
- `buildSubmission`
- `buildStatus`
- `workerRegistration`
- `workerPoll`
- `buildLogs`

**`invalidInputs`**
Test cases for negative testing:
- `buildSubmission` - Missing/invalid fields
- `workerRegistration` - Missing/invalid fields
- `workerPoll` - Missing/invalid worker_id

## Usage Examples

### Basic Test
```typescript
import { createTestExpoProject, zipDirectory } from './test-helpers';

const projectDir = join(testDir, 'project');
createTestExpoProject(projectDir);

const zipPath = join(testDir, 'project.zip');
await zipDirectory(projectDir, zipPath);

const result = await apiClient.submitBuild({
  projectPath: zipPath,
});

expect(result).toMatchObject(expectedResponses.buildSubmission);
```

### Negative Testing
```typescript
import { invalidInputs } from './test-helpers';

for (const testCase of invalidInputs.buildSubmission) {
  await expect(
    apiClient.submitBuild(testCase.data)
  ).rejects.toThrow(testCase.expectedError);
}
```

### Wait for Condition
```typescript
import { waitFor } from './test-helpers';

await waitFor(async () => {
  const status = await apiClient.getBuildStatus(buildId);
  return status.status === 'completed';
}, 30000); // 30s timeout
```

### Retry with Backoff
```typescript
import { retry } from './test-helpers';

const result = await retry(
  () => apiClient.submitBuild({ projectPath }),
  3, // max retries
  1000 // initial delay ms
);
```
