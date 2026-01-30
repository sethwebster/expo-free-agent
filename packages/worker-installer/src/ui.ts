import chalk from 'chalk';
import type { runPreflightChecks } from './preflight.js';

export function displayBanner(): void {
  console.log(chalk.bold.cyan('\nExpo Free Agent Worker Installer'));
  console.log(chalk.gray('=====================================\n'));
}

export function displayPreflightResults(results: ReturnType<typeof runPreflightChecks>): boolean {
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
