import { Command } from 'commander';
import { loadConfig, saveConfig } from '../config.js';
import chalk from 'chalk';

export function createConfigCommand(): Command {
  const command = new Command('config');

  command
    .description('Manage CLI configuration')
    .option('--set-url <url>', 'Set controller URL')
    .option('--set-api-key <key>', 'Set API key')
    .option('--show', 'Show current configuration')
    .action(async (options) => {
      try {
        if (options.setUrl) {
          await saveConfig({ controllerUrl: options.setUrl });
          console.log(chalk.green('Controller URL updated:'), options.setUrl);
          return;
        }

        if (options.setApiKey) {
          await saveConfig({ apiKey: options.setApiKey });
          console.log(chalk.green('API key updated'));
          return;
        }

        if (options.show) {
          const config = await loadConfig();
          console.log();
          console.log(chalk.bold('Configuration:'));
          console.log('  Controller URL:', config.controllerUrl);
          console.log('  API Key:', config.apiKey ? maskApiKey(config.apiKey) : chalk.dim('(not set)'));
          console.log();
          return;
        }

        // Default: show config
        const config = await loadConfig();
        console.log();
        console.log(chalk.bold('Configuration:'));
        console.log('  Controller URL:', config.controllerUrl);
        console.log('  API Key:', config.apiKey ? maskApiKey(config.apiKey) : chalk.dim('(not set)'));
        console.log();
      } catch (error) {
        console.error(chalk.red('Failed to manage config'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}

function maskApiKey(key: string): string {
  if (key.length <= 8) return '****';
  return key.slice(0, 4) + '****' + key.slice(-4);
}
