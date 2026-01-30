import { Command } from 'commander';
import { apiClient, APIClient } from '../api-client.js';
import chalk from 'chalk';
import type { DiagnosticReport } from '../types.js';

export function createDoctorCommand(): Command {
  const command = new Command('doctor');

  command
    .description('View worker diagnostic reports')
    .argument('[worker-id]', 'Worker ID to view diagnostics for')
    .option('-l, --latest', 'Show only latest diagnostic report')
    .option('--limit <n>', 'Number of reports to show', '10')
    .option('--api-key <key>', 'API key for authentication')
    .option('--controller-url <url>', 'Controller URL')
    .action(async (workerId?: string, options?: { latest?: boolean; limit?: string; apiKey?: string; controllerUrl?: string }) => {
      try {
        // If no worker ID provided, show error
        if (!workerId) {
          console.error(chalk.red('Error: Worker ID is required'));
          console.log();
          console.log('Usage:');
          console.log(`  ${chalk.cyan('expo-controller doctor <worker-id>')}`);
          console.log(`  ${chalk.cyan('expo-controller doctor <worker-id> --latest')}`);
          console.log(`  ${chalk.cyan('expo-controller doctor <worker-id> --limit 5')}`);
          console.log();
          process.exit(1);
        }

        const client = (options?.apiKey || options?.controllerUrl)
          ? new APIClient(options?.controllerUrl, options?.apiKey)
          : apiClient;

        if (options?.latest) {
          const report = await client.getLatestDiagnostic(workerId);
          displayDiagnosticReport(report);
        } else {
          const limit = parseInt(options?.limit || '10');
          const data = await client.getDiagnostics(workerId, limit);
          displayDiagnosticReports(data.worker_id, data.reports);
        }
      } catch (error) {
        console.error(chalk.red('Failed to get diagnostics'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}

function displayDiagnosticReports(workerId: string, reports: DiagnosticReport[]): void {
  console.log();
  console.log(chalk.bold('Diagnostics for worker:'), chalk.cyan(workerId));
  console.log();

  if (reports.length === 0) {
    console.log(chalk.yellow('No diagnostic reports available'));
    console.log();
    return;
  }

  for (let i = 0; i < reports.length; i++) {
    console.log(chalk.bold(`Report ${i + 1}:`));
    displayDiagnosticReport(reports[i], false);
    if (i < reports.length - 1) {
      console.log(chalk.dim('─'.repeat(60)));
    }
  }

  console.log();
}

function displayDiagnosticReport(report: DiagnosticReport, showHeader = true): void {
  if (showHeader) {
    console.log();
    console.log(chalk.bold('Diagnostic Report'));
    console.log();
  }

  // Overall status
  const statusIcon = getStatusIcon(report.status);
  const statusColor = getStatusColor(report.status);
  console.log(`${statusIcon} Status: ${statusColor}`);
  console.log(`  Run at: ${new Date(report.run_at).toLocaleString()}`);
  console.log(`  Duration: ${report.duration_ms}ms`);
  console.log(`  Auto-fixed: ${report.auto_fixed ? chalk.green('Yes') : 'No'}`);
  console.log();

  // Checks
  console.log(chalk.bold('  Checks:'));
  for (const check of report.checks) {
    const checkIcon = getCheckIcon(check.status);
    const autoFixedLabel = check.auto_fixed ? chalk.dim(' (auto-fixed)') : '';
    console.log(`  ${checkIcon} ${check.name}: ${check.message} ${chalk.dim(`(${check.duration_ms}ms)`)}${autoFixedLabel}`);

    // Show details if available
    if (check.details && Object.keys(check.details).length > 0) {
      for (const [key, value] of Object.entries(check.details)) {
        console.log(chalk.dim(`      ${key}: ${value}`));
      }
    }
  }

  console.log();
}

function getStatusIcon(status: string): string {
  switch (status) {
    case 'healthy':
      return chalk.green('✓');
    case 'warning':
      return chalk.yellow('⚠');
    case 'critical':
      return chalk.red('✗');
    default:
      return '●';
  }
}

function getStatusColor(status: string): string {
  switch (status) {
    case 'healthy':
      return chalk.green(status);
    case 'warning':
      return chalk.yellow(status);
    case 'critical':
      return chalk.red(status);
    default:
      return status;
  }
}

function getCheckIcon(status: string): string {
  switch (status) {
    case 'pass':
      return chalk.green('✓');
    case 'warn':
      return chalk.yellow('⚠');
    case 'fail':
      return chalk.red('✗');
    default:
      return '●';
  }
}
