import { execSync, spawnSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import os from 'os';
import readline from 'readline';
import crypto from 'crypto';
import chalk from 'chalk';
import archiver from 'archiver';
import { isTTY } from './types.js';

export interface CertificateInfo {
  hash: string;
  name: string;
  displayName: string;
}

export interface ProvisioningProfileInfo {
  uuid: string;
  name: string;
  teamId: string;
  appId: string;
  bundleId: string;
  isWildcard: boolean;
  isAppStore: boolean;
  developerCertificateFingerprints: string[];
  path: string;
}

interface CertificateCache {
  certificateHash: string;
  certificateName: string;
  projectPath: string;
  cachedAt: string;
}

const CACHE_FILE = '.expo-free-agent-certs.json';
const P12_PASSWORD_ENV = 'EXPO_CERT_P12_PASSWORD';
const PROFILES_DIR = path.join(os.homedir(), 'Library/MobileDevice/Provisioning Profiles');

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

export function selectAppStoreProfile(
  profiles: ProvisioningProfileInfo[],
  bundleId: string
): ProvisioningProfileInfo {
  const exactMatches = profiles.filter(profile =>
    profile.isAppStore &&
    !profile.isWildcard &&
    profile.bundleId === bundleId
  );

  if (exactMatches.length === 0) {
    throw new Error(`No App Store provisioning profile found for ${bundleId}`);
  }

  if (exactMatches.length > 1) {
    throw new Error(`Multiple App Store provisioning profiles found for ${bundleId}`);
  }

  return exactMatches[0];
}

export function selectProfileForBundle(
  profiles: ProvisioningProfileInfo[],
  bundleId: string
): { profile: ProvisioningProfileInfo; method: 'app-store' | 'development' } {
  const appStore = profiles.filter(profile =>
    profile.isAppStore &&
    !profile.isWildcard &&
    profile.bundleId === bundleId
  );

  if (appStore.length > 1) {
    throw new Error(`Multiple App Store provisioning profiles found for ${bundleId}`);
  }

  if (appStore.length === 1) {
    return { profile: appStore[0], method: 'app-store' };
  }

  const development = profiles.filter(profile =>
    !profile.isAppStore &&
    !profile.isWildcard &&
    profile.bundleId === bundleId
  );

  if (development.length === 0) {
    throw new Error(`No provisioning profile found for ${bundleId}`);
  }

  if (development.length > 1) {
    throw new Error(`Multiple development provisioning profiles found for ${bundleId}`);
  }

  return { profile: development[0], method: 'development' };
}

export function selectMatchingCertificate(
  certs: CertificateInfo[],
  profile: ProvisioningProfileInfo
): CertificateInfo {
  const match = certs.find(cert =>
    profile.developerCertificateFingerprints.includes(cert.hash)
  );

  if (!match) {
    throw new Error('No matching signing certificate found for selected provisioning profile');
  }

  return match;
}

export function listProvisioningProfiles(): ProvisioningProfileInfo[] {
  if (!fs.existsSync(PROFILES_DIR)) {
    return [];
  }

  const files = fs.readdirSync(PROFILES_DIR).filter(file => file.endsWith('.mobileprovision'));
  const profiles: ProvisioningProfileInfo[] = [];
  let parsedCount = 0;

  for (const file of files) {
    const profilePath = path.join(PROFILES_DIR, file);
    const profile = readProvisioningProfile(profilePath);
    if (profile) {
      profiles.push(profile);
      parsedCount += 1;
    }
  }

  if (files.length > 0 && parsedCount == 0) {
    throw new Error('Failed to parse provisioning profiles. Try reinstalling profiles via Xcode or Apple Developer portal.');
  }

  return profiles;
}

function readProvisioningProfile(profilePath: string): ProvisioningProfileInfo | null {
  const directJson = tryPlutilJson(profilePath);
  if (directJson) {
    return parseProvisioningProfile(directJson, profilePath);
  }

  const xml = decodeProvisioningProfile(profilePath);
  if (!xml) {
    return null;
  }

  const json = plistXmlToJson(xml);
  return parseProvisioningProfile(json, profilePath);
}

function plistXmlToJson(xml: string): Record<string, unknown> {
  const plutil = spawnSync(
    'plutil',
    ['-convert', 'json', '-o', '-', '-'],
    { input: xml, encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 }
  );

  if (plutil.status !== 0 || !plutil.stdout) {
    throw new Error('Failed to parse provisioning profile');
  }

  return JSON.parse(plutil.stdout) as Record<string, unknown>;
}

function tryPlutilJson(profilePath: string): Record<string, unknown> | null {
  const plutil = spawnSync(
    'plutil',
    ['-convert', 'json', '-o', '-', profilePath],
    { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 }
  );

  if (plutil.status !== 0 || !plutil.stdout) {
    return null;
  }

  try {
    return JSON.parse(plutil.stdout) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function decodeProvisioningProfile(profilePath: string): string | null {
  const cmsResult = spawnSync('security', ['cms', '-D', '-i', profilePath], { encoding: 'utf-8' });
  if (cmsResult.status === 0 && cmsResult.stdout) {
    return cmsResult.stdout;
  }

  const opensslCommands = [
    ['cms', '-inform', 'der', '-verify', '-noverify', '-in', profilePath],
    ['smime', '-inform', 'der', '-verify', '-noverify', '-in', profilePath],
    ['smime', '-inform', 'smime', '-verify', '-noverify', '-in', profilePath],
  ];

  for (const args of opensslCommands) {
    const result = spawnSync('openssl', args, { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 });
    if (result.status === 0 && result.stdout) {
      return result.stdout;
    }
  }

  return null;
}

function parseProvisioningProfile(
  data: Record<string, unknown>,
  profilePath: string
): ProvisioningProfileInfo | null {
  const uuid = getString(data, 'UUID');
  const name = getString(data, 'Name');
  const entitlements = getObject(data, 'Entitlements');
  const appId = getString(entitlements, 'application-identifier');
  const teamIds = getStringArray(data, 'TeamIdentifier');
  const teamId = teamIds[0] ?? appId.split('.')[0];

  if (!uuid || !name || !appId || !teamId) {
    return null;
  }

  const bundleId = appId.replace(`${teamId}.`, '');
  const isWildcard = bundleId.endsWith('*');
  const provisionedDevices = data['ProvisionedDevices'];
  const provisionsAllDevices = Boolean(data['ProvisionsAllDevices']);
  const getTaskAllow = Boolean((entitlements as Record<string, unknown>)['get-task-allow']);
  const isAppStore = !provisionedDevices && !provisionsAllDevices && !getTaskAllow;
  const developerCertificates = getDataArray(data, 'DeveloperCertificates');
  const developerCertificateFingerprints = developerCertificates.map(cert =>
    crypto.createHash('sha1').update(cert).digest('hex').toUpperCase()
  );

  return {
    uuid,
    name,
    teamId,
    appId,
    bundleId,
    isWildcard,
    isAppStore,
    developerCertificateFingerprints,
    path: profilePath,
  };
}

function getString(data: Record<string, unknown>, key: string): string {
  const value = data[key];
  return typeof value === 'string' ? value : '';
}

function getObject(data: Record<string, unknown>, key: string): Record<string, unknown> {
  const value = data[key];
  return value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
}

function getStringArray(data: Record<string, unknown>, key: string): string[] {
  const value = data[key];
  return Array.isArray(value) ? value.filter(item => typeof item === 'string') as string[] : [];
}

function getDataArray(data: Record<string, unknown>, key: string): Buffer[] {
  const value = data[key];
  if (!Array.isArray(value)) return [];
  return value
    .filter(item => typeof item === 'string')
    .map(item => Buffer.from(item as string, 'base64'));
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

async function promptP12Password(): Promise<string> {
  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    const stdout = process.stdout;

    if (isTTY(stdin)) {
      stdin.setRawMode(true);
    }

    stdout.write('P12 password: ');

    let password = '';

    const onData = (char: Buffer) => {
      const str = char.toString();

      if (str === '\n' || str === '\r' || str === '\u0004') {
        if (isTTY(stdin)) {
          stdin.setRawMode(false);
        }
        stdin.pause();
        stdin.removeListener('data', onData);
        stdout.write('\n');
        resolve(password);
      } else if (str === '\u0003') {
        if (isTTY(stdin)) {
          stdin.setRawMode(false);
        }
        stdin.pause();
        reject(new Error('Cancelled'));
      } else if (str === '\u007f' || str === '\b') {
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

async function createCertsZip(
  zipPath: string,
  p12Path: string,
  p12Password: string,
  profilePath?: string
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const output = fs.createWriteStream(zipPath);
    const archive = archiver('zip', { zlib: { level: 9 } });

    output.on('close', () => resolve());
    archive.on('error', (err) => reject(err));

    archive.pipe(output);
    archive.file(p12Path, { name: 'cert.p12' });
    archive.append(p12Password, { name: 'password.txt' });
    if (profilePath) {
      archive.file(profilePath, { name: path.basename(profilePath) });
    }
    archive.finalize();
  });
}

export async function ensureCertificateBundle(
  certPath: string
): Promise<{ certsPath: string; tempDir?: string }> {
  const resolvedPath = path.resolve(certPath);
  const ext = path.extname(resolvedPath).toLowerCase();

  if (ext === '.zip') {
    return { certsPath: resolvedPath };
  }

  if (ext !== '.p12') {
    throw new Error('Certificate must be a .zip bundle or a .p12 file');
  }

  const envPassword = process.env[P12_PASSWORD_ENV];
  let p12Password = envPassword;

  if (!p12Password) {
    if (!isTTY(process.stdin)) {
      throw new Error(`P12 password required. Set ${P12_PASSWORD_ENV} or run in interactive mode.`);
    }

    p12Password = await promptP12Password();
  }

  if (!p12Password) {
    throw new Error('P12 password required to package certificate');
  }

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'expo-certs-p12-'));
  const zipPath = path.join(tempDir, 'certs.zip');

  await createCertsZip(zipPath, resolvedPath, p12Password);

  return { certsPath: zipPath, tempDir };
}

export async function exportCertificateWithProfile(
  cert: CertificateInfo,
  keychainPassword: string,
  profilePath: string
): Promise<string> {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'expo-certs-'));

  try {
    const p12Password = execSync('openssl rand -base64 32', { encoding: 'utf-8' }).trim();

    const unlockResult = spawnSync(
      'security',
      ['unlock-keychain', '-p', keychainPassword, path.join(os.homedir(), 'Library/Keychains/login.keychain-db')],
      { encoding: 'utf-8' }
    );

    if (unlockResult.status !== 0) {
      throw new Error('Failed to unlock keychain - incorrect password');
    }

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

    fs.writeFileSync(path.join(tempDir, 'password.txt'), p12Password, 'utf-8');

    const profileCopyPath = path.join(tempDir, path.basename(profilePath));
    fs.copyFileSync(profilePath, profileCopyPath);

    const zipPath = path.join(tempDir, 'certs.zip');
    await createCertsZip(zipPath, path.join(tempDir, 'cert.p12'), p12Password, profileCopyPath);

    return zipPath;
  } catch (error) {
    fs.rmSync(tempDir, { recursive: true, force: true });
    throw error;
  }
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

export async function discoverAndExportCertificateForBundle(
  projectPath: string,
  bundleId: string
): Promise<{ certsPath: string; tempDir: string }> {
  const resolvedPath = path.resolve(projectPath);

  try {
    const certs = listIOSCertificates();
    if (certs.length === 0) {
      throw new Error('No iOS signing certificates found in keychain');
    }

    const profiles = listProvisioningProfiles();
    const selection = selectProfileForBundle(profiles, bundleId);
    if (selection.method === 'development') {
      console.log(chalk.yellow('⚠'), 'Using development provisioning profile for demo build');
    }
    const profile = selection.profile;
    const certificate = selectMatchingCertificate(certs, profile);

    console.log();
    console.log(chalk.dim('Please enter your keychain password to export the certificate:'));
    console.log();
    const keychainPassword = await promptKeychainPassword();
    console.log();

    const certsPath = await exportCertificateWithProfile(certificate, keychainPassword, profile.path);
    const tempDir = path.dirname(certsPath);

    saveCertificateCache(resolvedPath, certificate.hash, certificate.name);
    console.log(chalk.green('✓'), 'Certificate cached for this project');

    return { certsPath, tempDir };
  } catch (error) {
    console.log(chalk.yellow('⚠'), 'Strict profile selection failed, falling back to legacy export.');
    console.log(chalk.dim('Reason:'), error instanceof Error ? error.message : String(error));
    return discoverAndExportCertificate(resolvedPath, true);
  }
}
