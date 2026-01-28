#!/usr/bin/env node
import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { existsSync } from 'fs';
import { execSync } from 'child_process';

const WORKER_APP_PATH = '/Applications/FreeAgent.app';

function isWorkerInstalled(): boolean {
  return existsSync(WORKER_APP_PATH);
}

function isWorkerRunning(): boolean {
  try {
    const output = execSync('pgrep -f "FreeAgent.app"', { encoding: 'utf8' });
    return output.trim().length > 0;
  } catch {
    return false;
  }
}

function launchWorker(): void {
  // Remove quarantine attribute to prevent "damaged app" error
  try {
    execSync(`xattr -cr "${WORKER_APP_PATH}"`, { stdio: 'pipe' });
  } catch {
    // Ignore if xattr fails (might not have attribute)
  }

  execSync(`open "${WORKER_APP_PATH}"`, { stdio: 'inherit' });
}

async function startWorker(): Promise<void> {
  if (!isWorkerInstalled()) {
    console.log(chalk.yellow('⚠️  Free Agent Worker is not installed yet.\n'));
    console.log(chalk.white('Installing the worker to start earning credits...\n'));

    try {
      execSync('npx @sethwebster/expo-free-agent-worker@latest', {
        stdio: 'inherit'
      });
    } catch (error) {
      console.error(chalk.red('\n❌ Installation failed'));
      process.exit(1);
    }

    console.log(chalk.green('\n✓ Installation complete!'));
    console.log(chalk.dim('\nLook for the Free Agent icon in your menu bar.'));
    console.log(chalk.dim('Click "Start Worker" to begin earning credits.\n'));
    return;
  }

  if (isWorkerRunning()) {
    console.log(chalk.green('✓ Free Agent Worker is already running!'));
    console.log(chalk.dim('\nLook for the Free Agent icon in your menu bar.\n'));
    return;
  }

  const spinner = ora('Starting Free Agent Worker...').start();

  try {
    launchWorker();

    // Give it a moment to start
    await new Promise(resolve => setTimeout(resolve, 1000));

    if (isWorkerRunning()) {
      spinner.succeed('Free Agent Worker started successfully!');
      console.log(chalk.dim('\nLook for the Free Agent icon in your menu bar.'));
      console.log(chalk.dim('Click it to view build activity and settings.\n'));
    } else {
      spinner.warn('Worker app opened, but may still be starting...');
      console.log(chalk.dim('\nCheck your menu bar for the Free Agent icon.\n'));
    }
  } catch (error) {
    spinner.fail('Failed to start worker');
    console.error(chalk.red('\nError:'), error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}

export function createStartCommand(): Command {
  return new Command('start')
    .description('Start the Free Agent Worker to earn build credits')
    .action(async () => {
      try {
        await startWorker();
      } catch (error) {
        console.error(chalk.red('\n❌ Error:'), error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });
}
