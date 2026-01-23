# Smoketest Guide

Quick verification that Expo Free Agent is working.

## Option 1: Quick Smoketest (2 minutes)

Fast verification without full E2E workflow.

```bash
# Install dependencies
bun install

# Run controller unit tests
cd packages/controller
bun test

# Run CLI unit tests
cd ../../cli
bun test

# Verify builds succeed
cd ..
bun run build
```

**Expected:** All tests pass, builds succeed with no errors.

## Option 2: Full E2E Smoketest (5 minutes)

Tests complete build submission → worker assignment → completion flow.

```bash
# From project root
./test-e2e.sh
```

**What it does:**
1. Starts controller server
2. Creates test Expo project
3. Submits build via API
4. Starts mock worker
5. Waits for build completion
6. Downloads result
7. Verifies logs
8. Tests concurrent builds
9. Cleans up

**Expected output:**
```
[SUCCESS] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[SUCCESS]   All E2E Tests Passed! ✓
[SUCCESS] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Option 3: Manual Smoketest (10 minutes)

Test each component individually.

### 1. Controller

```bash
# Terminal 1: Start controller
export CONTROLLER_API_KEY="smoketest-key-1234567890123456"
cd packages/controller
bun controller

# Terminal 2: Test health
curl http://localhost:3000/health

# Expected: {"status":"ok",...}

# Test auth
curl -H "X-API-Key: smoketest-key-1234567890123456" \
     http://localhost:3000/api/builds

# Expected: {"builds":[]}
```

### 2. CLI

```bash
# Configure CLI
cd cli
bun run build
./dist/cli.js config --set-url http://localhost:3000

# Create test project
mkdir test-app
cd test-app
cat > app.json <<EOF
{
  "expo": {
    "name": "Smoketest",
    "slug": "smoketest",
    "version": "1.0.0",
    "platforms": ["ios"]
  }
}
EOF

# Submit (will fail without certs, but tests upload)
export CONTROLLER_API_KEY="smoketest-key-1234567890123456"
../dist/cli.js submit . --platform ios

# Expected: Upload succeeds, build queued
```

### 3. Mock Worker

```bash
# Terminal 3: Start mock worker
cd test
bun mock-worker.ts \
  --url http://localhost:3000 \
  --api-key "smoketest-key-1234567890123456" \
  --name "Smoketest Worker" \
  --platform ios

# Expected: Worker registers, polls for jobs
```

### 4. Free Agent (Optional - requires VM setup)

```bash
cd free-agent
swift build -c release

# Configure settings
.build/release/FreeAgent

# Open Settings window, set controller URL
# Start worker
```

## Troubleshooting

### Tests fail

```bash
# Check Node/Bun version
bun --version  # Should be 1.x

# Clean and reinstall
rm -rf node_modules
bun install

# Check for port conflicts
lsof -i :3000  # Controller port
```

### E2E test hangs

```bash
# Check logs in .test-e2e-integration/
cat .test-e2e-integration/controller.log
cat .test-e2e-integration/worker.log

# Kill stuck processes
killall -9 bun node
```

### Build fails

```bash
# Controller
cd packages/controller
rm -rf dist node_modules
bun install
bun run build

# CLI
cd cli
rm -rf dist node_modules
bun install
bun run build
```

### Permission errors

```bash
# Make scripts executable
chmod +x test-e2e.sh test-api.sh

# Check file permissions
ls -la packages/controller/src/cli.ts
```

## Success Criteria

✅ All unit tests pass
✅ All builds succeed (no TypeScript errors)
✅ E2E test completes successfully
✅ Controller starts and responds to health checks
✅ CLI can submit builds
✅ Mock worker can register and poll

## Next Steps

After smoketest passes:
1. Set up VM for real iOS builds (`/vm-setup/`)
2. Test with actual Expo project
3. Configure production settings
4. Review security documentation (`SECURITY.md`)

## Quick Reference

```bash
# Run everything
bun run test:all && ./test-e2e.sh

# Controller only
cd packages/controller && bun test

# CLI only
cd cli && bun test

# E2E only
./test-e2e.sh

# Clean everything
rm -rf node_modules packages/*/node_modules cli/node_modules
rm -rf packages/*/dist cli/dist
rm -rf .test-e2e-integration
```
