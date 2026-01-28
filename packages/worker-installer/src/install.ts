import { execSync, execFileSync } from 'child_process';
import { existsSync, rmSync, cpSync, chmodSync } from 'fs';
import { join } from 'path';

const APPLICATIONS_DIR = '/Applications';
const APP_NAME = 'FreeAgent.app';

export function isAppInstalled(): boolean {
  return existsSync(join(APPLICATIONS_DIR, APP_NAME));
}

export function getInstalledVersion(): string | null {
  const appPath = join(APPLICATIONS_DIR, APP_NAME);
  const plistPath = join(appPath, 'Contents', 'Info.plist');

  if (!existsSync(plistPath)) {
    return null;
  }

  try {
    const output = execSync(
      `/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${plistPath}"`,
      { encoding: 'utf-8' }
    );
    return output.trim();
  } catch {
    return null;
  }
}

export function stopApp(): void {
  try {
    execSync(`pkill -f "${APP_NAME}"`, { stdio: 'ignore' });
    // Wait a moment for graceful shutdown
    execSync('sleep 1');
  } catch {
    // App may not be running, that's fine
  }
}

export function installApp(sourcePath: string, force: boolean = false): void {
  const destPath = join(APPLICATIONS_DIR, APP_NAME);

  if (existsSync(destPath)) {
    if (!force) {
      throw new Error(
        `${APP_NAME} already exists in ${APPLICATIONS_DIR}. Use --force to reinstall.`
      );
    }

    // Stop the app before replacing
    stopApp();

    // Remove old app
    rmSync(destPath, { recursive: true, force: true });
  }

  // CRITICAL: Use ditto instead of cpSync to preserve code signature and xattrs.
  // Node's cpSync may not correctly preserve macOS-specific metadata required
  // for Gatekeeper validation of notarized apps.
  execFileSync('ditto', [sourcePath, destPath], { stdio: 'pipe' });

  // Verify code signature is intact after copy
  try {
    execFileSync('codesign', ['--verify', '--deep', '--strict', destPath], {
      stdio: 'pipe'
    });
  } catch (error) {
    throw new Error(
      `Code signature verification failed after installation. The app bundle may be corrupted.`
    );
  }

  // DO NOT remove quarantine attributes - Gatekeeper needs them to validate notarization.
  // DO NOT run spctl --add - it's for unsigned apps, not notarized ones.
  // DO NOT run lsregister - it's unrelated to Gatekeeper.
  // The app is properly notarized; macOS will handle first-launch validation automatically.
}

export function uninstallApp(): void {
  const appPath = join(APPLICATIONS_DIR, APP_NAME);

  if (!existsSync(appPath)) {
    throw new Error(`${APP_NAME} is not installed`);
  }

  stopApp();
  rmSync(appPath, { recursive: true, force: true });
}

export function validateAppBundle(appPath: string): { valid: boolean; error?: string } {
  // Check if it's a .app bundle
  if (!appPath.endsWith('.app')) {
    return { valid: false, error: 'Not a .app bundle' };
  }

  if (!existsSync(appPath)) {
    return { valid: false, error: 'App bundle does not exist' };
  }

  // Check for Contents directory
  const contentsPath = join(appPath, 'Contents');
  if (!existsSync(contentsPath)) {
    return { valid: false, error: 'Missing Contents directory' };
  }

  // Check for Info.plist
  const plistPath = join(contentsPath, 'Info.plist');
  if (!existsSync(plistPath)) {
    return { valid: false, error: 'Missing Info.plist' };
  }

  // Check for MacOS directory with executable
  const macosPath = join(contentsPath, 'MacOS');
  if (!existsSync(macosPath)) {
    return { valid: false, error: 'Missing MacOS directory' };
  }

  return { valid: true };
}
