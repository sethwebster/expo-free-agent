import { Command } from 'commander';
import { apiClient, APIClient } from '../api-client.js';
import chalk from 'chalk';
import ora from 'ora';

export function createCancelCommand(): Command {
  const command = new Command('cancel');

  command
    .description('Cancel a build')
    .argument('<build-id>', 'Build ID to cancel')
    .option('--api-key <key>', 'API key for authentication')
    .option('--controller-url <url>', 'Controller URL')
    .action(async (buildId: string, options) => {
      const spinner = ora('Cancelling build').start();

      try {
        const client = (options.apiKey || options.controllerUrl)
          ? new APIClient(options.controllerUrl, options.apiKey)
          : apiClient;

        await client.cancelBuild(buildId);
        spinner.succeed(chalk.green('Build cancelled successfully'));

        console.log();
        console.log(chalk.bold('Build ID:'), buildId);
        console.log(chalk.bold('Status:'), chalk.yellow('cancelled'));
        console.log();
      } catch (error) {
        spinner.fail(chalk.red('Failed to cancel build'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}
