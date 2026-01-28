import Fastify, { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import fastifyView from '@fastify/view';
import fastifyCors from '@fastify/cors';
import ejs from 'ejs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { DatabaseService } from './db/Database.js';
import { JobQueue } from './services/JobQueue.js';
import { FileStorage } from './services/FileStorage.js';
import { EventLog } from './services/EventLog.js';
import { ControllerRegistry } from './services/ControllerRegistry.js';
import { EventBroadcaster } from './services/EventBroadcaster.js';
import { QueueEventLogger } from './services/QueueEventLogger.js';
import { registerApiRoutes } from './api/index.js';
import { statsRoutes } from './api/stats/index.js';
import { registerControllerRoutes } from './api/controllers/index.js';
import { registerEventRoutes } from './api/events/index.js';
import type { ControllerConfig } from './domain/Config.js';
import { generateDemoData } from './demo/generateDemoData.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export class ControllerServer {
  private app: FastifyInstance;
  private db: DatabaseService;
  private queue: JobQueue;
  private storage: FileStorage;
  private config: ControllerConfig;
  private timeoutChecker?: NodeJS.Timeout;
  private expirationChecker?: NodeJS.Timeout;
  private heartbeatTimer?: NodeJS.Timeout;

  // Distributed mode services
  private eventLog?: EventLog;
  private registry?: ControllerRegistry;
  private broadcaster?: EventBroadcaster;
  private queueEventLogger?: QueueEventLogger;

  constructor(config: ControllerConfig) {
    this.config = config;
    this.app = Fastify({
      logger: false,
      bodyLimit: Math.max(
        config.maxSourceFileSize,
        config.maxCertsFileSize,
        config.maxResultFileSize
      ),
    });
    this.db = new DatabaseService(config.dbPath);
    this.queue = new JobQueue();
    this.storage = new FileStorage(config.storagePath);

    // Initialize distributed mode services if enabled
    if (config.mode === 'distributed') {
      this.eventLog = new EventLog(this.db, config.controllerId);
      this.registry = new ControllerRegistry(this.db, this.eventLog);
      this.broadcaster = new EventBroadcaster(this.db, this.eventLog, this.registry, config.apiKey);
      this.queueEventLogger = new QueueEventLogger(this.queue, this.eventLog, this.broadcaster);
    }

    this.setupMiddleware();
    this.setupRoutes();
    this.setupQueueListeners();
    this.restoreQueueState();
    this.performStartupMaintenance();
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

  /**
   * Perform maintenance tasks on startup
   * - Purge old CPU snapshots (>90 days) to prevent unbounded growth
   */
  private performStartupMaintenance() {
    try {
      const snapshotsBefore = this.db.getCpuSnapshotCount();
      const deleted = this.db.purgeCpuSnapshotsOlderThan(90);
      if (deleted > 0) {
        console.log(`[Maintenance] Purged ${deleted} CPU snapshots older than 90 days (${snapshotsBefore} → ${snapshotsBefore - deleted})`);
      }
    } catch (err) {
      console.error('[Maintenance] Failed to purge old CPU snapshots:', err);
    }
  }

  private setupMiddleware() {
    // CORS for landing page
    this.app.register(fastifyCors, {
      origin: true, // Allow all origins in dev (TODO: restrict in prod)
      credentials: true,
    });

    // Request logging
    this.app.addHook('onRequest', async (request, reply) => {
      console.log(`[${new Date().toISOString()}] ${request.method} ${request.url}`);
    });
  }

  private setupRoutes() {
    // Set up EJS templates
    this.app.register(fastifyView, {
      engine: {
        ejs,
      },
      root: join(__dirname, 'views'),
    });

    // Public stats endpoint (no auth)
    this.app.register(statsRoutes, {
      prefix: '/api/stats',
      db: this.db,
    });

    // Protected API routes
    this.app.register(registerApiRoutes, {
      prefix: '/api',
      db: this.db,
      queue: this.queue,
      storage: this.storage,
      config: this.config,
    });

    // Distributed controller routes (if enabled)
    if (this.config.mode === 'distributed' && this.registry && this.eventLog && this.broadcaster) {
      this.app.register(async (app) => {
        await registerControllerRoutes(app, this.registry!);
      });
      this.app.register(async (app) => {
        await registerEventRoutes(app, this.eventLog!, this.broadcaster!);
      });
    }

    // Web UI
    this.app.get('/', async (request: FastifyRequest<{ Querystring: { demo?: string } }>, reply: FastifyReply) => {
      const isDemo = request.query.demo === 'true';

      if (isDemo) {
        // Demo mode - show beautiful charts with realistic data
        const demoData = generateDemoData();
        return reply.view('index', {
          ...demoData,
          isDemo: true,
        });
      }

      // Real mode - show actual data
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

      return reply.view('index', {
        builds: enrichedBuilds,
        workers,
        stats: {
          totalBuilds: builds.length,
          pendingBuilds: queueStats.pending,
          activeBuilds: queueStats.active,
          totalWorkers: workers.length,
        },
        isDemo: false,
        chartData: null,
      });
    });

    // Health check
    this.app.get('/health', async (request: FastifyRequest, reply: FastifyReply) => {
      return reply.send({
        status: 'ok',
        queue: this.queue.getStats(),
        storage: this.storage.getStats(),
      });
    });

    // 404 handler
    this.app.setNotFoundHandler(async (request, reply) => {
      return reply.status(404).send({ error: 'Not found' });
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
   * Register with parent controller (if configured)
   */
  private async registerWithParent() {
    if (!this.config.parentControllerUrl || !this.registry) {
      return;
    }

    try {
      const response = await fetch(`${this.config.parentControllerUrl}/api/controllers/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': this.config.apiKey,
        },
        body: JSON.stringify({
          id: this.config.controllerId,
          url: `http://localhost:${this.config.port}`,
          name: this.config.controllerName,
          metadata: {
            version: '1.0.0',
            mode: this.config.mode,
          },
          ttl: this.config.registrationTtl,
        }),
      });

      if (!response.ok) {
        throw new Error(`Failed to register with parent: ${response.status}`);
      }

      const data = await response.json() as { expiresAt: number };
      console.log(`✅ Registered with parent controller (expires: ${new Date(data.expiresAt).toISOString()})`);
    } catch (error) {
      console.error('❌ Failed to register with parent controller:', error);
    }
  }

  /**
   * Send heartbeat to parent controller
   */
  private async sendHeartbeatToParent() {
    if (!this.config.parentControllerUrl) {
      return;
    }

    try {
      const response = await fetch(
        `${this.config.parentControllerUrl}/api/controllers/${this.config.controllerId}/heartbeat`,
        {
          method: 'POST',
          headers: {
            'X-API-Key': this.config.apiKey,
          },
        }
      );

      if (!response.ok) {
        console.error(`❌ Heartbeat failed: ${response.status}`);
        // Try to re-register if heartbeat fails
        await this.registerWithParent();
      }
    } catch (error) {
      console.error('❌ Heartbeat error:', error);
    }
  }

  /**
   * Start heartbeat timer (sends heartbeats to parent)
   */
  private startHeartbeatTimer() {
    if (!this.config.parentControllerUrl) {
      return;
    }

    this.heartbeatTimer = setInterval(async () => {
      await this.sendHeartbeatToParent();
    }, this.config.heartbeatInterval);
  }

  /**
   * Start expiration checker (expires stale controllers)
   */
  private startExpirationChecker() {
    if (!this.registry) {
      return;
    }

    this.expirationChecker = setInterval(async () => {
      const expired = await this.registry!.expireStale();
      if (expired.length > 0) {
        console.log(`⏱️  Expired ${expired.length} stale controllers:`, expired);
      }
    }, this.config.expirationCheckInterval);
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

  async start(): Promise<void> {
    await this.app.listen({
      port: this.config.port,
      host: '0.0.0.0',
    });

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('🚀 Expo Free Agent Controller');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`\n📍 Server:   http://localhost:${this.config.port}`);
    console.log(`📊 Web UI:   http://localhost:${this.config.port}`);
    console.log(`🔌 API:      http://localhost:${this.config.port}/api`);
    console.log(`\n💾 Database: ${this.config.dbPath}`);
    console.log(`📦 Storage:  ${this.config.storagePath}`);
    console.log(`🔐 API Key:  ${this.config.apiKey.substring(0, 8)}...`);

    // Distributed mode info
    if (this.config.mode === 'distributed') {
      console.log(`\n🌐 Mode:     Distributed`);
      console.log(`🆔 ID:       ${this.config.controllerId}`);
      console.log(`📛 Name:     ${this.config.controllerName}`);
      if (this.config.parentControllerUrl) {
        console.log(`👆 Parent:   ${this.config.parentControllerUrl}`);
      }
    } else {
      console.log(`\n🌐 Mode:     Standalone`);
    }

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    // Start timeout checker (every 60 seconds)
    this.timeoutChecker = setInterval(() => {
      this.checkStuckBuilds();
    }, 60000);

    // Start distributed mode features
    if (this.config.mode === 'distributed') {
      // Start queue event logger
      if (this.queueEventLogger) {
        this.queueEventLogger.start();
        console.log('Queue event logger started');
      }

      // Register with parent (if configured)
      await this.registerWithParent();

      // Start heartbeat timer
      this.startHeartbeatTimer();

      // Start expiration checker
      this.startExpirationChecker();
    }
  }

  async stop() {
    console.log('\nShutting down...');

    // Stop timeout checker
    if (this.timeoutChecker) {
      clearInterval(this.timeoutChecker);
      console.log('Timeout checker stopped');
    }

    // Stop heartbeat timer
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      console.log('Heartbeat timer stopped');
    }

    // Stop expiration checker
    if (this.expirationChecker) {
      clearInterval(this.expirationChecker);
      console.log('Expiration checker stopped');
    }

    // Close HTTP server gracefully
    await this.app.close();
    console.log('HTTP server closed');

    // Queue state is already persisted in DB via transactions
    // No need to save separately

    // Close database
    this.db.close();
    console.log('Database closed');
  }
}
