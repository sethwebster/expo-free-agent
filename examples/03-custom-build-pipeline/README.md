# Example 3: Configure Custom Build Pipeline

Advanced example showing how to customize the build process with pre/post scripts, environment variables, and custom build commands.

## Use Cases

- Run tests before building
- Generate build metadata
- Custom code signing workflows
- Multi-environment configurations
- Automated changelog generation

## Project Structure

```
my-expo-app/
├── .expo-build/
│   ├── pre-build.sh          # Runs before build
│   ├── post-build.sh         # Runs after build
│   └── build-config.json     # Custom configuration
├── scripts/
│   ├── generate-version.sh   # Version automation
│   └── notify-team.sh        # Slack/email notifications
├── app.json                  # Expo configuration
└── package.json
```

## Step 1: Create Build Scripts Directory

```bash
mkdir -p .expo-build scripts
```

## Step 2: Pre-Build Script

Create `.expo-build/pre-build.sh`:

```bash
#!/bin/bash
# Pre-build: Run before compilation starts
set -e

echo "🔍 Running pre-build checks..."

# 1. Run tests
echo "Running tests..."
npm test -- --passWithNoTests

# 2. Lint code
echo "Linting code..."
npm run lint

# 3. Type check
echo "Type checking..."
npx tsc --noEmit

# 4. Generate build number
echo "Generating build number..."
BUILD_NUMBER=$(git rev-list --count HEAD)
echo "$BUILD_NUMBER" > .expo-build/build-number.txt

# 5. Update version in app.json
echo "Updating version..."
node scripts/update-version.js

# 6. Generate changelog
echo "Generating changelog..."
npx conventional-changelog -p angular -i CHANGELOG.md -s

echo "✅ Pre-build checks passed!"
```

Make executable:
```bash
chmod +x .expo-build/pre-build.sh
```

## Step 3: Post-Build Script

Create `.expo-build/post-build.sh`:

```bash
#!/bin/bash
# Post-build: Run after successful build
set -e

echo "📦 Running post-build tasks..."

BUILD_ID=$1
PLATFORM=$2
ARTIFACT_PATH=$3

# 1. Upload to S3 (optional)
if [ -n "$AWS_S3_BUCKET" ]; then
    echo "Uploading to S3..."
    aws s3 cp "$ARTIFACT_PATH" \
        "s3://$AWS_S3_BUCKET/builds/$BUILD_ID/"
fi

# 2. Notify team on Slack
if [ -n "$SLACK_WEBHOOK_URL" ]; then
    echo "Notifying team..."
    curl -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d '{
            "text": "✅ Build completed!",
            "attachments": [{
                "color": "good",
                "fields": [
                    {"title": "Build ID", "value": "'"$BUILD_ID"'", "short": true},
                    {"title": "Platform", "value": "'"$PLATFORM"'", "short": true}
                ]
            }]
        }'
fi

# 3. Archive build artifacts
echo "Archiving artifacts..."
mkdir -p builds/archive/$BUILD_ID
cp "$ARTIFACT_PATH" builds/archive/$BUILD_ID/
cp .expo-build/build-number.txt builds/archive/$BUILD_ID/
cp CHANGELOG.md builds/archive/$BUILD_ID/

# 4. Update build registry
echo "Updating registry..."
cat >> builds/registry.json <<EOF
{
    "buildId": "$BUILD_ID",
    "platform": "$PLATFORM",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "commit": "$(git rev-parse HEAD)",
    "branch": "$(git branch --show-current)"
}
EOF

echo "✅ Post-build tasks complete!"
```

Make executable:
```bash
chmod +x .expo-build/post-build.sh
```

## Step 4: Version Management Script

Create `scripts/update-version.js`:

```javascript
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

// Read app.json
const appJsonPath = path.join(__dirname, '..', 'app.json');
const appJson = JSON.parse(fs.readFileSync(appJsonPath, 'utf8'));

// Read build number from pre-build script
const buildNumberPath = path.join(__dirname, '..', '.expo-build', 'build-number.txt');
const buildNumber = fs.readFileSync(buildNumberPath, 'utf8').trim();

// Update version
const version = appJson.expo.version; // e.g., "1.2.3"
appJson.expo.ios.buildNumber = buildNumber;
appJson.expo.android.versionCode = parseInt(buildNumber, 10);

// Write back
fs.writeFileSync(appJsonPath, JSON.stringify(appJson, null, 2));

console.log(`✅ Updated to version ${version} (build ${buildNumber})`);
```

Make executable:
```bash
chmod +x scripts/update-version.js
```

## Step 5: Build Configuration

Create `.expo-build/build-config.json`:

```json
{
  "environments": {
    "development": {
      "apiUrl": "https://dev-api.example.com",
      "enableDebug": true,
      "analyticsEnabled": false
    },
    "staging": {
      "apiUrl": "https://staging-api.example.com",
      "enableDebug": true,
      "analyticsEnabled": true
    },
    "production": {
      "apiUrl": "https://api.example.com",
      "enableDebug": false,
      "analyticsEnabled": true
    }
  },
  "notifications": {
    "slack": {
      "enabled": true,
      "channel": "#builds"
    },
    "email": {
      "enabled": false,
      "recipients": ["team@example.com"]
    }
  },
  "artifacts": {
    "upload": {
      "s3": false,
      "gcs": false
    },
    "retention": {
      "days": 90
    }
  }
}
```

## Step 6: Environment-Specific Builds

### Set Environment Variables

Create `.env.development`:
```bash
API_URL=https://dev-api.example.com
ENABLE_DEBUG=true
ANALYTICS_ENABLED=false
SENTRY_DSN=https://your-dev-sentry-dsn
```

Create `.env.production`:
```bash
API_URL=https://api.example.com
ENABLE_DEBUG=false
ANALYTICS_ENABLED=true
SENTRY_DSN=https://your-prod-sentry-dsn
```

### Configure App

Update `app.json` to use environment variables:

```json
{
  "expo": {
    "name": "My App",
    "extra": {
      "apiUrl": "${API_URL}",
      "enableDebug": "${ENABLE_DEBUG}",
      "analyticsEnabled": "${ANALYTICS_ENABLED}",
      "sentryDsn": "${SENTRY_DSN}"
    }
  }
}
```

### Submit Environment-Specific Build

```bash
# Development build
expo-build submit \
  --platform ios \
  --env development \
  --config .expo-build/build-config.json

# Production build
expo-build submit \
  --platform ios \
  --env production \
  --config .expo-build/build-config.json
```

## Step 7: Custom Build Commands

Create `.expo-build/custom-commands.sh`:

```bash
#!/bin/bash
# Custom build commands
set -e

# Install custom dependencies
npm install -g appcenter-cli

# Run custom build steps
case "$EXPO_BUILD_PLATFORM" in
  ios)
    echo "Running iOS-specific commands..."
    # Custom iOS build steps
    npx pod-install
    ;;
  android)
    echo "Running Android-specific commands..."
    # Custom Android build steps
    ./gradlew clean
    ;;
esac

# Generate assets
npm run generate-assets

# Optimize images
npm run optimize-images

# Bundle JavaScript
npx metro bundle \
  --platform "$EXPO_BUILD_PLATFORM" \
  --dev false \
  --entry-file index.js \
  --bundle-output ./dist/main.jsbundle
```

## Step 8: Automated Testing in Pipeline

Create `.expo-build/run-tests.sh`:

```bash
#!/bin/bash
set -e

echo "🧪 Running test suite..."

# Unit tests
npm run test:unit

# Integration tests
npm run test:integration

# E2E tests (headless)
npm run test:e2e:headless

# Visual regression tests
npm run test:visual

# Generate coverage report
npm run test:coverage

# Upload coverage to Codecov
if [ -n "$CODECOV_TOKEN" ]; then
    npx codecov
fi

echo "✅ All tests passed!"
```

## Step 9: Submit with Custom Pipeline

Complete build script with all custom steps:

```bash
#!/bin/bash
# build-with-pipeline.sh
set -e

ENV=${1:-production}
PLATFORM=${2:-ios}

echo "🚀 Starting custom build pipeline..."
echo "Environment: $ENV"
echo "Platform: $PLATFORM"

# Load environment variables
if [ -f ".env.$ENV" ]; then
    export $(cat .env.$ENV | xargs)
fi

# Pre-build
./.expo-build/pre-build.sh

# Run tests
./.expo-build/run-tests.sh

# Submit build
BUILD_ID=$(expo-build submit \
  --platform $PLATFORM \
  --env $ENV \
  --format json | jq -r '.buildId')

echo "Build ID: $BUILD_ID"

# Wait for completion
expo-build wait $BUILD_ID

# Download artifacts
expo-build download $BUILD_ID

# Post-build
./.expo-build/post-build.sh \
  "$BUILD_ID" \
  "$PLATFORM" \
  "./expo-builds/$BUILD_ID/"

echo "✅ Pipeline complete!"
```

Usage:
```bash
chmod +x build-with-pipeline.sh

# Development iOS build
./build-with-pipeline.sh development ios

# Production Android build
./build-with-pipeline.sh production android
```

## Step 10: CI/CD Integration

### GitHub Actions

Create `.github/workflows/build.yml`:

```yaml
name: Build Expo App

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Bun
        uses: oven-sh/setup-bun@v1

      - name: Install dependencies
        run: bun install

      - name: Run tests
        run: bun test

      - name: Submit build
        env:
          EXPO_CONTROLLER_URL: ${{ secrets.EXPO_CONTROLLER_URL }}
          EXPO_CONTROLLER_API_KEY: ${{ secrets.EXPO_CONTROLLER_API_KEY }}
        run: |
          ./build-with-pipeline.sh production ios

      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: ios-build
          path: expo-builds/
```

### GitLab CI

Create `.gitlab-ci.yml`:

```yaml
stages:
  - test
  - build
  - deploy

variables:
  EXPO_CONTROLLER_URL: "https://builds.example.com"

test:
  stage: test
  script:
    - bun install
    - bun test

build:
  stage: build
  script:
    - ./build-with-pipeline.sh production ios
  artifacts:
    paths:
      - expo-builds/
    expire_in: 1 week
  only:
    - main
```

## Troubleshooting

### Pre-Build Script Fails

**Error:** `Tests failed, build aborted`

**Solution:**
```bash
# Skip tests in development
expo-build submit --skip-pre-build

# Or fix tests before building
npm test
```

### Environment Variables Not Loading

**Error:** `API_URL is undefined`

**Solution:**
```bash
# Check .env file exists
ls -la .env.*

# Manually export variables
export $(cat .env.production | xargs)

# Verify
echo $API_URL
```

### Custom Commands Timeout

**Error:** `Build timeout after 30 minutes`

**Solution:**
```bash
# Increase timeout
expo-build submit --timeout 60

# Or optimize custom commands:
# - Cache dependencies
# - Parallelize tasks
# - Skip unnecessary steps in CI
```

## Best Practices

1. **Keep scripts fast** - Pre-build should complete in <2 minutes
2. **Make idempotent** - Scripts should be safe to run multiple times
3. **Handle failures gracefully** - Always `set -e` and clean up
4. **Version control everything** - `.expo-build/` in git
5. **Document dependencies** - List required tools in README
6. **Test locally first** - Don't debug in CI
7. **Use environment variables** - Never hardcode secrets

## Advanced Topics

- **Monorepo builds:** Build multiple apps from one repo
- **Feature flags:** Dynamic configuration per build
- **A/B testing:** Build variants for experiments
- **Code push:** OTA updates vs full builds
- **Build caching:** Speed up repeat builds

## Resources

- [Expo Build Lifecycle](../../docs/architecture/build-lifecycle.md)
- [Environment Configuration](../../docs/operations/environment-config.md)
- [CI/CD Best Practices](../../docs/operations/cicd.md)

---

**Time to complete:** ~2 hours (initial setup)
**Skill level:** Advanced
**Maintenance:** ~15 minutes/month
