import { hostname } from 'os';
import type { WorkerCapabilities, WorkerConfiguration, RegistrationResponse } from './types.js';

export async function registerWorker(
  controllerURL: string,
  apiKey: string,
  capabilities: WorkerCapabilities
): Promise<RegistrationResponse> {
  const workerName = hostname();

  const payload = {
    name: workerName,
    capabilities,
    apiKey
  };

  try {
    const response = await fetch(`${controllerURL}/api/workers/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Registration failed (${response.status}): ${errorText}`);
    }

    const data = await response.json();

    return {
      workerID: data.workerID || data.id || 'unknown',
      message: data.message || 'Worker registered successfully'
    };
  } catch (error) {
    if (error instanceof Error) {
      throw new Error(`Failed to register worker: ${error.message}`);
    }
    throw error;
  }
}

export async function testConnection(controllerURL: string): Promise<boolean> {
  try {
    const response = await fetch(`${controllerURL}/api/health`, {
      method: 'GET',
      signal: AbortSignal.timeout(5000)
    });

    return response.ok;
  } catch {
    return false;
  }
}

export function createConfiguration(
  controllerURL: string,
  apiKey: string,
  workerID: string,
  deviceName: string
): WorkerConfiguration {
  return {
    controllerURL,
    apiKey,
    workerID,
    deviceName,
    pollIntervalSeconds: 30,
    maxCPUPercent: 70,
    maxMemoryGB: 8,
    maxConcurrentBuilds: 1,
    vmDiskSizeGB: 50,
    reuseVMs: false,
    cleanupAfterBuild: true,
    autoStart: true,
    onlyWhenIdle: false,
    buildTimeoutMinutes: 120
  };
}
