#!/usr/bin/env node
import { Command } from 'commander';
import { createStartCommand } from './commands/start.js';
import { createSubmitCommand } from './commands/submit.js';
import { createStatusCommand } from './commands/status.js';
import { createDownloadCommand } from './commands/download.js';
import { createListCommand } from './commands/list.js';
import { createConfigCommand } from './commands/config.js';
import { createCancelCommand } from './commands/cancel.js';
import { createDoctorCommand } from './commands/doctor.js';
import { createWorkerCommand } from './commands/worker.js';
import { createLoginCommand } from './commands/login.js';
import { createLogsCommand } from './commands/logs.js';
import { createRetryCommand } from './commands/retry.js';

const program = new Command();

program
  .name('expo-free-agent')
  .description('CLI for Expo Free Agent distributed build system')
  .version('0.1.23');

program.addCommand(createLoginCommand());
program.addCommand(createStartCommand());
program.addCommand(createWorkerCommand());
program.addCommand(createSubmitCommand());
program.addCommand(createStatusCommand());
program.addCommand(createLogsCommand());
program.addCommand(createDownloadCommand());
program.addCommand(createListCommand());
program.addCommand(createCancelCommand());
program.addCommand(createRetryCommand());
program.addCommand(createConfigCommand());
program.addCommand(createDoctorCommand());

program.parse();
