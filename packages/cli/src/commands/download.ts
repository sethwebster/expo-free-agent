import { Command } from 'commander';
import path from 'path';
import { apiClient, APIClient } from '../api-client.js';
import chalk from 'chalk';
import ora from 'ora';
import fs from 'fs';

export function createDownloadCommand(): Command {
  const command = new Command('download');

  command
    .description('Download a completed build')
    .argument('<build-id>', 'Build ID to download')
    .option('-o, --output <path>', 'Output file path', './build.ipa')
    .option('--api-key <key>', 'API key for authentication')
    .option('--controller-url <url>', 'Controller URL')
    .action(async (buildId: string, options) => {
      const spinner = ora('Checking build status').start();

      try {
        const client = (options.apiKey || options.controllerUrl)
          ? new APIClient(options.controllerUrl, options.apiKey)
          : apiClient;

        // Check if build is completed
        const status = await client.getBuildStatus(buildId);

        if (status.status !== 'completed') {
          spinner.fail(chalk.red(`Build is not ready (status: ${status.status})`));
          console.log();
          console.log('Check status:', chalk.cyan(`expo-controller status ${buildId}`));
          console.log();
          process.exit(1);
        }

        const outputPath = path.resolve(options.output);

        // Check if file exists
        const fileExists = await fs.promises
          .access(outputPath)
          .then(() => true)
          .catch(() => false);

        if (fileExists) {
          spinner.stop();
          console.log(chalk.yellow(`File already exists: ${outputPath}`));
          console.log();
          console.log('Overwrite? Press Enter to continue, Ctrl+C to cancel');

          // Wait for user confirmation
          await new Promise<void>((resolve) => {
            process.stdin.once('data', () => resolve());
          });

          spinner.start('Downloading build');
        } else {
          spinner.text = 'Downloading build';
        }

        let lastUpdate = Date.now();
        const startTime = Date.now();

        await client.downloadBuild(buildId, outputPath, (downloadedBytes) => {
          // Update spinner every 500ms to avoid too many updates
          const now = Date.now();
          if (now - lastUpdate > 500) {
            const elapsed = (now - startTime) / 1000;
            const speed = downloadedBytes / elapsed;
            spinner.text = `Downloading build (${formatBytes(downloadedBytes)} @ ${formatBytes(speed)}/s)`;
            lastUpdate = now;
          }
        });

        const fileSize = (await fs.promises.stat(outputPath)).size;
        spinner.succeed(chalk.green('Build downloaded successfully'));

        console.log();
        console.log(chalk.bold('File:'), outputPath);
        console.log(chalk.bold('Size:'), formatBytes(fileSize));
        console.log();
      } catch (error) {
        spinner.fail(chalk.red('Download failed'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}
