import express, { Request, Response } from 'express';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import http from 'http';
import { DatabaseService } from './db/Database.js';
import { JobQueue } from './services/JobQueue.js';
import { FileStorage } from './services/FileStorage.js';
import { createApiRoutes } from './api/routes.js';
import type { ControllerConfig } from './domain/Config.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export class ControllerServer {
  private app: express.Application;
  private db: DatabaseService;
  private queue: JobQueue;
  private storage: FileStorage;
  private config: ControllerConfig;
  private server?: http.Server;
  private timeoutChecker?: NodeJS.Timeout;

  constructor(config: ControllerConfig) {
    this.config = config;
    this.app = express();
    this.db = new DatabaseService(config.dbPath);
    this.queue = new JobQueue();
    this.storage = new FileStorage(config.storagePath);

    this.setupMiddleware();
    this.setupRoutes();
    this.setupQueueListeners();
    this.restoreQueueState();
  }

  /**
   * Restore queue state from database on startup
   * Recovers pending and assigned builds after server restart
   */
  private restoreQueueState() {
    const pendingBuilds = this.db.getPendingBuilds();
    const assignedBuilds = this.db.getAssignedBuilds();
    const workers = new Map(this.db.getAllWorkers().map(w => [w.id, w]));

    this.queue.restoreFromDatabase(pendingBuilds, assignedBuilds, workers);
  }

  private setupMiddleware() {
    this.app.use(express.json());
    this.app.use(express.urlencoded({ extended: true }));

    // Request logging
    this.app.use((req, res, next) => {
      console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
      next();
    });
  }

  private setupRoutes() {
    // Set up EJS templates
    this.app.set('view engine', 'ejs');
    this.app.set('views', join(__dirname, 'views'));

    // API routes
    this.app.use('/api', createApiRoutes(this.db, this.queue, this.storage, this.config));

    // Web UI
    this.app.get('/', (req: Request, res: Response) => {
      const builds = this.db.getAllBuilds();
      const workers = this.db.getAllWorkers();
      const queueStats = this.queue.getStats();

      // Enrich builds with worker names
      const enrichedBuilds = builds.map(build => {
        const worker = build.worker_id ? this.db.getWorker(build.worker_id) : null;
        return {
          ...build,
          worker_name: worker?.name || null,
        };
      });

      res.render('index', {
        builds: enrichedBuilds,
        workers,
        stats: {
          totalBuilds: builds.length,
          pendingBuilds: queueStats.pending,
          activeBuilds: queueStats.active,
          totalWorkers: workers.length,
        },
      });
    });

    // Health check
    this.app.get('/health', (req: Request, res: Response) => {
      res.json({
        status: 'ok',
        queue: this.queue.getStats(),
        storage: this.storage.getStats(),
      });
    });

    // 404
    this.app.use((req: Request, res: Response) => {
      res.status(404).json({ error: 'Not found' });
    });
  }

  private setupQueueListeners() {
    this.queue.on('job:assigned', (build, worker) => {
      console.log(`Build ${build.id} assigned to worker ${worker.name}`);
    });

    this.queue.on('job:completed', (build, worker) => {
      console.log(`Build ${build.id} completed by worker ${worker.name}`);
    });

    this.queue.on('job:failed', (build, worker) => {
      console.log(`Build ${build.id} failed on worker ${worker.name}`);
    });
  }

  /**
   * Check for stuck builds (no heartbeat for 2 minutes)
   * Runs every 60 seconds
   */
  private checkStuckBuilds() {
    const HEARTBEAT_TIMEOUT = 120000; // 2 minutes
    const now = Date.now();

    const activeBuilds = this.db.getAllBuilds().filter(b =>
      b.status === 'assigned' || b.status === 'building'
    );

    for (const build of activeBuilds) {
      // Check if heartbeat is missing or stale
      const lastHeartbeat = (build as any).last_heartbeat_at;
      const timeSinceStart = build.started_at ? now - build.started_at : 0;

      // Only check builds that have been running for at least 30 seconds
      // and haven't sent a heartbeat in 2 minutes
      if (timeSinceStart > 30000) {
        const timeSinceHeartbeat = lastHeartbeat ? now - lastHeartbeat : timeSinceStart;

        if (timeSinceHeartbeat > HEARTBEAT_TIMEOUT) {
          console.warn(`Build ${build.id} stuck - no heartbeat for ${Math.round(timeSinceHeartbeat / 1000)}s`);

          // Mark as failed
          this.db.updateBuildStatus(build.id, 'failed', {
            error_message: `Build timeout - no heartbeat from worker for ${Math.round(timeSinceHeartbeat / 1000)}s`,
            completed_at: now,
          });

          // Mark worker as idle
          if (build.worker_id) {
            this.db.updateWorkerStatus(build.worker_id, 'idle', now);
          }

          // Remove from queue
          this.queue.fail(build.id, false);

          // Log
          this.db.addBuildLog({
            build_id: build.id,
            timestamp: now,
            level: 'error',
            message: `Build timeout - worker stopped responding`,
          });
        }
      }
    }
  }

  start(): Promise<void> {
    return new Promise((resolve) => {
      this.server = this.app.listen(this.config.port, () => {
        console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log('🚀 Expo Free Agent Controller');
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log(`\n📍 Server:   http://localhost:${this.config.port}`);
        console.log(`📊 Web UI:   http://localhost:${this.config.port}`);
        console.log(`🔌 API:      http://localhost:${this.config.port}/api`);
        console.log(`\n💾 Database: ${this.config.dbPath}`);
        console.log(`📦 Storage:  ${this.config.storagePath}`);
        console.log(`🔐 API Key:  ${this.config.apiKey.substring(0, 8)}...`);
        console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

        // Start timeout checker (every 60 seconds)
        this.timeoutChecker = setInterval(() => {
          this.checkStuckBuilds();
        }, 60000);

        resolve();
      });
    });
  }

  async stop() {
    console.log('\nShutting down...');

    // Stop timeout checker
    if (this.timeoutChecker) {
      clearInterval(this.timeoutChecker);
      console.log('Timeout checker stopped');
    }

    // Close HTTP server gracefully
    if (this.server) {
      await new Promise<void>((resolve) => {
        this.server!.close(() => {
          console.log('HTTP server closed');
          resolve();
        });
      });
    }

    // Queue state is already persisted in DB via transactions
    // No need to save separately

    // Close database
    this.db.close();
    console.log('Database closed');
  }
}
