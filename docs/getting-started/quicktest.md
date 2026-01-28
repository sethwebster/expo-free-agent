# Quick Test Guide

Fast reference for running tests.

## Run All Tests
```bash
bun run test:all
```

## Run Individual Suites

### Controller Tests
```bash
# All controller tests
bun run test:controller

# Or from package
cd packages/controller
bun test

# Specific test file
bun test src/__tests__/integration.test.ts
bun test src/__tests__/e2e.test.ts
```

### CLI Tests
```bash
# All CLI tests
bun run test:cli

# Or from package
cd cli
bun test
```

### E2E Script
```bash
# Full end-to-end test
./test-e2e.sh

# View logs after
cat .test-e2e-integration/controller.log
cat .test-e2e-integration/worker.log
```

## Manual Testing

### 1. Start Controller
```bash
bun controller
# Open http://localhost:3000
```

### 2. Start Mock Worker
```bash
bun test/mock-worker.ts
```

### 3. Submit Test Build
```bash
# Create test project
mkdir test-project
cat > test-project/app.json <<EOF
{"expo": {"name": "Test", "slug": "test"}}
EOF

# Zip it
cd test-project && zip -r ../test.zip . && cd ..

# Submit via API
curl -X POST http://localhost:3000/api/builds/submit \
  -H "X-API-Key: dev-insecure-key-change-in-production" \
  -F "source=@test.zip" \
  -F "platform=ios"
```

### 4. Watch Build Progress
Open http://localhost:3000 and watch the build go from pending → building → completed.

### 5. Download Result
```bash
curl -H "X-API-Key: dev-insecure-key-change-in-production" \
  "http://localhost:3000/api/builds/<BUILD_ID>/download" \
  -o result.ipa
```

## Quick Commands

```bash
# Run just auth tests
bun test --test-name-pattern "Authentication"

# Watch mode
bun test --watch

# Verbose output
bun test --verbose

# Clean test artifacts
rm -rf .test-*

# Kill processes on port 3000
lsof -ti:3000 | xargs kill -9
```

## Mock Worker Options

```bash
# Basic
bun test/mock-worker.ts

# Fail 20% of builds
bun test/mock-worker.ts --failure-rate 0.2

# Faster builds
bun test/mock-worker.ts --build-delay 1000

# Android platform
bun test/mock-worker.ts --platform android

# Custom URL
bun test/mock-worker.ts --url http://localhost:8080

# Help
bun test/mock-worker.ts --help
```

## Expected Times

- Controller integration: ~75ms
- Controller E2E: ~3s
- CLI integration: ~500ms
- E2E script: ~60s
- Full suite: ~2min

## Debugging

### Tests Hang
```bash
# Check for processes
lsof -i:3000
lsof -i:3001
lsof -i:3002

# Kill them
kill -9 <PID>
```

### Tests Fail
```bash
# Check test database
ls -la .test-*

# Clean up
rm -rf .test-*

# Re-run with verbose
bun test --verbose
```

### View Test Output
```bash
# Controller logs
cat .test-e2e-integration/controller.log

# Worker logs
cat .test-e2e-integration/worker.log

# Download result
ls -lh .test-e2e-integration/result.ipa
```

## CI/CD

### GitHub Actions
```yaml
steps:
  - uses: oven-sh/setup-bun@v1
  - run: bun install
  - run: bun run test:all
```

### GitLab CI
```yaml
test:
  script:
    - bun install
    - bun run test:all
```

## Troubleshooting

**Port in use:**
```bash
lsof -ti:3000 | xargs kill -9
```

**Database locked:**
```bash
rm -rf .test-*
```

**Tests fail in CI:**
- Check port availability
- Increase timeouts
- Verify dependencies installed

## Test Structure

```
packages/controller/src/__tests__/
├── integration.test.ts    # Basic tests (4 cases)
└── e2e.test.ts           # Comprehensive E2E (30 cases)

cli/src/__tests__/
└── integration.test.ts    # CLI tests (20+ cases)

test/
├── mock-worker.ts         # Mock Free Agent
├── fixtures/             # Test data
└── test-e2e.sh           # Bash E2E script
```

## Success Indicators

All tests passing:
```
✓ packages/controller/src/__tests__/integration.test.ts
✓ packages/controller/src/__tests__/e2e.test.ts
✓ cli/src/__tests__/integration.test.ts
✓ ./test-e2e.sh
```

## See Also

- [TESTING.md](./TESTING.md) - Comprehensive testing guide
- [TEST_SUMMARY.md](./TEST_SUMMARY.md) - What was created
- [test/fixtures/README.md](./test/fixtures/README.md) - Test helpers
