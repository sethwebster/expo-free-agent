import { EventEmitter } from 'events';
import type { Build, Worker } from '../db/Database.js';

export interface JobAssignment {
  build: Build;
  worker: Worker;
}

/**
 * In-memory job queue for build assignment
 * Simple FIFO queue with round-robin worker assignment
 *
 * Persistence: Queue state is restored from DB on startup and persisted on shutdown
 */
export class JobQueue extends EventEmitter {
  private pendingBuilds: Build[] = [];
  private activeAssignments = new Map<string, JobAssignment>(); // buildId -> assignment

  constructor() {
    super();
  }

  /**
   * Restore queue state from database
   * Call on server startup to recover pending/assigned builds
   */
  restoreFromDatabase(pendingBuilds: Build[], assignedBuilds: Build[], workers: Map<string, any>) {
    // Restore pending builds
    this.pendingBuilds = [...pendingBuilds];

    // Restore active assignments
    for (const build of assignedBuilds) {
      if (build.worker_id) {
        const worker = workers.get(build.worker_id);
        if (worker) {
          this.activeAssignments.set(build.id, { build, worker });
        } else {
          // Worker no longer exists, reset build to pending
          this.pendingBuilds.unshift(build);
        }
      }
    }

    console.log(`Queue restored: ${this.pendingBuilds.length} pending, ${this.activeAssignments.size} active`);
  }

  /**
   * Get current queue state for persistence
   */
  getState() {
    return {
      pending: [...this.pendingBuilds],
      active: Array.from(this.activeAssignments.values()),
    };
  }

  /**
   * Add build to queue
   */
  enqueue(build: Build) {
    this.pendingBuilds.push(build);
    this.emit('job:added', build);
  }

  /**
   * Assign next pending build to worker
   * Returns assignment or undefined if no pending builds
   */
  assignToWorker(worker: Worker): Build | undefined {
    const build = this.pendingBuilds.shift();
    if (!build) return undefined;

    this.activeAssignments.set(build.id, { build, worker });
    this.emit('job:assigned', build, worker);

    return build;
  }

  /**
   * Mark build as completed
   */
  complete(buildId: string) {
    const assignment = this.activeAssignments.get(buildId);
    if (assignment) {
      this.activeAssignments.delete(buildId);
      this.emit('job:completed', assignment.build, assignment.worker);
    }
  }

  /**
   * Mark build as failed and reassign to queue
   */
  fail(buildId: string, requeue = true) {
    const assignment = this.activeAssignments.get(buildId);
    if (assignment) {
      this.activeAssignments.delete(buildId);

      if (requeue) {
        // Put back at front of queue for retry
        this.pendingBuilds.unshift(assignment.build);
      }

      this.emit('job:failed', assignment.build, assignment.worker);
    }
  }

  /**
   * Get next pending build without removing from queue
   */
  peek(): Build | undefined {
    return this.pendingBuilds[0];
  }

  /**
   * Get all pending builds
   */
  getPending(): Build[] {
    return [...this.pendingBuilds];
  }

  /**
   * Get active assignments
   */
  getActive(): JobAssignment[] {
    return Array.from(this.activeAssignments.values());
  }

  /**
   * Get assignment for specific build
   */
  getAssignment(buildId: string): JobAssignment | undefined {
    return this.activeAssignments.get(buildId);
  }

  /**
   * Get build assigned to specific worker
   */
  getWorkerBuild(workerId: string): Build | undefined {
    for (const assignment of this.activeAssignments.values()) {
      if (assignment.worker.id === workerId) {
        return assignment.build;
      }
    }
    return undefined;
  }

  /**
   * Check if worker has active assignment
   */
  isWorkerBusy(workerId: string): boolean {
    return this.getWorkerBuild(workerId) !== undefined;
  }

  /**
   * Get queue stats
   */
  getStats() {
    return {
      pending: this.pendingBuilds.length,
      active: this.activeAssignments.size,
      total: this.pendingBuilds.length + this.activeAssignments.size,
    };
  }

  /**
   * Clear all pending builds (for testing/emergency)
   */
  clear() {
    this.pendingBuilds = [];
    this.activeAssignments.clear();
  }
}
