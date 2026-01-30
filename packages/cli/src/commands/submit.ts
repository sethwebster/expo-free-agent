import { Command } from 'commander';
import archiver from 'archiver';
import fs from 'fs';
import path from 'path';
import os from 'os';
import readline from 'readline';
import { apiClient, APIClient } from '../api-client.js';
import { saveBuildToken } from '../build-tokens.js';
import chalk from 'chalk';
import ora from 'ora';
import { isTTY } from '../types.js';

export function createSubmitCommand(): Command {
  const command = new Command('submit');

  command
    .description('Submit an Expo project for building')
    .argument('<project-path>', 'Path to Expo project directory')
    .option('--cert <path>', 'Path to signing certificate (.p12)')
    .option('--profile <path>', 'Path to provisioning profile (.mobileprovision)')
    .option('--apple-id <email>', 'Apple ID email')
    .option('--api-key <key>', 'API key for authentication')
    .option('--controller-url <url>', 'Controller URL')
    .action(async (projectPath: string, options) => {
      const spinner = ora('Preparing project for submission').start();

      try {
        // Validate project path
        const resolvedPath = path.resolve(projectPath);
        const stats = await fs.promises.stat(resolvedPath);

        if (!stats.isDirectory()) {
          spinner.fail(chalk.red('Project path must be a directory'));
          process.exit(1);
        }

        // Check for app.json, app.config.js, or app.config.ts
        const hasAppJson = await fs.promises
          .access(path.join(resolvedPath, 'app.json'))
          .then(() => true)
          .catch(() => false);
        const hasAppConfigJs = await fs.promises
          .access(path.join(resolvedPath, 'app.config.js'))
          .then(() => true)
          .catch(() => false);
        const hasAppConfigTs = await fs.promises
          .access(path.join(resolvedPath, 'app.config.ts'))
          .then(() => true)
          .catch(() => false);

        if (!hasAppJson && !hasAppConfigJs && !hasAppConfigTs) {
          spinner.fail(chalk.red('Not a valid Expo project (missing app.json, app.config.js, or app.config.ts)'));
          process.exit(1);
        }

        // Create temporary zip file
        spinner.text = 'Zipping project files';
        const tempDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'expo-controller-'));
        const zipPath = path.join(tempDir, 'project.zip');

        await zipDirectory(resolvedPath, zipPath, (fileCount) => {
          spinner.text = `Zipping project files (${fileCount} files)`;
        });

        const zipSize = (await fs.promises.stat(zipPath)).size;
        spinner.succeed(chalk.green(`Project zipped (${formatBytes(zipSize)})`));

        // Validate cert and profile if provided
        if (options.cert) {
          const certPath = path.resolve(options.cert);
          try {
            await fs.promises.access(certPath);
          } catch {
            console.error(chalk.red(`Certificate not found: ${certPath}`));
            process.exit(1);
          }
        }

        if (options.profile) {
          const profilePath = path.resolve(options.profile);
          try {
            await fs.promises.access(profilePath);
          } catch {
            console.error(chalk.red(`Provisioning profile not found: ${profilePath}`));
            process.exit(1);
          }
        }

        // Handle Apple password securely
        let applePassword = process.env.EXPO_APPLE_PASSWORD;

        if (options.appleId && !applePassword) {
          spinner.stop();
          console.log();
          console.log(chalk.yellow('Apple ID provided but EXPO_APPLE_PASSWORD env var not set.'));
          console.log(chalk.dim('You can set it with: export EXPO_APPLE_PASSWORD=your-app-specific-password'));
          console.log();

          applePassword = await promptPassword('Enter Apple app-specific password (or Ctrl+C to cancel): ');

          if (!applePassword) {
            console.error(chalk.red('Apple password required when using --apple-id'));
            process.exit(1);
          }

          // Set env var for this session so api-client can access it
          process.env.EXPO_APPLE_PASSWORD = applePassword;
        }

        // Submit build
        spinner.start('Uploading to controller');

        // Use custom client if --api-key or --controller-url provided
        const client = (options.apiKey || options.controllerUrl)
          ? new APIClient(options.controllerUrl, options.apiKey)
          : apiClient;

        const { buildId, accessToken } = await client.submitBuild({
          projectPath: zipPath,
          certPath: options.cert ? path.resolve(options.cert) : undefined,
          profilePath: options.profile ? path.resolve(options.profile) : undefined,
          appleId: options.appleId,
        });

        // Store build token for future access
        await saveBuildToken(buildId, accessToken);

        spinner.succeed(chalk.green('Build submitted successfully'));

        console.log();
        console.log(chalk.bold('Build ID:'), buildId);
        console.log();
        console.log('Track status:', chalk.cyan(`expo-free-agent status ${buildId}`));
        console.log('Download when ready:', chalk.cyan(`expo-free-agent download ${buildId}`));
        console.log();

        // Cleanup
        await fs.promises.rm(tempDir, { recursive: true, force: true });
      } catch (error) {
        spinner.fail(chalk.red('Build submission failed'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}

async function zipDirectory(
  sourceDir: string,
  outPath: string,
  onProgress?: (fileCount: number) => void
): Promise<void> {
  return new Promise((resolve, reject) => {
    const output = fs.createWriteStream(outPath);
    const archive = archiver('zip', { zlib: { level: 9 } });

    let fileCount = 0;

    output.on('close', () => resolve());
    archive.on('error', (err) => reject(err));

    // Track progress as files are added
    archive.on('entry', () => {
      fileCount++;
      if (onProgress && fileCount % 10 === 0) {
        onProgress(fileCount);
      }
    });

    archive.pipe(output);

    // Add files, excluding common directories
    // Only send: source code, config files, assets, lock files
    // VM will regenerate: node_modules, ios/, android/ via expo prebuild
    archive.glob('**/*', {
      cwd: sourceDir,
      ignore: [
        'node_modules/**',       // Reinstalled via npm ci
        'ios/**',                // Regenerated via expo prebuild
        'android/**',            // Not needed for iOS builds
        '.expo/**',              // Build cache
        '.expo-shared/**',       // Shared cache
        '.git/**',               // Version control
        '.next/**',              // Next.js cache
        '.turbo/**',             // Turborepo cache
        'dist/**',               // Build output
        'build/**',              // Build output
        'coverage/**',           // Test coverage
        '.nyc_output/**',        // Test coverage
        '*.log',                 // Log files
        '.DS_Store',             // macOS junk
        'Thumbs.db',             // Windows junk
      ],
    });

    archive.finalize();
  });
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

async function promptPassword(prompt: string): Promise<string> {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    // Hide input for password
    const stdin = process.stdin;
    if (isTTY(stdin)) {
      stdin.setRawMode(true);
    }

    process.stdout.write(prompt);

    let password = '';

    stdin.on('data', (char) => {
      const str = char.toString();

      if (str === '\n' || str === '\r' || str === '\u0004') {
        // Enter or Ctrl+D
        if (isTTY(stdin)) {
          stdin.setRawMode(false);
        }
        stdin.pause();
        process.stdout.write('\n');
        rl.close();
        resolve(password);
      } else if (str === '\u0003') {
        // Ctrl+C
        process.exit(1);
      } else if (str === '\u007f' || str === '\b') {
        // Backspace
        if (password.length > 0) {
          password = password.slice(0, -1);
          process.stdout.write('\b \b');
        }
      } else {
        password += str;
        process.stdout.write('*');
      }
    });
  });
}
