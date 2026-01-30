import prompts from 'prompts';
import chalk from 'chalk';
import { loadConfiguration } from '../config.js';
import type { InstallOptions } from '../types.js';

const DEFAULT_CONTROLLER_URL = 'https://expo-free-agent-controller.projects.sethwebster.com';

export async function promptForConfiguration(
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
