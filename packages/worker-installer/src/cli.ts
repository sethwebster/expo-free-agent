#!/usr/bin/env node

import { Command } from 'commander';
import chalk from 'chalk';
import { installWorker } from './workflows/install.js';
import { showStatus } from './workflows/status.js';
import type { InstallOptions } from './types.js';

async function main(): Promise<void> {
  const program = new Command();

  program
    .name('expo-free-agent-worker')
    .description('Install and configure the Expo Free Agent Worker macOS app')
    .version('0.1.12');

  // Default action (install/configure)
  program
    .option('--controller-url <url>', 'Controller URL')
    .option('--api-key <key>', 'API key for authentication')
    .option('--skip-launch', 'Skip launching the app after installation')
    .option('--force', 'Force reinstall if already installed')
    .option('--verbose', 'Verbose output')
    .option('-y, --yes', 'Auto-accept all prompts')
    .action(async (options) => {
      try {
        await installWorker({
          controllerUrl: options.controllerUrl,
          apiKey: options.apiKey,
          skipLaunch: options.skipLaunch,
          verbose: options.verbose,
          forceReinstall: options.force,
          autoAccept: options.yes
        });
      } catch (error) {
        console.error(chalk.red('\n❌ Installation failed:'), error instanceof Error ? error.message : String(error));

        if (options.verbose && error instanceof Error && error.stack) {
          console.error(chalk.dim(error.stack));
        }

        process.exit(1);
      }
    });

  // Status command
  program
    .command('status')
    .description('Show worker status and configuration')
    .action(async () => {
      try {
        await showStatus();
      } catch (error) {
        console.error(chalk.red('Failed to get status'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  await program.parseAsync(process.argv);
}

main();
