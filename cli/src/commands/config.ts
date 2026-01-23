import { Command } from 'commander';
import { loadConfig, saveConfig } from '../config.js';
import chalk from 'chalk';

export function createConfigCommand(): Command {
  const command = new Command('config');

  command
    .description('Manage CLI configuration')
    .option('--set-url <url>', 'Set controller URL')
    .option('--show', 'Show current configuration')
    .action(async (options) => {
      try {
        if (options.setUrl) {
          await saveConfig({ controllerUrl: options.setUrl });
          console.log(chalk.green('Controller URL updated:'), options.setUrl);
          return;
        }

        if (options.show) {
          const config = await loadConfig();
          console.log();
          console.log(chalk.bold('Configuration:'));
          console.log('  Controller URL:', config.controllerUrl);
          console.log();
          return;
        }

        // Default: show config
        const config = await loadConfig();
        console.log();
        console.log(chalk.bold('Configuration:'));
        console.log('  Controller URL:', config.controllerUrl);
        console.log();
      } catch (error) {
        console.error(chalk.red('Failed to manage config'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}
