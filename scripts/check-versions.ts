#!/usr/bin/env bun
import { readFileSync } from 'fs';
import { join } from 'path';

interface PackageJson {
  version: string;
}

interface VersionLocation {
  path: string;
  version: string;
  type: 'package.json' | 'constant';
}

const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const RESET = '\x1b[0m';

function readPackageVersion(path: string): string {
  try {
    const content = readFileSync(path, 'utf-8');
    const pkg: PackageJson = JSON.parse(content);
    return pkg.version;
  } catch (error) {
    throw new Error(`Failed to read ${path}: ${error}`);
  }
}

function extractVersionFromFile(path: string, pattern: RegExp): string {
  try {
    const content = readFileSync(path, 'utf-8');
    const match = content.match(pattern);
    if (!match || !match[1]) {
      throw new Error(`Version pattern not found in ${path}`);
    }
    return match[1];
  } catch (error) {
    throw new Error(`Failed to extract version from ${path}: ${error}`);
  }
}

function checkVersionSync(): void {
  const rootDir = join(__dirname, '..');

  const locations: VersionLocation[] = [
    {
      path: 'package.json',
      version: readPackageVersion(join(rootDir, 'package.json')),
      type: 'package.json'
    },
    {
      path: 'packages/cli/package.json',
      version: readPackageVersion(join(rootDir, 'packages/cli/package.json')),
      type: 'package.json'
    },
    {
      path: 'packages/landing-page/package.json',
      version: readPackageVersion(join(rootDir, 'packages/landing-page/package.json')),
      type: 'package.json'
    },
    {
      path: 'packages/worker-installer/package.json',
      version: readPackageVersion(join(rootDir, 'packages/worker-installer/package.json')),
      type: 'package.json'
    },
    {
      path: 'packages/cli/src/index.ts',
      version: extractVersionFromFile(
        join(rootDir, 'packages/cli/src/index.ts'),
        /\.version\(['"]([^'"]+)['"]\)/
      ),
      type: 'constant'
    },
    {
      path: 'packages/worker-installer/src/download.ts',
      version: extractVersionFromFile(
        join(rootDir, 'packages/worker-installer/src/download.ts'),
        /const VERSION = ['"]([^'"]+)['"]/
      ),
      type: 'constant'
    },
    {
      path: 'free-agent/Info.plist',
      version: extractVersionFromFile(
        join(rootDir, 'free-agent/Info.plist'),
        /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/
      ),
      type: 'constant'
    }
  ];

  const expectedVersion = locations[0].version;
  const mismatches: VersionLocation[] = [];

  console.log(`${YELLOW}Checking version synchronization...${RESET}\n`);
  console.log(`Expected version: ${GREEN}${expectedVersion}${RESET}\n`);

  for (const location of locations) {
    const match = location.version === expectedVersion;
    const icon = match ? '✓' : '✗';
    const color = match ? GREEN : RED;

    console.log(`${color}${icon}${RESET} ${location.path}: ${location.version}`);

    if (!match) {
      mismatches.push(location);
    }
  }

  if (mismatches.length > 0) {
    console.log(`\n${RED}❌ VERSION SYNC FAILED${RESET}\n`);
    console.log(`${mismatches.length} location(s) have mismatched versions:\n`);

    for (const mismatch of mismatches) {
      console.log(`  ${RED}•${RESET} ${mismatch.path}`);
      console.log(`    Expected: ${GREEN}${expectedVersion}${RESET}`);
      console.log(`    Found:    ${RED}${mismatch.version}${RESET}\n`);
    }

    console.log(`${YELLOW}To fix:${RESET}`);
    console.log(`  1. Update all package.json files to version ${GREEN}${expectedVersion}${RESET}`);
    console.log(`  2. Update version constants in .ts files`);
    console.log(`  3. Run: bun run test:versions\n`);

    process.exit(1);
  }

  console.log(`\n${GREEN}✓ All versions synchronized at ${expectedVersion}${RESET}\n`);
}

// Run the check
checkVersionSync();
