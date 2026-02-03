import { execSync, spawnSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import os from 'os';
import readline from 'readline';
import chalk from 'chalk';
import { isTTY } from './types.js';

interface CertificateInfo {
  hash: string;
  name: string;
  displayName: string;
}

interface CertificateCache {
  certificateHash: string;
  certificateName: string;
  projectPath: string;
  cachedAt: string;
}

const CACHE_FILE = '.expo-free-agent-certs.json';

/**
 * Get cached certificate for current project directory
 */
export function getCachedCertificate(projectPath: string): CertificateCache | null {
  const resolvedPath = path.resolve(projectPath);
  const cacheFilePath = path.join(resolvedPath, CACHE_FILE);

  try {
    if (!fs.existsSync(cacheFilePath)) {
      return null;
    }

    const cacheData = JSON.parse(fs.readFileSync(cacheFilePath, 'utf-8'));

    // Validate cache structure
    if (!cacheData.certificateHash || !cacheData.certificateName || !cacheData.projectPath) {
      return null;
    }

    // Verify cached certificate still exists in keychain
    const certs = listIOSCertificates();
    const certStillExists = certs.some(c => c.hash === cacheData.certificateHash);

    if (!certStillExists) {
      // Certificate was removed from keychain, invalidate cache
      fs.unlinkSync(cacheFilePath);
      return null;
    }

    return cacheData;
  } catch {
    return null;
  }
}

/**
 * Save certificate selection to cache
 */
export function saveCertificateCache(
  projectPath: string,
  certificateHash: string,
  certificateName: string
): void {
  const resolvedPath = path.resolve(projectPath);
  const cacheFilePath = path.join(resolvedPath, CACHE_FILE);

  const cache: CertificateCache = {
    certificateHash,
    certificateName,
    projectPath: resolvedPath,
    cachedAt: new Date().toISOString(),
  };

  fs.writeFileSync(cacheFilePath, JSON.stringify(cache, null, 2), 'utf-8');
}

/**
 * Clear certificate cache for project
 */
export function clearCertificateCache(projectPath: string): boolean {
  const resolvedPath = path.resolve(projectPath);
  const cacheFilePath = path.join(resolvedPath, CACHE_FILE);

  try {
    if (fs.existsSync(cacheFilePath)) {
      fs.unlinkSync(cacheFilePath);
      return true;
    }
    return false;
  } catch {
    return false;
  }
}

/**
 * List all iOS signing certificates in keychain
 */
export function listIOSCertificates(): CertificateInfo[] {
  try {
    const output = execSync(
      'security find-identity -v -p codesigning',
      { encoding: 'utf-8' }
    );

    const lines = output.split('\n');
    const certs: CertificateInfo[] = [];

    for (const line of lines) {
      // Match: 1) HASH "Name"
      const match = line.match(/^\s*\d+\)\s+([A-F0-9]+)\s+"([^"]+)"/);
      if (match && (line.includes('iPhone') || line.includes('Apple Development') || line.includes('Apple Distribution'))) {
        const [, hash, name] = match;
        certs.push({
          hash,
          name,
          displayName: line.trim(),
        });
      }
    }

    return certs;
  } catch (error) {
    throw new Error('Failed to list certificates. Ensure you have iOS signing certificates installed in your keychain.');
  }
}

/**
 * Prompt user to select a certificate
 */
export async function promptCertificateSelection(certs: CertificateInfo[]): Promise<CertificateInfo> {
  console.log();
  console.log(chalk.bold('iOS Signing Certificates:'));
  console.log();

  certs.forEach((cert, index) => {
    console.log(chalk.dim(`  ${index + 1})`), cert.displayName);
  });

  console.log();

  if (certs.length === 1) {
    console.log(chalk.green('Using:'), certs[0].displayName);
    return certs[0];
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve, reject) => {
    rl.question(`Select certificate (1-${certs.length}): `, (answer) => {
      rl.close();

      const selection = parseInt(answer, 10);
      if (isNaN(selection) || selection < 1 || selection > certs.length) {
        reject(new Error('Invalid selection'));
        return;
      }

      resolve(certs[selection - 1]);
    });
  });
}

/**
 * Prompt user for keychain password (secure input)
 */
export async function promptKeychainPassword(): Promise<string> {
  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    const stdout = process.stdout;

    // Enable raw mode to hide password
    if (isTTY(stdin)) {
      stdin.setRawMode(true);
    }

    stdout.write('Keychain password: ');

    let password = '';

    const onData = (char: Buffer) => {
      const str = char.toString();

      if (str === '\n' || str === '\r' || str === '\u0004') {
        // Enter or Ctrl+D
        if (isTTY(stdin)) {
          stdin.setRawMode(false);
        }
        stdin.pause();
        stdin.removeListener('data', onData);
        stdout.write('\n');
        resolve(password);
      } else if (str === '\u0003') {
        // Ctrl+C
        if (isTTY(stdin)) {
          stdin.setRawMode(false);
        }
        stdin.pause();
        reject(new Error('Cancelled'));
      } else if (str === '\u007f' || str === '\b') {
        // Backspace
        if (password.length > 0) {
          password = password.slice(0, -1);
        }
      } else {
        password += str;
      }
    };

    stdin.on('data', onData);
    stdin.resume();
  });
}

/**
 * Export certificate to PKCS#12 format and package with provisioning profiles
 */
export async function exportCertificate(
  cert: CertificateInfo,
  keychainPassword: string
): Promise<string> {
  // Create temp directory
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'expo-certs-'));

  try {
    // Generate random password for p12
    const p12Password = execSync('openssl rand -base64 32', { encoding: 'utf-8' }).trim();

    // Unlock keychain
    const unlockResult = spawnSync(
      'security',
      ['unlock-keychain', '-p', keychainPassword, path.join(os.homedir(), 'Library/Keychains/login.keychain-db')],
      { encoding: 'utf-8' }
    );

    if (unlockResult.status !== 0) {
      throw new Error('Failed to unlock keychain - incorrect password');
    }

    // Export certificate
    const exportResult = spawnSync(
      'security',
      [
        'export',
        '-k', path.join(os.homedir(), 'Library/Keychains/login.keychain-db'),
        '-t', 'identities',
        '-f', 'pkcs12',
        '-P', p12Password,
        '-o', path.join(tempDir, 'cert.p12'),
        cert.name,
      ],
      { encoding: 'utf-8' }
    );

    if (exportResult.status !== 0) {
      throw new Error(`Failed to export certificate: ${exportResult.stderr}`);
    }

    // Write password to file
    fs.writeFileSync(path.join(tempDir, 'password.txt'), p12Password, 'utf-8');

    // Find and copy provisioning profiles
    const profilesDir = path.join(os.homedir(), 'Library/MobileDevice/Provisioning Profiles');
    if (fs.existsSync(profilesDir)) {
      const profiles = fs.readdirSync(profilesDir).filter(f => f.endsWith('.mobileprovision'));
      for (const profile of profiles) {
        fs.copyFileSync(
          path.join(profilesDir, profile),
          path.join(tempDir, profile)
        );
      }
    }

    // Create zip archive
    const zipPath = path.join(tempDir, 'certs.zip');
    const zipResult = spawnSync(
      'zip',
      ['-q', '-r', 'certs.zip', 'cert.p12', 'password.txt', '*.mobileprovision'],
      { cwd: tempDir, encoding: 'utf-8' }
    );

    if (zipResult.status !== 0) {
      throw new Error('Failed to create certificate bundle');
    }

    return zipPath;
  } catch (error) {
    // Cleanup on error
    fs.rmSync(tempDir, { recursive: true, force: true });
    throw error;
  }
}

/**
 * Discover and export iOS signing certificate with caching
 */
export async function discoverAndExportCertificate(
  projectPath: string,
  useCache = true
): Promise<{ certsPath: string; tempDir: string }> {
  const resolvedPath = path.resolve(projectPath);

  // Check cache first
  if (useCache) {
    const cached = getCachedCertificate(resolvedPath);
    if (cached) {
      console.log();
      console.log(chalk.green('✓'), 'Using cached certificate:', chalk.dim(cached.certificateName));

      // Find the certificate by hash
      const certs = listIOSCertificates();
      const cert = certs.find(c => c.hash === cached.certificateHash);

      if (!cert) {
        // Certificate no longer exists, clear cache and continue
        clearCertificateCache(resolvedPath);
        console.log(chalk.yellow('⚠'), 'Cached certificate no longer exists in keychain');
      } else {
        // Export with cached certificate
        console.log();
        console.log(chalk.dim('Please enter your keychain password to export the certificate:'));
        const keychainPassword = await promptKeychainPassword();
        console.log();

        const certsPath = await exportCertificate(cert, keychainPassword);
        const tempDir = path.dirname(certsPath);

        return { certsPath, tempDir };
      }
    }
  }

  // No cache or cache invalid - prompt user
  const certs = listIOSCertificates();

  if (certs.length === 0) {
    throw new Error('No iOS signing certificates found in keychain');
  }

  const selectedCert = await promptCertificateSelection(certs);

  // Prompt for keychain password
  console.log();
  console.log(chalk.dim('Please enter your keychain password to export the certificate:'));
  console.log();
  const keychainPassword = await promptKeychainPassword();
  console.log();

  // Export certificate
  const certsPath = await exportCertificate(selectedCert, keychainPassword);
  const tempDir = path.dirname(certsPath);

  // Save to cache
  saveCertificateCache(resolvedPath, selectedCert.hash, selectedCert.name);
  console.log(chalk.green('✓'), 'Certificate cached for this project');

  return { certsPath, tempDir };
}
