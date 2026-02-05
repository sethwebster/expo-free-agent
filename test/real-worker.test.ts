import { test, expect } from 'bun:test';
import { mkdtempSync, rmSync, statSync, existsSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { copyBuildScripts } from './real-worker';

test('copyBuildScripts writes bootstrap and diagnostics scripts', () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'fa-real-worker-'));
  try {
    copyBuildScripts(tempDir);

    const bootstrapPath = join(tempDir, 'bootstrap.sh');
    const diagnosticsPath = join(tempDir, 'diagnostics.sh');

    expect(existsSync(bootstrapPath)).toBe(true);
    expect(existsSync(diagnosticsPath)).toBe(true);

    const bootstrapMode = statSync(bootstrapPath).mode & 0o111;
    const diagnosticsMode = statSync(diagnosticsPath).mode & 0o111;
    expect(bootstrapMode).toBeGreaterThan(0);
    expect(diagnosticsMode).toBeGreaterThan(0);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});
