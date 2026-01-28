import { describe, it, expect, beforeEach, afterEach } from 'bun:test';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { DatabaseService } from '../db/Database';
import { EventLog } from './EventLog';

describe('EventLog', () => {
  let tempDir: string;
  let db: DatabaseService;
  let eventLog: EventLog;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'eventlog-test-'));
    const dbPath = join(tempDir, 'test.db');
    db = new DatabaseService(dbPath);
    eventLog = new EventLog(db, 'test-controller-id');
  });

  afterEach(() => {
    db.close();
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('should append events with sequential numbering', async () => {
    const event1 = await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    const event2 = await eventLog.append({
      eventType: 'build:assigned',
      entityId: 'build-1',
      entityType: 'build',
      payload: { workerId: 'worker-1' },
    });

    expect(event1.sequence).toBe(1);
    expect(event2.sequence).toBe(2);
  });

  it('should create valid hash chain', async () => {
    const event1 = await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    const event2 = await eventLog.append({
      eventType: 'build:assigned',
      entityId: 'build-1',
      entityType: 'build',
      payload: { workerId: 'worker-1' },
    });

    expect(event1.previousHash).toBeNull();
    expect(event2.previousHash).toBe(event1.eventHash);
  });

  it('should verify valid hash chain', async () => {
    await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    await eventLog.append({
      eventType: 'build:assigned',
      entityId: 'build-1',
      entityType: 'build',
      payload: { workerId: 'worker-1' },
    });

    const result = await eventLog.verify();
    expect(result.valid).toBe(true);
    expect(result.firstBrokenSequence).toBeUndefined();
  });

  it('should detect tampered event hash', async () => {
    await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    // Manually tamper with event hash in database
    db.prepare('UPDATE event_log SET event_hash = ? WHERE sequence = 1')
      .run('tampered-hash');

    const result = await eventLog.verify();
    expect(result.valid).toBe(false);
    expect(result.firstBrokenSequence).toBe(1);
  });

  it('should detect broken hash chain', async () => {
    await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    await eventLog.append({
      eventType: 'build:assigned',
      entityId: 'build-1',
      entityType: 'build',
      payload: { workerId: 'worker-1' },
    });

    // Tamper with previous_hash in second event
    db.prepare('UPDATE event_log SET previous_hash = ? WHERE sequence = 2')
      .run('tampered-previous-hash');

    const result = await eventLog.verify();
    expect(result.valid).toBe(false);
    expect(result.firstBrokenSequence).toBe(2);
  });

  it('should get events since sequence', async () => {
    await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    await eventLog.append({
      eventType: 'build:assigned',
      entityId: 'build-1',
      entityType: 'build',
      payload: { workerId: 'worker-1' },
    });

    await eventLog.append({
      eventType: 'build:completed',
      entityId: 'build-1',
      entityType: 'build',
      payload: {},
    });

    const events = await eventLog.getSince(1, 10);
    expect(events.length).toBe(2);
    expect(events[0].sequence).toBe(2);
    expect(events[1].sequence).toBe(3);
  });

  it('should deduplicate received events', async () => {
    const event = await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    // Try to receive the same event again
    await eventLog.receive(event);

    const count = await eventLog.count();
    expect(count).toBe(1);
  });

  it('should reject events with invalid hash', async () => {
    const event = await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    // Tamper with hash and change ID to avoid deduplication
    const tamperedEvent = { ...event, id: 'different-id', eventHash: 'tampered-hash' };

    await expect(eventLog.receive(tamperedEvent)).rejects.toThrow('invalid hash');
  });

  it('should get events by entity', async () => {
    await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-1',
      entityType: 'build',
      payload: { platform: 'ios' },
    });

    await eventLog.append({
      eventType: 'build:assigned',
      entityId: 'build-1',
      entityType: 'build',
      payload: { workerId: 'worker-1' },
    });

    await eventLog.append({
      eventType: 'build:submitted',
      entityId: 'build-2',
      entityType: 'build',
      payload: { platform: 'android' },
    });

    const build1Events = await eventLog.getByEntity('build', 'build-1');
    expect(build1Events.length).toBe(2);
    expect(build1Events.every(e => e.entityId === 'build-1')).toBe(true);
  });
});
