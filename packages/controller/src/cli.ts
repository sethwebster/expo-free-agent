#!/usr/bin/env bun

import { join } from 'path';
import { existsSync, mkdirSync } from 'fs';
import { ControllerServer } from './server.js';
import { createConfig } from './domain/Config.js';

interface CliArgs {
  port?: number;
  dbPath?: string;
  storagePath?: string;
  apiKey?: string;
  mode?: 'standalone' | 'distributed';
  controllerId?: string;
  controllerName?: string;
  parentControllerUrl?: string;
}

function parseArgs(): CliArgs {
  const args: CliArgs = {};

  for (let i = 2; i < process.argv.length; i++) {
    const arg = process.argv[i];

    if (arg === '--port' || arg === '-p') {
      args.port = parseInt(process.argv[++i], 10);
    } else if (arg === '--db') {
      args.dbPath = process.argv[++i];
    } else if (arg === '--storage') {
      args.storagePath = process.argv[++i];
    } else if (arg === '--api-key') {
      args.apiKey = process.argv[++i];
    } else if (arg === '--mode') {
      const mode = process.argv[++i];
      if (mode !== 'standalone' && mode !== 'distributed') {
        console.error('Error: --mode must be "standalone" or "distributed"');
        process.exit(1);
      }
      args.mode = mode;
    } else if (arg === '--controller-id') {
      args.controllerId = process.argv[++i];
    } else if (arg === '--controller-name') {
      args.controllerName = process.argv[++i];
    } else if (arg === '--parent-url') {
      args.parentControllerUrl = process.argv[++i];
    } else if (arg === '--help' || arg === '-h') {
      console.log(`
Expo Free Agent Controller

Usage:
  expo-controller start [options]

Options:
  --port, -p <port>        Port to listen on (default: 3000)
  --db <path>              Database file path (default: ./data/controller.db)
  --storage <path>         Storage directory path (default: ./storage)
  --api-key <key>          API key for authentication (default: env CONTROLLER_API_KEY)

Distributed Mode Options:
  --mode <mode>            Controller mode: "standalone" or "distributed" (default: standalone)
  --controller-id <id>     Unique controller ID (default: auto-generated UUID)
  --controller-name <name> Human-readable controller name (default: hostname)
  --parent-url <url>       Parent controller URL to register with (e.g., http://localhost:3000)

  --help, -h               Show this help message

Examples:
  # Standalone mode (default)
  expo-controller start
  expo-controller start --port 8080

  # Distributed mode - parent controller
  expo-controller start --mode distributed --controller-name "main-controller"

  # Distributed mode - child controller registering with parent
  expo-controller start --mode distributed \\
    --port 3001 \\
    --controller-name "worker-controller-1" \\
    --parent-url http://localhost:3000

Environment Variables:
  CONTROLLER_API_KEY       API key for authentication (overridden by --api-key)
  CONTROLLER_MODE          Controller mode: "standalone" or "distributed"
  CONTROLLER_ID            Unique controller ID
  CONTROLLER_NAME          Human-readable controller name
  PARENT_CONTROLLER_URL    Parent controller URL
      `);
      process.exit(0);
    }
  }

  return args;
}

async function main() {
  const args = parseArgs();

  // Defaults
  const port = args.port || 3000;
  const dbPath = args.dbPath || join(process.cwd(), 'data', 'controller.db');
  const storagePath = args.storagePath || join(process.cwd(), 'storage');

  // Ensure directories exist
  const dbDir = join(dbPath, '..');
  if (!existsSync(dbDir)) {
    mkdirSync(dbDir, { recursive: true });
  }
  if (!existsSync(storagePath)) {
    mkdirSync(storagePath, { recursive: true });
  }

  // Create validated config
  const config = createConfig({
    port,
    dbPath,
    storagePath,
    ...(args.apiKey && { apiKey: args.apiKey }),
    ...(args.mode && { mode: args.mode }),
    ...(args.controllerId && { controllerId: args.controllerId }),
    ...(args.controllerName && { controllerName: args.controllerName }),
    ...(args.parentControllerUrl && { parentControllerUrl: args.parentControllerUrl }),
  });

  // Start server
  const server = new ControllerServer(config);
  await server.start();

  // Graceful shutdown
  const shutdown = async (signal: string) => {
    console.log(`\n\nReceived ${signal}, shutting down gracefully...`);
    await server.stop();
    process.exit(0);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
