import { Command } from 'commander';
import chalk from 'chalk';
import path from 'path';
import {
  getCachedCertificate,
  clearCertificateCache,
  listIOSCertificates,
} from '../certificates.js';

export function createCertificatesCommand(): Command {
  const command = new Command('certificates');

  command
    .description('Manage iOS signing certificates')
    .addCommand(createResetCommand())
    .addCommand(createShowCommand())
    .addCommand(createListCommand());

  return command;
}

function createResetCommand(): Command {
  const command = new Command('reset');

  command
    .description('Clear cached certificate for current project')
    .argument('[project-path]', 'Path to project directory (defaults to current directory)', '.')
    .action(async (projectPath: string) => {
      try {
        const resolvedPath = path.resolve(projectPath);

        const wasCleared = clearCertificateCache(resolvedPath);

        if (wasCleared) {
          console.log(chalk.green('✓'), 'Certificate cache cleared for:', chalk.dim(resolvedPath));
          console.log();
          console.log('Next build submission will prompt you to select a certificate.');
        } else {
          console.log(chalk.yellow('⚠'), 'No cached certificate found for:', chalk.dim(resolvedPath));
        }
      } catch (error) {
        console.error(chalk.red('Failed to clear certificate cache'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}

function createShowCommand(): Command {
  const command = new Command('show');

  command
    .description('Show cached certificate for current project')
    .argument('[project-path]', 'Path to project directory (defaults to current directory)', '.')
    .action(async (projectPath: string) => {
      try {
        const resolvedPath = path.resolve(projectPath);

        const cached = getCachedCertificate(resolvedPath);

        if (cached) {
          console.log();
          console.log(chalk.bold('Cached Certificate:'));
          console.log();
          console.log('  Name:', chalk.cyan(cached.certificateName));
          console.log('  Hash:', chalk.dim(cached.certificateHash));
          console.log('  Cached at:', chalk.dim(new Date(cached.cachedAt).toLocaleString()));
          console.log('  Project:', chalk.dim(cached.projectPath));
          console.log();
          console.log(chalk.dim('To change certificate, run:'), chalk.cyan('expo-free-agent certificates reset'));
        } else {
          console.log(chalk.yellow('⚠'), 'No cached certificate found for:', chalk.dim(resolvedPath));
          console.log();
          console.log(chalk.dim('Next build submission will prompt you to select a certificate.'));
        }
      } catch (error) {
        console.error(chalk.red('Failed to show cached certificate'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}

function createListCommand(): Command {
  const command = new Command('list');

  command
    .description('List all iOS signing certificates in keychain')
    .action(async () => {
      try {
        const certs = listIOSCertificates();

        if (certs.length === 0) {
          console.log(chalk.yellow('⚠'), 'No iOS signing certificates found in keychain');
          console.log();
          console.log(chalk.dim('To add certificates, use Xcode or the Keychain Access app.'));
          return;
        }

        console.log();
        console.log(chalk.bold(`Found ${certs.length} iOS signing certificate(s):`));
        console.log();

        certs.forEach((cert, index) => {
          console.log(chalk.dim(`  ${index + 1})`), cert.displayName);
        });

        console.log();
      } catch (error) {
        console.error(chalk.red('Failed to list certificates'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}
