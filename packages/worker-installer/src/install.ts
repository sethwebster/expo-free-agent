import { execSync } from 'child_process';
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

  // Copy to /Applications
  cpSync(sourcePath, destPath, { recursive: true });

  // Remove quarantine attribute (prevents "damaged app" error)
  try {
    execSync(`xattr -cr "${destPath}"`, { stdio: 'ignore' });
  } catch (error) {
    console.warn('Warning: Could not remove quarantine attribute:', error);
  }

  // Ensure executable permissions
  try {
    const executablePath = join(destPath, 'Contents', 'MacOS', 'FreeAgent');
    if (existsSync(executablePath)) {
      chmodSync(executablePath, 0o755);
    }
  } catch (error) {
    console.warn('Warning: Could not set executable permissions:', error);
  }
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
