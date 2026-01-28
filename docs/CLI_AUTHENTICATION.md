# CLI Authentication Flow

## Overview

The Expo Free Agent CLI now uses a web-based authentication flow instead of manual API key entry. Users authenticate via a browser-based login page, and the API key is automatically stored in their local config.

## How It Works

### For Users

1. Run `expo-free-agent login` in the terminal
2. Browser opens to the login page at the landing site
3. Enter any credentials (demo mode - any credentials work)
4. Browser shows "All set!" - close the window
5. API key is automatically saved to `~/.expo-free-agent/config.json`
6. Use other CLI commands without needing to provide API key again

### No-Browser Mode

For headless environments (SSH, CI/CD debugging):
```bash
expo-free-agent login --no-browser
```
This prints the login URL instead of auto-opening the browser.

## Architecture

### CLI Login Command
- **File**: `cli/src/commands/login.ts`
- Starts local HTTP server on random port (using `get-port`)
- Opens browser to landing page with callback URL
- Waits for authentication callback (30s timeout)
- Validates callback host (localhost/127.0.0.1 only)
- Decodes base64 token and saves API key to config
- Shows success message

### Landing Page Login
- **Route**: `/#/cli/login`
- **Component**: `packages/landing-page/src/pages/CLILoginPage.tsx`
- Clean Expo-style login form (email/password)
- Demo mode: accepts any credentials
- Base64-encodes the demo API key
- Redirects to CLI callback URL with token parameter

### Security
- Callback URL validation (localhost only)
- Base64 encoding (obfuscation, not encryption - suitable for demo)
- API key stored with file permissions 0o600
- Atomic config writes (write to temp file, then rename)

## Configuration

### CLI Environment Variables
```bash
# Controller API URL
EXPO_CONTROLLER_URL=http://localhost:3000

# API Key (optional - set via login command)
EXPO_CONTROLLER_API_KEY=your-api-key-here

# Auth page URL (defaults to production)
AUTH_BASE_URL=http://localhost:5173  # Development
# AUTH_BASE_URL=https://expo-free-agent.pages.dev  # Production (default)
```

### Landing Page Environment Variables
```bash
# Controller API URL
VITE_CONTROLLER_URL=http://localhost:4000

# Auth Base URL (for CLI login redirects)
VITE_AUTH_BASE_URL=http://localhost:5173  # Development
# VITE_AUTH_BASE_URL=https://expo-free-agent.pages.dev  # Production
```

## Demo API Key

**API Key**: `test-api-key-demo-1234567890`
**Base64 Encoded**: `dGVzdC1hcGkta2V5LWRlbW8tMTIzNDU2Nzg5MA==`

## Error Handling

### Missing API Key
If API key is not found when running commands like `submit`, `status`, etc., users see:
```
API key not found. Run `expo-free-agent login` to authenticate.
Alternatively, set the EXPO_CONTROLLER_API_KEY environment variable.
```

### Authentication Timeout
If authentication takes longer than 30 seconds:
```
Authentication timeout. Please try again.
```

### Invalid Callback Host
If callback comes from non-localhost host:
```
Forbidden: Invalid callback host
```

## Backward Compatibility

The `--api-key` flag is still supported on the `submit` command for CI/CD use cases, but it's not documented prominently. Users should prefer:
- Interactive: `expo-free-agent login`
- CI/CD: `EXPO_CONTROLLER_API_KEY` environment variable

## Future Enhancements

When ready to integrate with real Expo authentication:

1. **OAuth Integration**
   - Replace demo login with real Expo OAuth flow
   - Use PKCE for security
   - Get JWT tokens from Expo auth service

2. **Per-User API Keys**
   - Controller issues unique API key per user
   - Keys linked to Expo account
   - Support for multiple accounts

3. **Token Refresh**
   - Implement token expiry
   - Auto-refresh expired tokens
   - Secure refresh token storage

4. **Token Revocation**
   - Add logout command
   - Revoke tokens on controller
   - Clear local config

## Testing

### Manual Testing
```bash
# Terminal 1: Start landing page dev server
cd packages/landing-page
bun run dev

# Terminal 2: Build and test CLI
cd cli
bun run build

# Set environment variable for local testing
export AUTH_BASE_URL=http://localhost:5173

# Test login flow
./dist/index.js login

# Verify API key stored
./dist/index.js config --show

# Test no-browser mode
./dist/index.js login --no-browser
```

### Unit Tests
```bash
cd cli
bun test src/commands/__tests__/login.test.ts
```

Tests cover:
- Base64 encoding/decoding
- Callback URL validation
- Command options
- Token handling

## Files Changed

### New Files
- `cli/src/commands/login.ts` - Login command implementation
- `cli/.env.example` - CLI environment variables example
- `packages/landing-page/src/pages/CLILoginPage.tsx` - Login page component
- `cli/src/commands/__tests__/login.test.ts` - Login command tests
- `docs/CLI_AUTHENTICATION.md` - This documentation

### Modified Files
- `cli/src/index.ts` - Register login command
- `cli/src/config.ts` - Add `getAuthBaseUrl()` helper
- `cli/src/api-client.ts` - Show helpful error when API key missing
- `packages/landing-page/src/main.tsx` - Add `/cli/login` route
- `packages/landing-page/.env.example` - Add auth base URL
- `cli/package.json` - Add `get-port` and `open` dependencies

## Dependencies Added

- `get-port` - Find available port for callback server
- `open` - Open browser to login URL
