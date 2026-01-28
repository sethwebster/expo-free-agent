import { EventLog } from './EventLog';
import { JobQueue } from './JobQueue';
import { EventBroadcaster } from './EventBroadcaster';
import type { Build, Worker } from '../db/Database';

/**
 * Bridges JobQueue events to EventLog and broadcasts to network
 */
export class QueueEventLogger {
  constructor(
    private queue: JobQueue,
    private eventLog: EventLog,
    private broadcaster: EventBroadcaster
  ) {}

  /**
   * Start listening to queue events and logging to event log
   */
  start() {
    this.queue.on('job:added', async (build: Build) => {
      const event = await this.eventLog.append({
        eventType: 'build:submitted',
        entityId: build.id,
        entityType: 'build',
        payload: {
          platform: build.platform,
          status: 'pending',
          submittedAt: build.submitted_at,
        },
      });
      await this.broadcaster.broadcast(event);
    });

    this.queue.on('job:assigned', async (build: Build, worker: Worker) => {
      const event = await this.eventLog.append({
        eventType: 'build:assigned',
        entityId: build.id,
        entityType: 'build',
        payload: {
          workerId: worker.id,
          workerName: worker.name,
          status: 'assigned',
        },
      });
      await this.broadcaster.broadcast(event);
    });

    this.queue.on('job:completed', async (build: Build, worker: Worker) => {
      const event = await this.eventLog.append({
        eventType: 'build:completed',
        entityId: build.id,
        entityType: 'build',
        payload: {
          workerId: worker.id,
          workerName: worker.name,
          status: 'completed',
          completedAt: build.completed_at,
        },
      });
      await this.broadcaster.broadcast(event);
    });

    this.queue.on('job:failed', async (build: Build, worker: Worker) => {
      const event = await this.eventLog.append({
        eventType: 'build:failed',
        entityId: build.id,
        entityType: 'build',
        payload: {
          workerId: worker.id,
          workerName: worker.name,
          status: 'failed',
          errorMessage: build.error_message,
          completedAt: build.completed_at,
        },
      });
      await this.broadcaster.broadcast(event);
    });
  }
}
