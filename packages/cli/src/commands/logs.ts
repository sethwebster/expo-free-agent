import { Command } from 'commander';
import { apiClient } from '../api-client.js';
import chalk from 'chalk';
import type { LogEntry, LogsCommandOptions } from '../types.js';

export function createLogsCommand(): Command {
  const command = new Command('logs');

  command
    .description('View build logs')
    .argument('<build-id>', 'Build ID to get logs for')
    .option('--api-key <key>', 'API key for authentication')
    .option('--controller-url <url>', 'Controller URL')
    .option('-f, --follow', 'Follow logs in real-time (poll for updates)')
    .option('-w, --watch', 'Watch logs in real-time (alias for --follow)')
    .option('-t, --tail', 'Tail logs in real-time (alias for --follow)')
    .option('--interval <ms>', 'Poll interval in milliseconds (default: 2000)', '2000')
    .action(async (buildId: string, options) => {
      try {
        if (options.follow || options.watch || options.tail) {
          await followLogs(buildId, options);
        } else {
          await showLogs(buildId, options);
        }
      } catch (error) {
        console.error(chalk.red('Failed to get logs:'), error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
    });

  return command;
}

async function showLogs(buildId: string, options: LogsCommandOptions): Promise<void> {
  const baseUrl = options.controllerUrl || await apiClient.init().then(() => apiClient.getBaseUrl());
  const response = await fetch(
    `${baseUrl}/api/builds/${buildId}/logs`,
    {
      headers: await getHeaders(buildId, options),
    }
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Failed to get logs: ${error}`);
  }

  const data = await response.json() as { logs: LogEntry[] };
  displayLogs(data.logs);
}

async function followLogs(buildId: string, options: LogsCommandOptions): Promise<void> {
  const interval = parseInt(options.interval || '2000');
  let lastLogCount = 0;

  console.log(chalk.bold('Following logs for build:'), buildId);
  console.log(chalk.dim('Press Ctrl+C to stop\n'));

  // Show initial logs
  await showLogs(buildId, options);

  // Poll for new logs
  const pollInterval = setInterval(async () => {
    try {
      const baseUrl = options.controllerUrl || await apiClient.init().then(() => apiClient.getBaseUrl());
      const response = await fetch(
        `${baseUrl}/api/builds/${buildId}/logs`,
        {
          headers: await getHeaders(buildId, options),
        }
      );

      if (!response.ok) {
        clearInterval(pollInterval);
        throw new Error('Failed to get logs');
      }

      const data = await response.json() as { logs: LogEntry[] };

      // Only show new logs
      if (data.logs.length > lastLogCount) {
        const newLogs = data.logs.slice(lastLogCount);
        displayLogs(newLogs, false);
        lastLogCount = data.logs.length;
      }

      // Check if build is complete
      const statusUrl = options.controllerUrl || await apiClient.init().then(() => apiClient.getBaseUrl());
      const statusResponse = await fetch(
        `${statusUrl}/api/builds/${buildId}/status`,
        {
          headers: await getHeaders(buildId, options),
        }
      );

      if (statusResponse.ok) {
        const status = await statusResponse.json() as { status: string };
        if (status.status === 'completed' || status.status === 'failed') {
          clearInterval(pollInterval);
          console.log();
          console.log(chalk.bold('Build finished:'), status.status === 'completed' ? chalk.green('completed') : chalk.red('failed'));
          process.exit(0);
        }
      }
    } catch (error) {
      clearInterval(pollInterval);
      console.error(chalk.red('Error polling logs:'), error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  }, interval);
}

async function getHeaders(buildId: string, options: LogsCommandOptions): Promise<Record<string, string>> {
  const headers: Record<string, string> = {};

  // Try build token first (most specific - build-level access)
  const { getBuildToken } = await import('../build-tokens.js');
  const token = await getBuildToken(buildId);
  if (token) {
    headers['X-Build-Token'] = token;
    return headers;
  }

  // Fallback to API key from options
  if (options.apiKey) {
    headers['X-API-Key'] = options.apiKey;
    return headers;
  }

  // Try environment variable
  const envKey = process.env.EXPO_CONTROLLER_API_KEY;
  if (envKey) {
    headers['X-API-Key'] = envKey;
    return headers;
  }

  // Try config file
  const { getApiKey } = await import('../config.js');
  const configKey = await getApiKey();
  if (configKey) {
    headers['X-API-Key'] = configKey;
    return headers;
  }

  return headers;
}

function displayLogs(logs: LogEntry[], showHeader: boolean = true): void {
  if (showHeader && logs.length === 0) {
    console.log(chalk.dim('No logs yet'));
    return;
  }

  for (const log of logs) {
    const timestamp = new Date(log.timestamp).toLocaleTimeString();
    let levelColor = chalk.white;
    let levelSymbol = '●';

    switch (log.level) {
      case 'error':
        levelColor = chalk.red;
        levelSymbol = '✖';
        break;
      case 'warn':
        levelColor = chalk.yellow;
        levelSymbol = '⚠';
        break;
      case 'info':
        levelColor = chalk.blue;
        levelSymbol = '●';
        break;
    }

    console.log(
      chalk.dim(timestamp),
      levelColor(levelSymbol),
      log.message
    );
  }
}
