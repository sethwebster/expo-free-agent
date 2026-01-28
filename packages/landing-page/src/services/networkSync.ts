import { MeshNetworkEngine } from './meshNetworkEngine';

// ============================================================================
// TYPES
// ============================================================================

export interface ControllerStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
  totalBuilds: number;
  totalBuildTimeMs: number;
  totalCpuCycles: number;
}

export interface NetworkSyncConfig {
  controllerUrl: string;
  pollIntervalMs: number;
  timeoutMs: number;
}

// ============================================================================
// CONSTANTS
// ============================================================================

const CONTROLLER_URL =
  import.meta.env.VITE_CONTROLLER_URL || 'http://localhost:3000';

const DEFAULT_CONFIG: NetworkSyncConfig = {
  controllerUrl: CONTROLLER_URL,
  pollIntervalMs: 15_000,
  timeoutMs: 5_000,
};

// Mock baseline for builds
const DAILY_BUILDS = 36768;
const DAYS_LAUNCHED = 233;
const BASELINE_TOTAL = DAYS_LAUNCHED * DAILY_BUILDS;

// ============================================================================
// NETWORK SYNC SERVICE
// ============================================================================

export type SyncSubscriber = (stats: ControllerStats, isLive: boolean) => void;

export class NetworkSyncService {
  private config: NetworkSyncConfig;
  private engine: MeshNetworkEngine;
  private pollInterval: ReturnType<typeof setInterval> | null = null;
  private subscribers: Set<SyncSubscriber> = new Set();
  private isRunning = false;
  private lastStats: ControllerStats;
  private isLive = false;

  constructor(engine: MeshNetworkEngine, config: Partial<NetworkSyncConfig> = {}) {
    this.engine = engine;
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.lastStats = this.getMockStats();
  }

  // --------------------------------------------------------------------------
  // MOCK DATA
  // --------------------------------------------------------------------------

  private getBuildsToday(): number {
    const now = new Date();
    const startOfToday = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())
    );
    const msSinceMidnight = now.getTime() - startOfToday.getTime();
    return Math.floor((msSinceMidnight / 86400000) * DAILY_BUILDS);
  }

  private getMockStats(): ControllerStats {
    const buildsToday = this.getBuildsToday();
    const activeNodeCount = this.engine.getActiveNodeCount();

    // Simulate active builds (20-40% of active nodes have builds)
    const mockActiveBuilds = Math.floor(activeNodeCount * (0.2 + Math.random() * 0.2));

    const totalBuilds = BASELINE_TOTAL + buildsToday;
    const AVG_BUILD_TIME_MS = 300_000; // 5 minutes
    const AVG_CPU_PERCENT = 40;

    return {
      nodesOnline: activeNodeCount,
      buildsQueued: 82,
      activeBuilds: mockActiveBuilds,
      buildsToday,
      totalBuilds,
      totalBuildTimeMs: totalBuilds * AVG_BUILD_TIME_MS,
      totalCpuCycles: (totalBuilds * AVG_BUILD_TIME_MS / 1000) * (AVG_CPU_PERCENT / 100),
    };
  }

  // --------------------------------------------------------------------------
  // FETCH
  // --------------------------------------------------------------------------

  private async fetchStats(): Promise<ControllerStats | null> {
    try {
      const response = await fetch(`${this.config.controllerUrl}/api/stats`, {
        signal: AbortSignal.timeout(this.config.timeoutMs),
      });

      if (!response.ok) {
        console.warn('Failed to fetch stats:', response.status);
        return null;
      }

      return await response.json();
    } catch {
      // Controller not available - expected during dev
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // SYNC LOGIC
  // --------------------------------------------------------------------------

  private async poll(): Promise<void> {
    const liveStats = await this.fetchStats();

    if (liveStats) {
      this.isLive = true;
      this.lastStats = liveStats;

      // Sync active builds to glowing nodes
      // In a real implementation, we'd map specific agents to nodes
      // For now, we randomly assign glow to match activeBuilds count
      this.syncGlowingNodes(liveStats.activeBuilds);
    } else {
      this.isLive = false;
      // Use mock stats and sync glowing nodes to match
      const mockStats = this.getMockStats();
      this.lastStats = mockStats;

      // Sync glowing nodes to match mock active builds
      this.syncGlowingNodes(mockStats.activeBuilds);
    }

    this.notifySubscribers();
  }

  private syncGlowingNodes(targetCount: number): void {
    const state = this.engine.getState();
    const activeNodes = state.nodes.filter((n) => n.status === 'active');
    const currentGlowing = state.glowingNodeIds;
    const currentCount = currentGlowing.size;

    if (currentCount < targetCount) {
      // Add more glowing nodes
      const nonGlowing = activeNodes.filter((n) => !currentGlowing.has(n.id));
      const toAdd = Math.min(targetCount - currentCount, nonGlowing.length);

      for (let i = 0; i < toAdd; i++) {
        const randomNode = nonGlowing[Math.floor(Math.random() * nonGlowing.length)];
        if (randomNode) {
          this.engine.setNodeGlowing(randomNode.id, true);
          nonGlowing.splice(nonGlowing.indexOf(randomNode), 1);
        }
      }
    } else if (currentCount > targetCount) {
      // Remove some glowing nodes
      const glowingNodes = activeNodes.filter((n) => currentGlowing.has(n.id));
      const toRemove = currentCount - targetCount;

      for (let i = 0; i < toRemove && glowingNodes.length > 0; i++) {
        const randomNode = glowingNodes[Math.floor(Math.random() * glowingNodes.length)];
        if (randomNode) {
          this.engine.setNodeGlowing(randomNode.id, false);
          glowingNodes.splice(glowingNodes.indexOf(randomNode), 1);
        }
      }
    }
  }

  // --------------------------------------------------------------------------
  // SUBSCRIPTION
  // --------------------------------------------------------------------------

  subscribe(callback: SyncSubscriber): () => void {
    this.subscribers.add(callback);
    // Immediately call with current state
    callback(this.lastStats, this.isLive);
    return () => {
      this.subscribers.delete(callback);
    };
  }

  private notifySubscribers(): void {
    this.subscribers.forEach((callback) => {
      callback(this.lastStats, this.isLive);
    });
  }

  // --------------------------------------------------------------------------
  // LIFECYCLE
  // --------------------------------------------------------------------------

  start(): void {
    if (this.isRunning) return;
    this.isRunning = true;

    // Fetch immediately
    this.poll();

    // Poll periodically
    this.pollInterval = setInterval(() => {
      this.poll();
    }, this.config.pollIntervalMs);
  }

  stop(): void {
    if (!this.isRunning) return;
    this.isRunning = false;

    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  dispose(): void {
    this.stop();
    this.subscribers.clear();
  }

  // --------------------------------------------------------------------------
  // ACCESSORS
  // --------------------------------------------------------------------------

  getStats(): ControllerStats {
    return { ...this.lastStats };
  }

  getIsLive(): boolean {
    return this.isLive;
  }

  // --------------------------------------------------------------------------
  // MANUAL UPDATES (for engine-driven stat updates)
  // --------------------------------------------------------------------------

  updateFromEngine(): void {
    if (!this.isLive) {
      this.lastStats = {
        ...this.lastStats,
        nodesOnline: this.engine.getActiveNodeCount(),
        activeBuilds: this.engine.getGlowingNodeCount(),
      };
      this.notifySubscribers();
    }
  }
}

// ============================================================================
// SINGLETON INSTANCE
// ============================================================================

let syncInstance: NetworkSyncService | null = null;

export function getNetworkSyncService(engine: MeshNetworkEngine): NetworkSyncService {
  if (!syncInstance) {
    syncInstance = new NetworkSyncService(engine);
  }
  return syncInstance;
}

export function disposeNetworkSyncService(): void {
  if (syncInstance) {
    syncInstance.dispose();
    syncInstance = null;
  }
}
