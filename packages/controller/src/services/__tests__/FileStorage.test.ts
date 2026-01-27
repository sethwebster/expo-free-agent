import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import { mkdirSync, rmSync, existsSync, writeFileSync } from 'fs';
import { join } from 'path';
import { FileStorage } from '../FileStorage';

describe('FileStorage', () => {
  const testStoragePath = join(process.cwd(), '.test-storage');
  let storage: FileStorage;

  beforeEach(() => {
    // Clean up and create test directory
    if (existsSync(testStoragePath)) {
      rmSync(testStoragePath, { recursive: true, force: true });
    }
    mkdirSync(testStoragePath, { recursive: true });
    storage = new FileStorage(testStoragePath);
  });

  afterEach(() => {
    // Clean up
    if (existsSync(testStoragePath)) {
      rmSync(testStoragePath, { recursive: true, force: true });
    }
  });

  describe('Path Traversal Protection', () => {
    test('should reject absolute path outside storage directory', () => {
      expect(() => {
        storage.createReadStream('/etc/passwd');
      }).toThrow('Path traversal attempt blocked');
    });

    test('should reject relative path traversal with ../', () => {
      expect(() => {
        storage.createReadStream(join(testStoragePath, '../../../etc/passwd'));
      }).toThrow('Path traversal attempt blocked');
    });

    test('should reject path traversal through symbolic links', () => {
      // Note: This test validates normalized paths, not symlink following
      // Real symlink protection would need additional checks
      expect(() => {
        storage.createReadStream(join(testStoragePath, '..', '..', 'sensitive.txt'));
      }).toThrow('Path traversal attempt blocked');
    });

    test('should allow valid path inside storage directory', () => {
      const testFile = join(testStoragePath, 'builds', 'test.zip');
      mkdirSync(join(testStoragePath, 'builds'), { recursive: true });
      writeFileSync(testFile, 'test content');

      expect(() => {
        storage.createReadStream(testFile);
      }).not.toThrow();
    });

    test('should reject non-existent file even if path is valid', () => {
      const testFile = join(testStoragePath, 'builds', 'nonexistent.zip');

      expect(() => {
        storage.createReadStream(testFile);
      }).toThrow('File not found');
    });

    test('should allow nested paths inside storage directory', () => {
      const nestedPath = join(testStoragePath, 'builds', 'deep', 'nested', 'file.zip');
      mkdirSync(join(testStoragePath, 'builds', 'deep', 'nested'), { recursive: true });
      writeFileSync(nestedPath, 'test content');

      expect(() => {
        storage.createReadStream(nestedPath);
      }).not.toThrow();
    });
  });
});
