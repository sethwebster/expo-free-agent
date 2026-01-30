import { Command } from 'commander';
import { apiClient } from '../api-client.js';
import { saveBuildToken } from '../build-tokens.js';
import { getApiKey } from '../config.js';
import chalk from 'chalk';
import ora from 'ora';

export function createRetryCommand(): Command {
  const command = new Command('retry');

  command
    .description('Retry a failed or completed build with the same source')
    .argument('<build-id>', 'Build ID to retry')
    .option('--api-key <key>', 'API key for authentication')
    .option('--controller-url <url>', 'Controller URL')
    .action(async (buildId: string, options) => {
      const spinner = ora('Retrying build...').start();

      try {
        await apiClient.init();

        // Get headers for authentication
        const headers: Record<string, string> = {};
        if (options.apiKey) {
          headers['X-API-Key'] = options.apiKey;
        } else {
          const envKey = process.env.EXPO_CONTROLLER_API_KEY;
          if (envKey) {
            headers['X-API-Key'] = envKey;
          } else {
            const configKey = await getApiKey();
            if (configKey) {
              headers['X-API-Key'] = configKey;
            } else {
              // Try build token
              const { getBuildToken } = await import('../build-tokens.js');
              const token = await getBuildToken(buildId);
              if (token) {
                headers['X-Build-Token'] = token;
              }
            }
          }
        }

        const baseUrl = options.controllerUrl || (apiClient as any).baseUrl;
        const response = await fetch(`${baseUrl}/api/builds/${buildId}/retry`, {
          method: 'POST',
          headers,
        });

        if (!response.ok) {
          const error = await response.text();
          spinner.fail(chalk.red('Retry failed'));
          console.error(chalk.red(error));
          process.exit(1);
        }

        const data = await response.json();

        // Store the new build token
        await saveBuildToken(data.id, data.access_token);

        spinner.succeed(chalk.green('Build retried successfully'));

        console.log();
        console.log(chalk.bold('New Build ID:'), data.id);
        console.log(chalk.dim('Original Build ID:'), buildId);
        console.log();
        console.log('Track status:', chalk.cyan(`expo-free-agent status ${data.id}`));
        console.log('View logs:', chalk.cyan(`expo-free-agent logs ${data.id}`));
        console.log('Download when ready:', chalk.cyan(`expo-free-agent download ${data.id}`));
        console.log();
      } catch (error) {
        spinner.fail(chalk.red('Retry failed'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}
