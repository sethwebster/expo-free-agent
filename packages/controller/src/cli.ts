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
  --help, -h               Show this help message

Examples:
  expo-controller start
  expo-controller start --port 8080
  expo-controller start --db /var/data/db.sqlite --storage /var/storage
  expo-controller start --api-key "my-secure-key-min-16-chars"

Environment Variables:
  CONTROLLER_API_KEY       API key for authentication (overridden by --api-key)
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
