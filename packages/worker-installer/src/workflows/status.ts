import chalk from 'chalk';
import {
  isAppInstalled,
  getInstalledVersion
} from '../install.js';
import {
  isAppRunning,
  isInLoginItems
} from '../launch.js';
import {
  loadConfiguration,
  getConfigPath
} from '../config.js';
import { displayBanner } from '../ui.js';

export async function showStatus(): Promise<void> {
  displayBanner();

  const installed = isAppInstalled();
  const running = isAppRunning();
  const inLoginItems = isInLoginItems();
  const config = loadConfiguration();

  console.log(chalk.bold('Worker Status:'));
  console.log();

  // Installation status
  console.log(
    '  Installed:',
    installed ? chalk.green('Yes') + chalk.gray(` (${getInstalledVersion()})`) : chalk.red('No')
  );

  // Running status
  console.log('  Running:', running ? chalk.green('Yes') : chalk.yellow('No'));

  // Login items
  console.log('  Auto-start:', inLoginItems ? chalk.green('Enabled') : chalk.gray('Disabled'));

  console.log();

  // Configuration
  if (config) {
    console.log(chalk.bold('Configuration:'));
    console.log('  Controller:', config.controllerURL || chalk.dim('(not configured)'));
    console.log('  Worker ID:', config.workerID || chalk.dim('(not registered)'));
    console.log('  Device:', config.deviceName || chalk.dim('(unknown)'));
    console.log('  Config file:', chalk.dim(getConfigPath()));
    console.log();
  } else {
    console.log(chalk.yellow('Not configured yet'));
    console.log(chalk.dim('Run the installer to configure: npx @sethwebster/expo-free-agent-worker\n'));
  }

  // Recommendations
  if (installed && !running) {
    console.log(chalk.yellow('💡 Worker is installed but not running'));
    console.log(chalk.dim('   Launch it from /Applications/FreeAgent.app\n'));
  }

  if (!installed) {
    console.log(chalk.yellow('💡 Worker not installed'));
    console.log(chalk.dim('   Run: npx @sethwebster/expo-free-agent-worker\n'));
  }
}
