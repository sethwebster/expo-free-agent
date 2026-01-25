#!/usr/bin/env bun
import { spawn } from 'child_process';
import { promisify } from 'util';
import { exec } from 'child_process';

const execAsync = promisify(exec);

function showHelp() {
  console.log(`
Expo Free Agent Controller - CapRover Deployment Script

Usage:
  bun run deploy              # Interactive deployment (prompts for app)
  bun run deploy:app <name>   # Deploy to specific app
  bun run scripts/deploy.ts -a <name>  # Deploy to specific app

Options:
  -a, --app <name>   Specify the app name to deploy to
  -h, --help         Show this help message

Examples:
  bun run deploy                        # Interactive
  bun run deploy:app expo-controller    # Deploy to expo-controller
  bun run scripts/deploy.ts -a my-app   # Deploy to my-app

Before deploying:
  1. Install CapRover CLI: npm install -g caprover
  2. Login: caprover login
  3. Create app in CapRover dashboard
  4. Configure environment variables (see DEPLOYMENT.md)
`);
}

async function checkCaproverInstalled(): Promise<boolean> {
  try {
    await execAsync('which caprover');
    return true;
  } catch {
    return false;
  }
}

async function createTarFile(): Promise<string> {
  const tarFile = './deploy.tar';

  console.log('📦 Creating deployment archive...');

  // Create tar file excluding node_modules, .git, etc.
  try {
    await execAsync(
      `tar -czf ${tarFile} \
        --exclude=node_modules \
        --exclude=.git \
        --exclude=dist \
        --exclude=*.tar \
        --exclude=*.tar.gz \
        .`
    );
    console.log('✓ Archive created\n');
    return tarFile;
  } catch (error) {
    throw new Error(`Failed to create tar file: ${error}`);
  }
}

async function cleanupTarFile(tarFile: string) {
  try {
    await execAsync(`rm -f ${tarFile}`);
  } catch {
    // Ignore cleanup errors
  }
}

async function deploy(appName?: string) {
  console.log('🚀 Deploying to CapRover...\n');

  // Check if caprover CLI is installed
  const isInstalled = await checkCaproverInstalled();
  if (!isInstalled) {
    console.error('❌ CapRover CLI not found!');
    console.error('Install it with: npm install -g caprover');
    process.exit(1);
  }

  let tarFile: string | null = null;

  try {
    // Create tar file for deployment
    tarFile = await createTarFile();

    // Build args for caprover deploy
    const args = ['deploy', '-t', tarFile];

    if (appName) {
      args.push('-a', appName);
    }

    console.log(`Running: caprover ${args.join(' ')}\n`);

    // Run caprover deploy
    const deployProcess = spawn('caprover', args, {
      stdio: 'inherit',
      shell: true,
    });

    deployProcess.on('close', async (code) => {
      // Cleanup tar file
      if (tarFile) {
        await cleanupTarFile(tarFile);
      }

      if (code === 0) {
        console.log('\n✅ Deployment successful!');
        console.log('\nNext steps:');
        console.log('1. Verify deployment in CapRover dashboard');
        console.log('2. Check app logs: caprover logs -a <app-name>');
        console.log('3. Test API endpoint');
      } else {
        console.error(`\n❌ Deployment failed with code ${code}`);
        process.exit(code || 1);
      }
    });

    deployProcess.on('error', async (error) => {
      // Cleanup tar file
      if (tarFile) {
        await cleanupTarFile(tarFile);
      }
      console.error('❌ Failed to start deployment:', error.message);
      process.exit(1);
    });
  } catch (error) {
    // Cleanup tar file on error
    if (tarFile) {
      await cleanupTarFile(tarFile);
    }
    throw error;
  }
}

// Parse command line args
const args = process.argv.slice(2);

// Check for help flag
if (args.includes('-h') || args.includes('--help')) {
  showHelp();
  process.exit(0);
}

const appNameIndex = args.indexOf('-a') !== -1 ? args.indexOf('-a') : args.indexOf('--app');
const appName = appNameIndex !== -1 ? args[appNameIndex + 1] : undefined;

// Run deployment
deploy(appName).catch((error) => {
  console.error('❌ Deployment error:', error);
  process.exit(1);
});
