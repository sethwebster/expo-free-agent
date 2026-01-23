#!/usr/bin/env node
import { Command } from 'commander';
import { createSubmitCommand } from './commands/submit.js';
import { createStatusCommand } from './commands/status.js';
import { createDownloadCommand } from './commands/download.js';
import { createListCommand } from './commands/list.js';
import { createConfigCommand } from './commands/config.js';

const program = new Command();

program
  .name('expo-controller')
  .description('CLI for Expo Free Agent distributed build system')
  .version('0.1.0');

program.addCommand(createSubmitCommand());
program.addCommand(createStatusCommand());
program.addCommand(createDownloadCommand());
program.addCommand(createListCommand());
program.addCommand(createConfigCommand());

program.parse();
