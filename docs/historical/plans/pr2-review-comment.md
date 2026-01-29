# Code Review: CLI Login Authentication Flow

**Verdict: Request Changes**

---

## Critical Issues

### 1. Open Redirect Vulnerability

**Location:** `packages/landing-page/src/pages/CLILoginPage.tsx:17-24`

The callback URL from query params is used directly for redirect without validation. An attacker can craft:
```
/#/cli/login?callback=http://evil.com/steal-token
```
The browser redirects to the attacker's server with the token.

**Impact:** Token theft via malicious links.

**Fix:** Validate callback URL before redirect:
```tsx
const handleSubmit = (e: FormEvent) => {
  e.preventDefault();
  setIsLoading(true);

  const token = btoa(DEMO_API_KEY);
  const params = new URLSearchParams(window.location.hash.split('?')[1] || '');
  const callback = params.get('callback');

  if (callback) {
    try {
      const url = new URL(callback);
      if (url.hostname !== 'localhost' && url.hostname !== '127.0.0.1') {
        alert('Invalid callback URL: must be localhost');
        setIsLoading(false);
        return;
      }
      window.location.href = `${callback}?token=${token}`;
    } catch {
      alert('Invalid callback URL');
      setIsLoading(false);
    }
  } else {
    alert('No callback URL provided');
    setIsLoading(false);
  }
};
```

### 2. Race Condition: Multiple Callbacks Can Resolve Promise

**Location:** `cli/src/commands/login.ts:43-122`

Multiple requests to `/auth/callback` can arrive (browser retries, double-clicks). Each `resolveAuth(apiKey)` succeeds even after promise resolved.

**Fix:** Add guard:
```typescript
let authCompleted = false;

// In handler:
if (authCompleted) {
  res.writeHead(409, { 'Content-Type': 'text/plain' });
  res.end('Authentication already completed');
  return;
}
authCompleted = true;
resolveAuth(apiKey);
```

### 3. Host Validation is No-Op

**Location:** `cli/src/commands/login.ts:52-58`

```typescript
const url = new URL(req.url, `http://localhost:${port}`);
const host = url.hostname;
if (host !== 'localhost' && host !== '127.0.0.1') { ... }
```

`url.hostname` is always `localhost` because the base URL is hardcoded. This validation provides false confidence.

**Fix:** Remove the misleading validation and document the actual security model:
```typescript
// SECURITY NOTE: This callback server accepts connections from any local process.
// This is acceptable because:
// 1. Only localhost can connect (OS network isolation)
// 2. The token comes from our auth page, not from the callback request
// 3. An attacker with local access has bigger problems
```

---

## Architecture Concerns

### 4. Default Auth URL Points to Development Server

**Location:** `cli/src/config.ts:118-127`

```typescript
return 'http://localhost:5173';  // "Default to localhost for development"
```

Production users will get connection refused. Default should be production URL:
```typescript
return 'https://expo-free-agent.pages.dev';
```

### 5. Documentation Says Wrong Default

**Location:** `docs/CLI_AUTHENTICATION.md:81-82`

Docs say `AUTH_BASE_URL` "defaults to production" but code defaults to localhost. Align docs with code.

### 6. `useEffect` Used Directly in Component

**Location:** `packages/landing-page/src/main.tsx:21-26`

Per project guidelines, extract to custom hook:
```typescript
function useHashRoute() {
  const [route, setRoute] = useState(window.location.hash);

  useEffect(() => {
    const handleHashChange = () => setRoute(window.location.hash);
    window.addEventListener("hashchange", handleHashChange);
    return () => window.removeEventListener("hashchange", handleHashChange);
  }, []);

  return route;
}
```

---

## Maintenance Improvements

### 7. Test Coverage Gaps

**Location:** `cli/src/commands/__tests__/login.test.ts`

- `rejects non-localhost callback hosts` test doesn't actually test the server
- No integration tests for HTTP server flow
- No tests for timeout behavior or error handling paths

### 8. Timeout Not Cleared on Error Path

**Location:** `cli/src/commands/login.ts:139-156`

Add `clearTimeout(timeout)` in catch block to prevent double server close.

### 9. Config Path Mismatch

`docs/CLI_AUTHENTICATION.md` says `~/.expo-controller/config.json` but code uses `~/.expo-free-agent/config.json`.

---

## Nitpicks

- Unused import in test file (`import * as config`)
- `catch (error) { throw error }` is redundant
- Missing `.js` extension for ESM compatibility in test imports

---

## Strengths

- Atomic config writes with temp file + rename, correct file permissions (0o600)
- 30-second timeout prevents hung CLI sessions
- Clean separation of concerns
- `--no-browser` flag for headless environments
- Comprehensive documentation
- Demo mode clearly labeled in UI

---

## Summary

The open redirect vulnerability must be fixed before merge. Remove the misleading host validation and document the actual security model.

**Priority fixes:**
1. Add callback URL validation in `CLILoginPage.tsx`
2. Remove/fix misleading host validation in `login.ts`
3. Fix default auth URL to production
4. Add `authCompleted` guard against race condition
5. Extract `useEffect` to custom hook per guidelines
6. Improve test coverage

With security fixes, this is ready to merge.
