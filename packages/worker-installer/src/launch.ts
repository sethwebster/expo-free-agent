import { execSync, spawn } from 'child_process';
import { join } from 'path';

const APPLICATIONS_DIR = '/Applications';
const APP_NAME = 'FreeAgent.app';

export function launchApp(): void {
  const appPath = join(APPLICATIONS_DIR, APP_NAME);

  try {
    // Use 'open' command to launch the app
    execSync(`open "${appPath}"`, { stdio: 'ignore' });
  } catch (error) {
    throw new Error(`Failed to launch ${APP_NAME}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

export function addToLoginItems(): boolean {
  const appPath = join(APPLICATIONS_DIR, APP_NAME);

  try {
    // Use osascript to add to Login Items
    const script = `tell application "System Events" to make login item at end with properties {path:"${appPath}", hidden:false}`;

    execSync(`osascript -e '${script}'`, { stdio: 'pipe' });
    return true;
  } catch (error) {
    console.warn('Failed to add to Login Items:', error);
    return false;
  }
}

export function removeFromLoginItems(): boolean {
  try {
    const script = `tell application "System Events" to delete login item "${APP_NAME.replace('.app', '')}"`;

    execSync(`osascript -e '${script}'`, { stdio: 'pipe' });
    return true;
  } catch (error) {
    console.warn('Failed to remove from Login Items:', error);
    return false;
  }
}

export function isInLoginItems(): boolean {
  try {
    const script = `tell application "System Events" to get the name of every login item`;

    const output = execSync(`osascript -e '${script}'`, { encoding: 'utf-8' });
    const items = output.split(', ').map(s => s.trim());

    return items.includes(APP_NAME.replace('.app', ''));
  } catch {
    return false;
  }
}

export function isAppRunning(): boolean {
  try {
    execSync(`pgrep -f "${APP_NAME}"`, { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}
