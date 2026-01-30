import { execSync } from 'child_process';
import { platform, arch, totalmem } from 'os';
import { existsSync, statfsSync } from 'fs';
import type { PreflightResult, WorkerCapabilities } from './types.js';

export function checkMacOS(): PreflightResult {
  const currentPlatform = platform();

  if (currentPlatform !== 'darwin') {
    return {
      check: 'macOS',
      status: 'error',
      message: `Unsupported platform: ${currentPlatform}`,
      details: 'Free Agent Worker requires macOS 14.0 (Sonoma) or newer'
    };
  }

  try {
    const version = execSync('sw_vers -productVersion', { encoding: 'utf-8' }).trim();
    const [major, minor] = version.split('.').map(Number);

    if (major < 14) {
      return {
        check: 'macOS',
        status: 'error',
        message: `macOS ${version} is too old`,
        details: 'Requires macOS 14.0 (Sonoma) or newer for Virtualization.framework'
      };
    }

    return {
      check: 'macOS',
      status: 'ok',
      message: `macOS ${version}`
    };
  } catch (error) {
    return {
      check: 'macOS',
      status: 'error',
      message: 'Unable to detect macOS version',
      details: error instanceof Error ? error.message : String(error)
    };
  }
}

export function checkArchitecture(): PreflightResult {
  const currentArch = arch();

  if (currentArch !== 'arm64') {
    return {
      check: 'Architecture',
      status: 'error',
      message: `Unsupported architecture: ${currentArch}`,
      details: 'Free Agent Worker requires Apple Silicon (arm64)'
    };
  }

  return {
    check: 'Architecture',
    status: 'ok',
    message: 'Apple Silicon (arm64)'
  };
}

export function checkXcode(): PreflightResult {
  try {
    const path = execSync('xcode-select -p', { encoding: 'utf-8' }).trim();

    try {
      const version = execSync('xcodebuild -version', { encoding: 'utf-8' });
      const match = version.match(/Xcode ([\d.]+)/);
      const xcodeVersion = match ? match[1] : 'unknown';

      return {
        check: 'Xcode',
        status: 'ok',
        message: `Version ${xcodeVersion}`,
        details: path
      };
    } catch {
      return {
        check: 'Xcode',
        status: 'ok',
        message: 'Command Line Tools installed',
        details: path
      };
    }
  } catch {
    return {
      check: 'Xcode',
      status: 'warn',
      message: 'Not found',
      details: 'Install Xcode from App Store for iOS builds. Run: sudo xcode-select -s /Applications/Xcode.app'
    };
  }
}

export function checkTart(): PreflightResult {
  try {
    const version = execSync('/opt/homebrew/bin/tart --version 2>/dev/null || tart --version', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'ignore']
    }).trim();

    return {
      check: 'Tart',
      status: 'ok',
      message: version,
      details: '/opt/homebrew/bin/tart'
    };
  } catch {
    return {
      check: 'Tart',
      status: 'warn',
      message: 'Not found',
      details: 'Install with: brew install cirruslabs/cli/tart'
    };
  }
}

export function checkDiskSpace(): PreflightResult {
  try {
    const homeDir = process.env.HOME || '/Users';
    const stats = statfsSync(homeDir);
    const freeGB = (stats.bavail * stats.bsize) / (1024 ** 3);

    if (freeGB < 10) {
      return {
        check: 'Disk Space',
        status: 'error',
        message: `Only ${freeGB.toFixed(1)}GB free`,
        details: 'At least 10GB free space required'
      };
    }

    if (freeGB < 50) {
      return {
        check: 'Disk Space',
        status: 'warn',
        message: `${freeGB.toFixed(1)}GB free`,
        details: 'At least 50GB recommended for VM images'
      };
    }

    return {
      check: 'Disk Space',
      status: 'ok',
      message: `${freeGB.toFixed(1)}GB free`
    };
  } catch (error) {
    return {
      check: 'Disk Space',
      status: 'warn',
      message: 'Unable to check',
      details: error instanceof Error ? error.message : String(error)
    };
  }
}

export function checkMemory(): PreflightResult {
  const totalGB = totalmem() / (1024 ** 3);

  if (totalGB < 8) {
    return {
      check: 'Memory',
      status: 'warn',
      message: `${totalGB.toFixed(1)}GB total`,
      details: 'At least 16GB recommended for running VMs'
    };
  }

  return {
    check: 'Memory',
    status: 'ok',
    message: `${totalGB.toFixed(1)}GB total`
  };
}

export function runPreflightChecks(verbose: boolean = false): PreflightResult[] {
  const checks = [
    checkMacOS(),
    checkArchitecture(),
    checkXcode(),
    checkTart(),
    checkDiskSpace(),
    checkMemory()
  ];

  return checks;
}

export function getWorkerCapabilities(): WorkerCapabilities {
  const cpuCores = parseInt(execSync('sysctl -n hw.ncpu', { encoding: 'utf-8' }).trim());
  const memoryGB = totalmem() / (1024 ** 3);

  let diskGB = 0;
  try {
    const homeDir = process.env.HOME || '/Users';
    const stats = statfsSync(homeDir);
    diskGB = (stats.bavail * stats.bsize) / (1024 ** 3);
  } catch (error) {
    // Failed to query disk space; will report as 0
    console.warn('Failed to query available disk space:', error);
  }

  let xcodeVersion: string | undefined;
  try {
    const version = execSync('xcodebuild -version', { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'ignore'] });
    const match = version.match(/Xcode ([\d.]+)/);
    xcodeVersion = match ? match[1] : undefined;
  } catch (error) {
    // xcodebuild not found or failed; will report as undefined
    console.warn('Failed to detect Xcode version:', error);
  }

  let tartVersion: string | undefined;
  try {
    tartVersion = execSync('/opt/homebrew/bin/tart --version 2>/dev/null || tart --version', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'ignore']
    }).trim();
  } catch (error) {
    // tart not found or failed; will report as undefined
    console.warn('Failed to detect Tart version:', error);
  }

  return {
    cpuCores,
    memoryGB: Math.round(memoryGB),
    diskGB: Math.round(diskGB),
    xcodeVersion,
    tartVersion,
    platform: platform(),
    architecture: arch()
  };
}
