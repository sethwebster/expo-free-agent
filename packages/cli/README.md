# Expo Free Agent CLI

Command-line interface for submitting builds to the Expo Free Agent distributed build system.

## Installation

```bash
cd cli
bun install
bun run build
bun link
```

## Configuration

Set the controller URL:

```bash
expo-controller config --set-url http://your-controller:3000
```

Default: `http://localhost:3000`

## Commands

### Submit a Build

```bash
expo-controller submit ./my-expo-app \
  --cert ./certs/dist.p12 \
  --profile ./profiles/adhoc.mobileprovision \
  --apple-id me@example.com
```

**Security Note:** Apple passwords are handled via environment variable `EXPO_APPLE_PASSWORD` or interactive prompt only. Never pass passwords as CLI arguments.

```bash
# Recommended: Set environment variable
export EXPO_APPLE_PASSWORD="your-app-specific-password"
expo-controller submit ./my-expo-app --apple-id me@example.com

# Alternative: Interactive prompt (password hidden)
expo-controller submit ./my-expo-app --apple-id me@example.com
# Will prompt: Enter Apple app-specific password: ****
```

Options:
- `--cert <path>` - Signing certificate (.p12)
- `--profile <path>` - Provisioning profile (.mobileprovision)
- `--apple-id <email>` - Apple ID for notarization

**File Size Limits:**
- Maximum upload size: 500MB per file
- Larger files will be rejected with a clear error message

### Check Build Status

```bash
expo-controller status <build-id>
```

Watch progress:

```bash
expo-controller status <build-id> --watch
```

**Watch Mode Features:**
- Max watch time: 30 minutes (prevents infinite polling)
- Exponential backoff: Starts at 2s, increases to max 30s between polls
- Auto-retry: Retries up to 5 consecutive errors before giving up

### Download Build

```bash
expo-controller download <build-id>
```

Custom output path:

```bash
expo-controller download <build-id> -o ./my-app.ipa
```

**Security:**
- Output paths are validated to prevent directory traversal attacks
- Downloads must stay within current working directory
- Files are streamed to disk (no memory exhaustion on large files)
- Shows download progress with speed indicator
- Partial files are cleaned up on error

### List Builds

```bash
expo-controller list
```

Limit results:

```bash
expo-controller list --limit 20
```

### Manage Configuration

```bash
# Show current config
expo-controller config --show

# Set controller URL
expo-controller config --set-url http://controller:3000
```

## Security Best Practices

### Credentials Handling

**NEVER:**
- Pass passwords as CLI arguments (they appear in shell history)
- Log or display passwords in output
- Commit passwords to version control

**ALWAYS:**
- Use `EXPO_APPLE_PASSWORD` environment variable for automation
- Use interactive prompts for manual builds (password hidden as `****`)
- Store credentials in secure credential managers
- Use app-specific passwords (not main Apple ID password)

### File Operations

- All downloads are validated to prevent path traversal (`../../../etc/passwd`)
- Output files must be within current working directory
- File sizes are validated before upload (max 500MB)
- Partial downloads are cleaned up on failure

### Network Security

- All HTTP requests have 30s timeout (prevents hang)
- Automatic retry on network failures (max 3 attempts)
- Response data validated with Zod schemas
- Status polling uses exponential backoff (prevents server overload)
- Watch mode has 30-minute max timeout (prevents infinite loops)

### Configuration

- Config file uses atomic writes (prevents corruption on concurrent writes)
- Config stored with restricted permissions (0600)
- Temp files include PID to avoid conflicts

## Configuration File

Config stored at `~/.expo-controller/config.json`

```json
{
  "controllerUrl": "http://localhost:3000"
}
```

## Development

```bash
# Install dependencies
bun install

# Run in dev mode
bun run dev submit --help

# Build
bun run build

# Type check
bun run typecheck
```

## Architecture

- **Commander.js** - CLI framework
- **Archiver** - Zip project files
- **Form-Data** - Multipart upload
- **Ora** - Spinners
- **Chalk** - Colors
- **cli-progress** - Progress bars
- **Zod** - Schema validation

## Project Structure

```
cli/
├── src/
│   ├── index.ts              # Entry point
│   ├── config.ts             # Config management (atomic writes)
│   ├── api-client.ts         # HTTP client (timeout, retry, validation)
│   └── commands/
│       ├── submit.ts         # Submit command (secure password handling)
│       ├── status.ts         # Status command (exponential backoff)
│       ├── download.ts       # Download command (streaming, path validation)
│       ├── list.ts           # List command
│       └── config.ts         # Config command
├── package.json
└── tsconfig.json
```

## API Client

The `APIClient` class handles all communication with the controller:

```typescript
import { apiClient } from './api-client.js';

// Submit build
const { buildId } = await apiClient.submitBuild({
  projectPath: './project.zip',
  certPath: './cert.p12',
  profilePath: './adhoc.mobileprovision',
  appleId: 'me@example.com'
  // applePassword read from EXPO_APPLE_PASSWORD env var
});

// Check status
const status = await apiClient.getBuildStatus(buildId);

// Download artifact (streams to disk, not memory)
await apiClient.downloadBuild(buildId, './output.ipa', (bytes) => {
  console.log(`Downloaded: ${bytes} bytes`);
});

// List all builds
const builds = await apiClient.listBuilds();
```

## Error Handling

All commands include comprehensive error handling:

### Network Errors
- 30-second timeout on all requests
- Automatic retry (max 3 attempts) with 1s delay
- Clear error messages on failure

### File Errors
- File not found
- File too large (>500MB)
- Invalid file paths (directory traversal)
- Disk full

### Validation Errors
- Invalid build IDs
- Invalid project structure (missing app.json/app.config.js)
- Invalid API responses (Zod schema validation)
- Controller unreachable

Errors displayed with color and context.

## Features

### Submit Command
- Validates Expo project structure
- Zips project (excludes node_modules, .git, etc.)
- Validates file sizes before upload (rejects >500MB)
- Secure password handling (env var or interactive prompt)
- Shows file size
- Uploads with timeout and retry
- Returns build ID

### Status Command
- Single check or watch mode
- Progress bar when watching
- Exponential backoff (2s → 30s between polls)
- Max watch time: 30 minutes
- Shows duration
- Suggests next steps
- Handles network errors gracefully (5 consecutive = abort)

### Download Command
- Verifies build completed before download
- Confirms overwrites
- Streams to disk (no memory exhaustion)
- Path traversal protection
- Shows progress and download speed
- Cleans up partial files on error

### List Command
- Shows recent builds
- Colored status indicators
- Created timestamps
- Build durations
- Configurable limit
- Response validation

## Requirements

- Node.js 18+
- Bun (recommended)
- Controller running and accessible

## Troubleshooting

### "Request timeout" errors
- Controller may be overloaded or unreachable
- Check network connectivity
- Verify controller URL with `expo-controller config --show`

### "File too large" errors
- Max file size: 500MB
- Ensure `node_modules` is excluded from zip
- Check `.expo-controller` excludes in submit command

### "Path traversal detected" errors
- Download output path must be within current directory
- Use relative paths like `./output.ipa` or `builds/app.ipa`
- Avoid `..` in paths

### "Apple password required" errors
- Set `EXPO_APPLE_PASSWORD` environment variable
- Or omit `--apple-id` flag if not needed
- Use app-specific password, not main Apple ID password

## Changelog

### v1.1.0 - Security Hardening
- Added Zod validation for all API responses
- Streaming downloads (no memory exhaustion)
- File size limits (500MB max)
- Path traversal protection
- Request timeouts (30s) and retry logic (3x)
- Exponential backoff for status polling
- Max watch timeout (30 min)
- Atomic config writes (race condition fix)
- Secure password handling (env var + interactive prompt only)
- Progress indicators for downloads

### v1.0.0 - Initial Release
- Basic submit, status, download, list commands
- Config management
- Watch mode for status
