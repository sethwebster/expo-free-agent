import { Command } from 'commander';
import { apiClient, APIClient } from '../api-client.js';
import chalk from 'chalk';
import ora from 'ora';

export function createListCommand(): Command {
  const command = new Command('list');

  command
    .description('List all builds')
    .option('-l, --limit <number>', 'Limit number of results', '10')
    .option('--api-key <key>', 'API key for authentication')
    .option('--controller-url <url>', 'Controller URL')
    .action(async (options) => {
      const spinner = ora('Fetching builds').start();

      try {
        const client = (options.apiKey || options.controllerUrl)
          ? new APIClient(options.controllerUrl, options.apiKey)
          : apiClient;

        const builds = await client.listBuilds();
        spinner.stop();

        if (builds.length === 0) {
          console.log();
          console.log(chalk.yellow('No builds found'));
          console.log();
          return;
        }

        console.log();
        console.log(chalk.bold('Recent Builds:'));
        console.log();

        const limit = parseInt(options.limit, 10);
        const displayBuilds = builds.slice(0, limit);

        displayBuilds.forEach((build) => {
          const statusColor = getStatusColor(build.status);
          const createdAt = new Date(build.createdAt).toLocaleString();

          console.log(chalk.bold('ID:'), build.id);
          console.log('  Status:', statusColor);
          console.log('  Created:', createdAt);

          if (build.completedAt) {
            const duration = Math.round(
              (new Date(build.completedAt).getTime() - new Date(build.createdAt).getTime()) / 1000
            );
            console.log('  Duration:', formatDuration(duration));
          }

          console.log();
        });

        if (builds.length > limit) {
          console.log(chalk.gray(`... and ${builds.length - limit} more`));
          console.log();
        }

        console.log('View details:', chalk.cyan('expo-controller status <build-id>'));
        console.log();
      } catch (error) {
        spinner.fail(chalk.red('Failed to list builds'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
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

function formatDuration(seconds: number): string {
  const minutes = Math.floor(seconds / 60);
  const secs = seconds % 60;
  if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  }
  return `${secs}s`;
}
