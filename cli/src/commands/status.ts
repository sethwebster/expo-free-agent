import { Command } from 'commander';
import { apiClient, APIClient } from '../api-client.js';
import chalk from 'chalk';
import ora from 'ora';
import cliProgress from 'cli-progress';

const MAX_WATCH_DURATION_MS = 30 * 60 * 1000; // 30 minutes
const INITIAL_POLL_INTERVAL_MS = 2000; // Start at 2 seconds
const MAX_POLL_INTERVAL_MS = 30000; // Cap at 30 seconds
const BACKOFF_MULTIPLIER = 1.5;

export function createStatusCommand(): Command {
  const command = new Command('status');

  command
    .description('Check the status of a build')
    .argument('<build-id>', 'Build ID to check')
    .option('-w, --watch', 'Watch build progress and poll for updates')
    .option('--api-key <key>', 'API key for authentication')
    .option('--controller-url <url>', 'Controller URL')
    .action(async (buildId: string, options) => {
      try {
        const client = (options.apiKey || options.controllerUrl)
          ? new APIClient(options.controllerUrl, options.apiKey)
          : apiClient;

        if (options.watch) {
          await watchBuildStatus(buildId, client);
        } else {
          const spinner = ora('Fetching build status').start();
          const status = await client.getBuildStatus(buildId);
          spinner.stop();

          displayBuildStatus(status);
        }
      } catch (error) {
        console.error(chalk.red('Failed to get build status'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}

function displayBuildStatus(status: any): void {
  console.log();
  console.log(chalk.bold('Build ID:'), status.id);
  console.log(chalk.bold('Status:'), getStatusColor(status.status));
  console.log(chalk.bold('Created:'), new Date(status.createdAt).toLocaleString());

  if (status.completedAt) {
    console.log(chalk.bold('Completed:'), new Date(status.completedAt).toLocaleString());
    const duration = Math.round(
      (new Date(status.completedAt).getTime() - new Date(status.createdAt).getTime()) / 1000
    );
    console.log(chalk.bold('Duration:'), formatDuration(duration));
  }

  if (status.error) {
    console.log(chalk.bold('Error:'), chalk.red(status.error));
  }

  console.log();

  if (status.status === 'completed') {
    console.log(chalk.green('Build completed successfully!'));
    console.log('Download:', chalk.cyan(`expo-controller download ${status.id}`));
  } else if (status.status === 'failed') {
    console.log(chalk.red('Build failed'));
  } else {
    console.log(chalk.yellow('Build in progress...'));
    console.log('Watch progress:', chalk.cyan(`expo-controller status ${status.id} --watch`));
  }

  console.log();
}

async function watchBuildStatus(buildId: string, client: APIClient = apiClient): Promise<void> {
  console.log(chalk.bold('Watching build:'), buildId);
  console.log(chalk.dim('Max watch time: 30 minutes'));
  console.log();

  const bar = new cliProgress.SingleBar({
    format: `Build Progress |${chalk.cyan('{bar}')}| {status}`,
    barCompleteChar: '\u2588',
    barIncompleteChar: '\u2591',
    hideCursor: true,
  });

  let started = false;
  const startTime = Date.now();
  let pollInterval = INITIAL_POLL_INTERVAL_MS;
  let consecutiveErrors = 0;

  while (true) {
    const elapsed = Date.now() - startTime;

    // Check max timeout
    if (elapsed > MAX_WATCH_DURATION_MS) {
      if (started) {
        bar.stop();
      }
      console.log();
      console.log(chalk.red('Watch timeout exceeded (30 minutes)'));
      console.log('Build may still be running. Check status manually:');
      console.log(chalk.cyan(`expo-controller status ${buildId}`));
      console.log();
      process.exit(1);
    }

    try {
      const status = await client.getBuildStatus(buildId);

      // Reset error counter on success
      consecutiveErrors = 0;

      if (!started) {
        bar.start(100, 0, { status: status.status });
        started = true;
      }

      // Update progress based on status
      let progress = 0;
      if (status.status === 'pending') progress = 10;
      else if (status.status === 'building') progress = 50;
      else if (status.status === 'completed' || status.status === 'failed') progress = 100;

      bar.update(progress, { status: getStatusText(status.status) });

      if (status.status === 'completed') {
        bar.stop();
        const duration = Math.round((Date.now() - startTime) / 1000);
        console.log();
        console.log(chalk.green('Build completed successfully!'));
        console.log(chalk.bold('Duration:'), formatDuration(duration));
        console.log('Download:', chalk.cyan(`expo-controller download ${buildId}`));
        console.log();
        break;
      } else if (status.status === 'failed') {
        bar.stop();
        console.log();
        console.log(chalk.red('Build failed'));
        if (status.error) {
          console.log(chalk.red('Error:'), status.error);
        }
        console.log();
        process.exit(1);
      }

      // Exponential backoff for polling
      await new Promise((resolve) => setTimeout(resolve, pollInterval));
      pollInterval = Math.min(pollInterval * BACKOFF_MULTIPLIER, MAX_POLL_INTERVAL_MS);
    } catch (error) {
      consecutiveErrors++;

      if (consecutiveErrors >= 5) {
        if (started) {
          bar.stop();
        }
        console.log();
        console.log(chalk.red('Too many consecutive errors (5). Stopping watch.'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        console.log();
        console.log('Try again:', chalk.cyan(`expo-controller status ${buildId} --watch`));
        console.log();
        process.exit(1);
      }

      // Wait before retry on error (don't increase poll interval on errors)
      await new Promise((resolve) => setTimeout(resolve, pollInterval));
    }
  }
}

function getStatusColor(status: string): string {
  switch (status) {
    case 'completed':
      return chalk.green(status);
    case 'failed':
      return chalk.red(status);
    case 'building':
      return chalk.yellow(status);
    default:
      return chalk.gray(status);
  }
}

function getStatusText(status: string): string {
  switch (status) {
    case 'pending':
      return 'Waiting for worker...';
    case 'building':
      return 'Building...';
    case 'completed':
      return 'Completed';
    case 'failed':
      return 'Failed';
    default:
      return status;
  }
}

function formatDuration(seconds: number): string {
  const minutes = Math.floor(seconds / 60);
  const secs = seconds % 60;
  if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  }
  return `${secs}s`;
}
