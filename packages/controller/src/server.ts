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
        resolve();
      });
    });
  }

  async stop() {
    console.log('\nShutting down...');

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
