import chalk from 'chalk';
import ora from 'ora';
import prompts from 'prompts';
import { hostname } from 'os';
import {
  runPreflightChecks,
  getWorkerCapabilities,
  checkTart
} from '../preflight.js';
import {
  downloadAndVerifyRelease,
  verifyCodeSignature,
  getSigningInfo,
  cleanupDownload
} from '../download.js';
import {
  installApp,
  isAppInstalled,
  getInstalledVersion,
  validateAppBundle,
  uninstallApp
} from '../install.js';
import {
  registerWorker,
  testConnection,
  createConfiguration
} from '../register.js';
import { generatePublicIdentifier } from '../identifier.js';
import {
  saveConfiguration,
  getConfigPath
} from '../config.js';
import {
  launchApp,
  addToLoginItems,
  isAppRunning,
  isInLoginItems
} from '../launch.js';
import { displayBanner, displayPreflightResults } from '../ui.js';
import { promptForConfiguration } from './configure.js';
import type { InstallOptions } from '../types.js';

export async function installWorker(options: InstallOptions): Promise<void> {
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
    const wasRunning = isAppRunning();
    if (wasRunning) {
      console.log(chalk.yellow('  Worker is currently running and will be restarted after update\n'));
    }

    options.forceReinstall = true;
    // Store flag to skip launch prompts and auto-restart
    options.autoRestart = wasRunning;
  }

  // Run pre-flight checks
  const preflightResults = runPreflightChecks(options.verbose || false);
  const canContinue = displayPreflightResults(preflightResults);

  if (!canContinue) {
    process.exit(1);
  }

  // Check for Tart - offer to install
  const tartCheck = checkTart();
  if (tartCheck.status !== 'ok' && !options.autoAccept) {
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

  if (!options.autoAccept) {
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
  }

  // Download binary
  console.log();
  let appPath: string | null = null;
  let version: string | null = null;

  const downloadSpinner = ora('Fetching latest release...').start();

  try {
    const result = await downloadAndVerifyRelease(
      (progress) => {
        const percent = progress.percent.toFixed(1);
        const mb = (progress.transferred / 1024 / 1024).toFixed(1);
        const totalMb = (progress.total / 1024 / 1024).toFixed(1);
        downloadSpinner.text = `Downloading ${version || 'release'}... ${percent}% (${mb}/${totalMb} MB)`;
      },
      (attempt, maxRetries, error) => {
        downloadSpinner.warn(`Download attempt ${attempt - 1} failed: ${error.message}`);
        downloadSpinner.start(`Retrying download (attempt ${attempt}/${maxRetries})...`);
      }
    );

    appPath = result.appPath;
    version = result.version;

    downloadSpinner.succeed(`Downloaded ${version}`);
  } catch (error) {
    downloadSpinner.fail('Download failed after multiple attempts');
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

  const autoRestart = options.autoRestart;

  if (!options.skipLaunch) {
    // Auto-restart if this was an update and the app was running
    if (autoRestart) {
      const launchSpinner = ora('Restarting Free Agent Worker...').start();

      try {
        launchApp();
        launchSpinner.succeed('Worker restarted (look for icon in menu bar)');
      } catch (error) {
        launchSpinner.fail('Failed to restart');
        console.log(chalk.yellow('You can launch manually from /Applications/FreeAgent.app\n'));
      }
    } else {
      // Normal install flow - prompt user
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

      // Login items (only for fresh installs, not updates)
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
  }

  // Success message
  if (autoRestart) {
    console.log(chalk.green.bold('\n✓ Update complete!\n'));
    console.log(chalk.dim('The worker has been updated and restarted.\n'));
  } else {
    console.log(chalk.green.bold('\n✓ Installation complete!\n'));

    console.log(chalk.bold('Next steps:'));
    console.log('  1. Click the Free Agent icon in your menu bar');
    console.log('  2. Click "Start Worker" to begin accepting builds');
    console.log('  3. Monitor build activity in the app interface\n');
  }

  console.log(chalk.dim('Configuration: ' + getConfigPath()));
  console.log(chalk.dim('Documentation: https://docs.expo.dev/free-agent/\n'));
}
