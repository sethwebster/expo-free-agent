#!/usr/bin/env node

import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import prompts from 'prompts';
import { hostname } from 'os';
import {
  runPreflightChecks,
  getWorkerCapabilities,
  checkTart
} from './preflight.js';
import {
  downloadAndVerifyRelease,
  verifyCodeSignature,
  getSigningInfo,
  cleanupDownload
} from './download.js';
import {
  installApp,
  isAppInstalled,
  getInstalledVersion,
  validateAppBundle,
  uninstallApp
} from './install.js';
import {
  registerWorker,
  testConnection,
  createConfiguration
} from './register.js';
import { generatePublicIdentifier } from './identifier.js';
import {
  saveConfiguration,
  loadConfiguration,
  getConfigPath
} from './config.js';
import {
  launchApp,
  addToLoginItems,
  isAppRunning,
  isInLoginItems
} from './launch.js';
import type { InstallOptions } from './types.js';

const DEFAULT_CONTROLLER_URL = 'https://expo-free-agent-controller.projects.sethwebster.com';

function displayBanner(): void {
  console.log(chalk.bold.cyan('\nExpo Free Agent Worker Installer'));
  console.log(chalk.gray('=====================================\n'));
}

function displayPreflightResults(results: ReturnType<typeof runPreflightChecks>): boolean {
  console.log(chalk.bold('Checking system requirements...\n'));

  let hasErrors = false;
  let hasWarnings = false;

  for (const result of results) {
    let symbol = '';
    let color = chalk.white;

    switch (result.status) {
      case 'ok':
        symbol = chalk.green('[OK]');
        color = chalk.white;
        break;
      case 'warn':
        symbol = chalk.yellow('[WARN]');
        color = chalk.yellow;
        hasWarnings = true;
        break;
      case 'error':
        symbol = chalk.red('[ERROR]');
        color = chalk.red;
        hasErrors = true;
        break;
    }

    console.log(`  ${symbol} ${result.check}: ${color(result.message)}`);

    if (result.details && (result.status === 'warn' || result.status === 'error')) {
      console.log(`       ${chalk.dim(result.details)}`);
    }
  }

  console.log();

  if (hasErrors) {
    console.log(chalk.red.bold('❌ Critical errors detected. Please fix them before installing.\n'));
    return false;
  }

  if (hasWarnings) {
    console.log(chalk.yellow('⚠️  Warnings detected. Installation can continue but functionality may be limited.\n'));
  }

  return true;
}

async function promptForConfiguration(
  options: InstallOptions
): Promise<{ controllerURL: string; apiKey: string }> {
  const existingConfig = loadConfiguration();

  const questions = [];

  if (!options.controllerUrl) {
    questions.push({
      type: 'text',
      name: 'controllerURL',
      message: 'Controller URL:',
      initial: existingConfig?.controllerURL || DEFAULT_CONTROLLER_URL,
      validate: (value: string) => {
        if (!value) return 'Controller URL is required';
        if (!value.startsWith('http://') && !value.startsWith('https://')) {
          return 'URL must start with http:// or https://';
        }
        return true;
      }
    });
  }

  if (!options.apiKey) {
    questions.push({
      type: 'password',
      name: 'apiKey',
      message: 'API Key:',
      initial: existingConfig?.apiKey,
      validate: (value: string) => value ? true : 'API Key is required'
    });
  }

  const answers = await prompts(questions, {
    onCancel: () => {
      console.log(chalk.yellow('\nInstallation cancelled.'));
      process.exit(0);
    }
  });

  return {
    controllerURL: options.controllerUrl || answers.controllerURL,
    apiKey: options.apiKey || answers.apiKey
  };
}

async function installWorker(options: InstallOptions): Promise<void> {
  displayBanner();

  // Check if already installed
  if (isAppInstalled() && !options.forceReinstall) {
    const installedVersion = getInstalledVersion();
    console.log(chalk.yellow(`Free Agent Worker is already installed (version ${installedVersion}).\n`));

    const { action } = await prompts({
      type: 'select',
      name: 'action',
      message: 'What would you like to do?',
      choices: [
        { title: 'Update/Reinstall', value: 'reinstall' },
        { title: 'Reconfigure', value: 'reconfigure' },
        { title: 'Uninstall', value: 'uninstall' },
        { title: 'Cancel', value: 'cancel' }
      ]
    });

    if (action === 'cancel') {
      console.log(chalk.gray('Cancelled.'));
      return;
    }

    if (action === 'uninstall') {
      const spinner = ora('Uninstalling...').start();
      try {
        uninstallApp();
        spinner.succeed('Uninstalled successfully');
        return;
      } catch (error) {
        spinner.fail('Uninstallation failed');
        throw error;
      }
    }

    if (action === 'reconfigure') {
      const config = await promptForConfiguration(options);
      const spinner = ora('Testing connection...').start();

      const reachable = await testConnection(config.controllerURL);
      if (!reachable) {
        spinner.warn('Controller unreachable, but saving configuration anyway');
      } else {
        spinner.succeed('Controller reachable');
      }

      const capabilities = getWorkerCapabilities();
      const deviceName = hostname();

      spinner.start('Registering worker...');
      try {
        const registration = await registerWorker(
          config.controllerURL,
          config.apiKey,
          capabilities
        );

        spinner.succeed(`Worker registered (ID: ${registration.workerID})`);

        const fullConfig = createConfiguration(
          config.controllerURL,
          config.apiKey,
          registration.workerID,
          deviceName,
          registration.publicIdentifier
        );

        saveConfiguration(fullConfig);
        console.log(chalk.gray(`\nConfiguration saved to ${getConfigPath()}\n`));
      } catch (error) {
        spinner.fail('Registration failed');
        throw error;
      }

      return;
    }

    // Continue with reinstall
    options.forceReinstall = true;
  }

  // Run pre-flight checks
  const preflightResults = runPreflightChecks(options.verbose || false);
  const canContinue = displayPreflightResults(preflightResults);

  if (!canContinue) {
    process.exit(1);
  }

  // Check for Tart - offer to install
  const tartCheck = checkTart();
  if (tartCheck.status !== 'ok') {
    const { installTart } = await prompts({
      type: 'confirm',
      name: 'installTart',
      message: 'Tart is required for VMs. Would you like to install it via Homebrew?',
      initial: true
    });

    if (installTart) {
      const spinner = ora('Installing Tart...').start();
      try {
        const { execSync } = await import('child_process');
        execSync('brew install cirruslabs/cli/tart', { stdio: 'inherit' });
        spinner.succeed('Tart installed');
      } catch (error) {
        spinner.fail('Failed to install Tart');
        console.log(chalk.yellow('You can install it manually: brew install cirruslabs/cli/tart\n'));
      }
    }
  }

  const { proceed } = await prompts({
    type: 'confirm',
    name: 'proceed',
    message: 'Continue with installation?',
    initial: true
  });

  if (!proceed) {
    console.log(chalk.gray('Cancelled.'));
    return;
  }

  // Download binary
  console.log();
  let appPath: string | null = null;
  let version: string | null = null;

  const downloadSpinner = ora('Fetching latest release...').start();

  try {
    const result = await downloadAndVerifyRelease((progress) => {
      const percent = progress.percent.toFixed(1);
      const mb = (progress.transferred / 1024 / 1024).toFixed(1);
      const totalMb = (progress.total / 1024 / 1024).toFixed(1);
      downloadSpinner.text = `Downloading ${version || 'release'}... ${percent}% (${mb}/${totalMb} MB)`;
    });

    appPath = result.appPath;
    version = result.version;

    downloadSpinner.succeed(`Downloaded ${version}`);
  } catch (error) {
    downloadSpinner.fail('Download failed');
    throw error;
  }

  // Verify app bundle
  const validationSpinner = ora('Validating app bundle...').start();
  const validation = validateAppBundle(appPath);

  if (!validation.valid) {
    validationSpinner.fail(`Invalid app bundle: ${validation.error}`);
    cleanupDownload(appPath);
    process.exit(1);
  }

  validationSpinner.succeed('App bundle valid');

  // Verify code signature (optional, may not be signed in development)
  const signatureSpinner = ora('Verifying code signature...').start();
  const isSigned = verifyCodeSignature(appPath);

  if (isSigned) {
    const signingInfo = getSigningInfo(appPath);
    signatureSpinner.succeed('Code signature verified');
    if (options.verbose && signingInfo) {
      console.log(chalk.dim(signingInfo));
    }
  } else {
    signatureSpinner.warn('App is not signed (development build)');
  }

  // Install to /Applications
  const installSpinner = ora('Installing to /Applications...').start();

  try {
    installApp(appPath, options.forceReinstall || false);
    installSpinner.succeed('Installed to /Applications/FreeAgent.app');
  } catch (error) {
    installSpinner.fail('Installation failed');
    cleanupDownload(appPath);
    throw error;
  }

  // Cleanup temporary files
  cleanupDownload(appPath);

  // Configuration
  console.log();
  const config = await promptForConfiguration(options);

  const connectionSpinner = ora('Testing connection...').start();
  const reachable = await testConnection(config.controllerURL);

  if (!reachable) {
    connectionSpinner.warn('Controller unreachable, but continuing anyway');
    console.log(chalk.dim('  You can reconfigure later via the app Settings or by re-running this installer.\n'));
  } else {
    connectionSpinner.succeed('Controller reachable');
  }

  // Register worker
  const capabilities = getWorkerCapabilities();
  const deviceName = hostname();

  const registerSpinner = ora('Registering worker...').start();

  try {
    const registration = await registerWorker(
      config.controllerURL,
      config.apiKey,
      capabilities
    );

    registerSpinner.succeed(`Worker registered (ID: ${registration.workerID}, Name: ${registration.publicIdentifier})`);

    const fullConfig = createConfiguration(
      config.controllerURL,
      config.apiKey,
      registration.workerID,
      deviceName,
      registration.publicIdentifier
    );

    saveConfiguration(fullConfig);
    console.log(chalk.gray(`Configuration saved to ${getConfigPath()}`));
  } catch (error) {
    registerSpinner.fail('Registration failed');
    console.log(chalk.yellow('Saving configuration anyway. You can retry registration from the app.\n'));

    const fallbackIdentifier = generatePublicIdentifier();
    const fallbackConfig = createConfiguration(
      config.controllerURL,
      config.apiKey,
      'pending-registration',
      deviceName,
      fallbackIdentifier
    );

    saveConfiguration(fallbackConfig);
  }

  // Launch app
  console.log();

  if (!options.skipLaunch) {
    const { shouldLaunch } = await prompts({
      type: 'confirm',
      name: 'shouldLaunch',
      message: 'Launch Free Agent Worker now?',
      initial: true
    });

    if (shouldLaunch) {
      const launchSpinner = ora('Launching app...').start();

      try {
        launchApp();
        launchSpinner.succeed('App launched (look for icon in menu bar)');
      } catch (error) {
        launchSpinner.fail('Failed to launch');
        console.log(chalk.yellow('You can launch manually from /Applications/FreeAgent.app\n'));
      }
    }

    // Login items
    if (!isInLoginItems()) {
      const { addToLogin } = await prompts({
        type: 'confirm',
        name: 'addToLogin',
        message: 'Add to Login Items (start automatically on boot)?',
        initial: true
      });

      if (addToLogin) {
        const loginSpinner = ora('Adding to Login Items...').start();

        if (addToLoginItems()) {
          loginSpinner.succeed('Added to Login Items');
        } else {
          loginSpinner.warn('Could not add to Login Items automatically');
          console.log(chalk.dim('  You can add it manually in System Settings > General > Login Items\n'));
        }
      }
    }
  }

  // Success message
  console.log(chalk.green.bold('\n✓ Installation complete!\n'));

  console.log(chalk.bold('Next steps:'));
  console.log('  1. Click the Free Agent icon in your menu bar');
  console.log('  2. Click "Start Worker" to begin accepting builds');
  console.log('  3. Monitor build activity in the app interface\n');

  console.log(chalk.dim('Configuration: ' + getConfigPath()));
  console.log(chalk.dim('Documentation: https://docs.expo.dev/free-agent/\n'));
}

async function showStatus(): Promise<void> {
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

async function main(): Promise<void> {
  const program = new Command();

  program
    .name('expo-free-agent-worker')
    .description('Install and configure the Expo Free Agent Worker macOS app')
    .version('0.1.5');

  // Default action (install/configure)
  program
    .option('--controller-url <url>', 'Controller URL')
    .option('--api-key <key>', 'API key for authentication')
    .option('--skip-launch', 'Skip launching the app after installation')
    .option('--force', 'Force reinstall if already installed')
    .option('--verbose', 'Verbose output')
    .action(async (options) => {
      // If no command specified and no options, treat as install
      if (process.argv.length === 2) {
        try {
          await installWorker({
            controllerUrl: options.controllerUrl,
            apiKey: options.apiKey,
            skipLaunch: options.skipLaunch,
            verbose: options.verbose,
            forceReinstall: options.force
          });
        } catch (error) {
          console.error(chalk.red('\n❌ Installation failed:'), error instanceof Error ? error.message : String(error));

          if (options.verbose && error instanceof Error && error.stack) {
            console.error(chalk.dim(error.stack));
          }

          process.exit(1);
        }
      }
    });

  // Status command
  program
    .command('status')
    .description('Show worker status and configuration')
    .action(async () => {
      try {
        await showStatus();
      } catch (error) {
        console.error(chalk.red('Failed to get status'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  await program.parseAsync(process.argv);
}

main();
