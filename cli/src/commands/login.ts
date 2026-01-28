import { Command } from 'commander';
import chalk from 'chalk';
import http from 'http';
import { URL } from 'url';
import getPort from 'get-port';
import open from 'open';
import { saveConfig, getAuthBaseUrl } from '../config.js';

export function createLoginCommand(): Command {
  const command = new Command('login');

  command
    .description('Authenticate with Expo Free Agent')
    .option('--no-browser', 'Print login URL instead of opening browser')
    .action(async (options) => {
      try {
        await loginCommand(options);
      } catch (error) {
        console.error(chalk.red('Authentication failed'));
        console.error(chalk.red(error instanceof Error ? error.message : String(error)));
        process.exit(1);
      }
    });

  return command;
}

async function loginCommand(options: { browser: boolean }): Promise<void> {
  const port = await getPort();
  const callbackUrl = `http://localhost:${port}/auth/callback`;
  const authBaseUrl = getAuthBaseUrl();
  const loginUrl = `${authBaseUrl}/#/cli/login?callback=${encodeURIComponent(callbackUrl)}`;

  // Create promise to handle authentication result
  let resolveAuth: (apiKey: string) => void;
  let rejectAuth: (error: Error) => void;
  const authPromise = new Promise<string>((resolve, reject) => {
    resolveAuth = resolve;
    rejectAuth = reject;
  });

  // Create HTTP server for callback
  const server = http.createServer((req, res) => {
    if (!req.url) {
      res.writeHead(400, { 'Content-Type': 'text/plain' });
      res.end('Bad Request');
      return;
    }

    const url = new URL(req.url, `http://localhost:${port}`);

    if (url.pathname === '/auth/callback') {
      // Validate callback host (security check)
      const host = url.hostname;
      if (host !== 'localhost' && host !== '127.0.0.1') {
        res.writeHead(403, { 'Content-Type': 'text/plain' });
        res.end('Forbidden: Invalid callback host');
        rejectAuth(new Error('Invalid callback host'));
        return;
      }

      const token = url.searchParams.get('token');
      if (!token) {
        res.writeHead(400, { 'Content-Type': 'text/html' });
        res.end('<h1>Error</h1><p>Missing authentication token.</p>');
        rejectAuth(new Error('Missing authentication token'));
        return;
      }

      try {
        // Decode base64 token
        const apiKey = Buffer.from(token, 'base64').toString('utf-8');

        // Send success response
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`
          <!DOCTYPE html>
          <html>
            <head>
              <meta charset="utf-8">
              <title>Authentication Successful</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                  display: flex;
                  justify-content: center;
                  align-items: center;
                  min-height: 100vh;
                  margin: 0;
                  background: #f5f5f5;
                }
                .container {
                  text-align: center;
                  padding: 2rem;
                  background: white;
                  border-radius: 8px;
                  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
                }
                h1 {
                  color: #000091;
                  margin: 0 0 1rem 0;
                }
                p {
                  color: #666;
                  margin: 0;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>All set!</h1>
                <p>You can close this window.</p>
              </div>
            </body>
          </html>
        `);

        resolveAuth(apiKey);
      } catch (error) {
        res.writeHead(400, { 'Content-Type': 'text/html' });
        res.end('<h1>Error</h1><p>Invalid authentication token.</p>');
        rejectAuth(new Error('Invalid authentication token'));
      }
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    }
  });

  // Start server
  server.listen(port);

  // Set timeout for authentication (30 seconds)
  const timeout = setTimeout(() => {
    server.close();
    rejectAuth(new Error('Authentication timeout. Please try again.'));
  }, 30000);

  try {
    // Open browser or print URL
    if (options.browser) {
      console.log('Opening browser for authentication...');
      await open(loginUrl);
    } else {
      console.log('Open this URL in your browser to log in:');
      console.log(chalk.cyan(loginUrl));
    }

    console.log('Waiting for authentication...');

    // Wait for authentication
    const apiKey = await authPromise;

    // Clear timeout
    clearTimeout(timeout);

    // Save API key to config
    await saveConfig({ apiKey });

    console.log(chalk.green('✓ Successfully authenticated!'));
  } catch (error) {
    throw error;
  } finally {
    server.close();
  }
}
