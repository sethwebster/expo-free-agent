import { Command } from 'commander';
import { execSync } from 'child_process';
import chalk from 'chalk';
import ora from 'ora';

const WORKER_APP_PATH = '/Applications/FreeAgent.app';
const WORKER_PROCESS_NAME = 'FreeAgent';

export function createWorkerCommand(): Command {
  const command = new Command('worker');

  command.description('Manage Free Agent Worker');

  // Status subcommand
  command
    .command('status')
    .description('Show worker status')
    .action(async () => {
      try {
        const installed = isWorkerInstalled();
        const running = isWorkerRunning();

        console.log();
        console.log(chalk.bold('Worker Status:'));
        console.log();
        console.log('  Installed:', installed ? chalk.green('Yes') : chalk.red('No'));
        console.log('  Running:', running ? chalk.green('Yes') : chalk.yellow('No'));
        console.log();

        if (!installed) {
          console.log(chalk.yellow('💡 Worker not installed'));
          console.log(chalk.dim('   Run: npx @sethwebster/expo-free-agent worker install\n'));
        } else if (!running) {
          console.log(chalk.yellow('💡 Worker is installed but not running'));
          console.log(chalk.dim('   Run: npx @sethwebster/expo-free-agent worker start\n'));
        }
      } catch (error) {
        console.error(chalk.red('Failed to get worker status'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  // Start subcommand
  command
    .command('start')
    .description('Start the worker')
    .action(async () => {
      const spinner = ora('Starting worker').start();

      try {
        if (!isWorkerInstalled()) {
          spinner.fail(chalk.red('Worker not installed'));
          console.log();
          console.log('Install it first:', chalk.cyan('npx @sethwebster/expo-free-agent worker install'));
          console.log();
          process.exit(1);
        }

        if (isWorkerRunning()) {
          spinner.info('Worker is already running');
          return;
        }

        // Remove ALL quarantine attributes and reset Gatekeeper cache
        try {
          execSync(`xattr -cr "${WORKER_APP_PATH}"`, { stdio: 'pipe' });
          execSync(`xattr -d com.apple.quarantine "${WORKER_APP_PATH}" 2>/dev/null || true`, { stdio: 'pipe' });
          // Reset Launch Services database entry
          execSync(`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "${WORKER_APP_PATH}"`, { stdio: 'pipe' });
        } catch {
          // Ignore if commands fail
        }

        execSync(`open -a "${WORKER_APP_PATH}"`, { stdio: 'pipe' });
        spinner.succeed('Worker started');

        console.log();
        console.log(chalk.dim('Look for the Free Agent icon in your menu bar'));
        console.log();
      } catch (error) {
        spinner.fail('Failed to start worker');
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  // Stop subcommand
  command
    .command('stop')
    .description('Stop the worker')
    .action(async () => {
      const spinner = ora('Stopping worker').start();

      try {
        if (!isWorkerRunning()) {
          spinner.info('Worker is not running');
          return;
        }

        execSync(`pkill -f "${WORKER_PROCESS_NAME}"`, { stdio: 'pipe' });
        spinner.succeed('Worker stopped');
      } catch (error) {
        spinner.fail('Failed to stop worker');
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  // Install subcommand
  command
    .command('install')
    .description('Install the worker')
    .action(async () => {
      console.log();
      console.log(chalk.bold.cyan('Installing Expo Free Agent Worker'));
      console.log();
      console.log('Launching installer...');
      console.log();

      try {
        execSync('npx @sethwebster/expo-free-agent-worker@latest', { stdio: 'inherit' });
      } catch (error) {
        console.error(chalk.red('Installation failed'));
        process.exit(1);
      }
    });

  return command;
}

function isWorkerInstalled(): boolean {
  try {
    execSync(`test -d "${WORKER_APP_PATH}"`, { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

function isWorkerRunning(): boolean {
  try {
    const result = execSync(`pgrep -f "${WORKER_PROCESS_NAME}"`, { stdio: 'pipe', encoding: 'utf-8' });
    return result.trim().length > 0;
  } catch {
    return false;
  }
}
