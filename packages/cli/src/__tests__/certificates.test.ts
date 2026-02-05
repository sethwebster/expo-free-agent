import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { spawnSync } from 'child_process';
import {
  ensureCertificateBundle,
  selectAppStoreProfile,
  selectProfileForBundle,
  selectMatchingCertificate,
  type ProvisioningProfileInfo,
  type CertificateInfo,
} from '../certificates';

describe('certificate bundling', () => {
  let testDir: string;

  beforeEach(() => {
    testDir = mkdtempSync(join(tmpdir(), 'expo-certs-test-'));
    process.env.EXPO_CERT_P12_PASSWORD = 'test-pass';
  });

  afterEach(() => {
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
    delete process.env.EXPO_CERT_P12_PASSWORD;
  });

  test('wraps .p12 into certs.zip with password', async () => {
    const p12Path = join(testDir, 'cert.p12');
    writeFileSync(p12Path, 'mock-p12');

    const result = await ensureCertificateBundle(p12Path);

    expect(result.certsPath.endsWith('certs.zip')).toBe(true);
    expect(existsSync(result.certsPath)).toBe(true);
    expect(result.tempDir).toBeDefined();

    const password = spawnSync('unzip', ['-p', result.certsPath, 'password.txt'], { encoding: 'utf-8' });
    expect(password.status).toBe(0);
    expect(password.stdout.trim()).toBe('test-pass');

    const p12 = spawnSync('unzip', ['-p', result.certsPath, 'cert.p12'], { encoding: 'utf-8' });
    expect(p12.status).toBe(0);
    expect(p12.stdout).toBe('mock-p12');
  });

  test('accepts existing .zip bundle unchanged', async () => {
    const zipPath = join(testDir, 'certs.zip');
    writeFileSync(zipPath, 'not-a-real-zip');

    const result = await ensureCertificateBundle(zipPath);

    expect(result.certsPath).toBe(zipPath);
    expect(result.tempDir).toBeUndefined();
  });
});

describe('certificate selection', () => {
  test('selects exact app-store profile by bundle id', () => {
    const profiles: ProvisioningProfileInfo[] = [
      {
        uuid: 'A',
        name: 'App Store Profile',
        teamId: 'TEAM1',
        appId: 'TEAM1.com.example.app',
        bundleId: 'com.example.app',
        isWildcard: false,
        isAppStore: true,
        developerCertificateFingerprints: ['ABC'],
        path: '/tmp/profile.mobileprovision',
      },
    ];

    const selected = selectAppStoreProfile(profiles, 'com.example.app');
    expect(selected.uuid).toBe('A');
  });

  test('rejects multiple matching app-store profiles', () => {
    const profiles: ProvisioningProfileInfo[] = [
      {
        uuid: 'A',
        name: 'App Store Profile A',
        teamId: 'TEAM1',
        appId: 'TEAM1.com.example.app',
        bundleId: 'com.example.app',
        isWildcard: false,
        isAppStore: true,
        developerCertificateFingerprints: ['ABC'],
        path: '/tmp/profile-a.mobileprovision',
      },
      {
        uuid: 'B',
        name: 'App Store Profile B',
        teamId: 'TEAM1',
        appId: 'TEAM1.com.example.app',
        bundleId: 'com.example.app',
        isWildcard: false,
        isAppStore: true,
        developerCertificateFingerprints: ['DEF'],
        path: '/tmp/profile-b.mobileprovision',
      },
    ];

    expect(() => selectAppStoreProfile(profiles, 'com.example.app')).toThrow(
      /Multiple App Store provisioning profiles found/
    );
  });

  test('matches certificate by fingerprint', () => {
    const certs: CertificateInfo[] = [
      { hash: 'ABC', name: 'Apple Distribution: Example', displayName: 'ABC "Apple Distribution: Example"' },
      { hash: 'DEF', name: 'Apple Distribution: Other', displayName: 'DEF "Apple Distribution: Other"' },
    ];

    const profile: ProvisioningProfileInfo = {
      uuid: 'A',
      name: 'App Store Profile',
      teamId: 'TEAM1',
      appId: 'TEAM1.com.example.app',
      bundleId: 'com.example.app',
      isWildcard: false,
      isAppStore: true,
      developerCertificateFingerprints: ['DEF'],
      path: '/tmp/profile.mobileprovision',
    };

    const selected = selectMatchingCertificate(certs, profile);
    expect(selected.hash).toBe('DEF');
  });

  test('falls back to development profile when app-store missing', () => {
    const profiles: ProvisioningProfileInfo[] = [
      {
        uuid: 'D',
        name: 'Dev Profile',
        teamId: 'TEAM1',
        appId: 'TEAM1.com.example.app',
        bundleId: 'com.example.app',
        isWildcard: false,
        isAppStore: false,
        developerCertificateFingerprints: ['ABC'],
        path: '/tmp/profile-dev.mobileprovision',
      },
    ];

    const selected = selectProfileForBundle(profiles, 'com.example.app');
    expect(selected.method).toBe('development');
    expect(selected.profile.uuid).toBe('D');
  });
});
