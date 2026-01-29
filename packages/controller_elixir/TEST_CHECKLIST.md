# Test Checklist - Race Condition Fixes

## Prerequisites

Ensure CONTROLLER_API_KEY is set:
```bash
export CONTROLLER_API_KEY="your-32-char-key-here"
```

Or in `.env`:
```
CONTROLLER_API_KEY=your-32-char-key-here
```

## Quick Test

Run the new concurrency tests:
```bash
cd packages/controller_elixir
mix test test/expo_controller_web/controllers/worker_controller_test.exs
```

## Full Test Suite

Run all tests:
```bash
mix test
```

## Stress Test (100 iterations)

Verify no race conditions over 100 runs:
```bash
for i in {1..100}; do
  echo "Run $i"
  mix test test/expo_controller_web/controllers/worker_controller_test.exs:23 || exit 1
done
```

## Individual Test Cases

### 1. Concurrent assignment test:
```bash
mix test test/expo_controller_web/controllers/worker_controller_test.exs:23
```

### 2. High contention test:
```bash
mix test test/expo_controller_web/controllers/worker_controller_test.exs:93
```

### 3. Timeout test:
```bash
mix test test/expo_controller_web/controllers/worker_controller_test.exs:141
```

## Verify API Key Validation

Test that app fails to start without API key:
```bash
unset CONTROLLER_API_KEY
mix phx.server
# Expected: RuntimeError: CONTROLLER_API_KEY must be set and at least 32 characters
```

## Expected Results

All tests should:
- [x] Pass consistently
- [x] Show no race condition warnings
- [x] Complete within reasonable time (<5s per test)
- [x] Leave DB in consistent state

## If Tests Fail

1. Check database is clean:
   ```bash
   mix ecto.reset
   ```

2. Verify dependencies:
   ```bash
   mix deps.get
   ```

3. Check test output for specific error
4. Verify API key is set correctly

## Coverage

Tests cover:
- ✓ Concurrent build assignment (no double assignment)
- ✓ High contention scenarios (10 workers, 1 build)
- ✓ Transaction timeouts
- ✓ Worker registration
- ✓ Build result upload
- ✓ Build failure reporting
- ✓ Heartbeat recording

## Performance Benchmarks

Expected timing:
- Concurrent assignment test: ~200-500ms
- High contention test: ~100-300ms
- Timeout test: <6s (timeout + buffer)
- Full suite: <10s

If tests take significantly longer, investigate:
- Database connection issues
- Lock contention
- Transaction timeout configuration
