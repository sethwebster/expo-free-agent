import { useState, useEffect, useCallback, useRef } from 'react';
import type { ControllerStats } from '../services/networkSync';

// ============================================================================
// TYPES
// ============================================================================

export interface NetworkStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
  totalBuilds: number;
  totalBuildTimeMs: number;
  totalCpuCycles: number;
}

// ============================================================================
// CONSTANTS (for fallback mock data)
// ============================================================================

const DAILY_BUILDS = 36768;
const DAYS_LAUNCHED = 233;
const BASELINE_TOTAL = DAYS_LAUNCHED * DAILY_BUILDS;

const CONTROLLER_URL =
  import.meta.env.VITE_CONTROLLER_URL || 'http://localhost:3000';
const POLL_INTERVAL_MS = 15_000;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function getBuildsToday(): number {
  const now = new Date();
  const startOfToday = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())
  );
  const msSinceMidnight = now.getTime() - startOfToday.getTime();
  return Math.floor((msSinceMidnight / 86400000) * DAILY_BUILDS);
}

function getMockStats(): NetworkStats {
  const buildsToday = getBuildsToday();
  const totalBuilds = BASELINE_TOTAL + buildsToday;
  const AVG_BUILD_TIME_MS = 300_000; // 5 minutes
  const AVG_CPU_PERCENT = 40;
  return {
    nodesOnline: 0,
    buildsQueued: 82,
    activeBuilds: 0,
    buildsToday,
    totalBuilds,
    totalBuildTimeMs: totalBuilds * AVG_BUILD_TIME_MS,
    totalCpuCycles: (totalBuilds * AVG_BUILD_TIME_MS / 1000) * (AVG_CPU_PERCENT / 100),
  };
}

async function fetchStats(): Promise<ControllerStats | null> {
  try {
    const response = await fetch(`${CONTROLLER_URL}/api/stats`, {
      signal: AbortSignal.timeout(5000),
    });

    if (!response.ok) {
      console.warn('Failed to fetch stats:', response.status);
      return null;
    }

    return await response.json();
  } catch {
    return null;
  }
}

// ============================================================================
// HOOK: useNetworkStats
// ============================================================================

/**
 * Hook to get network stats, either from the controller or mock data.
 * This is a standalone hook that doesn't depend on the engine context,
 * making it safe to use in the NetworkProvider which wraps the engine.
 */
export function useNetworkStats(): {
  stats: NetworkStats;
  isLive: boolean;
  updateStats: (partial: Partial<NetworkStats>) => void;
} {
  const [stats, setStats] = useState<NetworkStats>(getMockStats);
  const [isLive, setIsLive] = useState(false);
  const mountedRef = useRef(true);

  // Poll for controller stats
  useEffect(() => {
    mountedRef.current = true;

    const poll = async () => {
      const liveStats = await fetchStats();
      if (!mountedRef.current) return;

      if (liveStats) {
        setStats(liveStats);
        setIsLive(true);
      } else {
        setIsLive(false);
        // Update mock stats time-based values
        setStats((prev) => {
          const buildsToday = getBuildsToday();
          if (prev.buildsToday !== buildsToday) {
            const totalBuilds = BASELINE_TOTAL + buildsToday;
            const AVG_BUILD_TIME_MS = 300_000;
            const AVG_CPU_PERCENT = 40;
            return {
              ...prev,
              buildsToday,
              totalBuilds,
              totalBuildTimeMs: totalBuilds * AVG_BUILD_TIME_MS,
              totalCpuCycles: (totalBuilds * AVG_BUILD_TIME_MS / 1000) * (AVG_CPU_PERCENT / 100),
            };
          }
          return prev;
        });
      }
    };

    // Fetch immediately
    poll();

    // Poll periodically
    const interval = setInterval(poll, POLL_INTERVAL_MS);

    return () => {
      mountedRef.current = false;
      clearInterval(interval);
    };
  }, []);

  // Manual update (for engine-driven updates)
  const updateStats = useCallback((partial: Partial<NetworkStats>) => {
    setStats((prev) => ({ ...prev, ...partial }));
  }, []);

  return { stats, isLive, updateStats };
}

// ============================================================================
// HOOK: useNetworkStatsWithEngine
// ============================================================================

/**
 * Hook that syncs network stats with the engine state.
 * Use this inside components that are within NetworkEngineProvider.
 */
export function useNetworkStatsWithEngine(): {
  stats: NetworkStats;
  isLive: boolean;
} {
  // This hook can optionally sync with the engine if needed
  // For now, it just returns the base stats
  const { stats, isLive } = useNetworkStats();
  return { stats, isLive };
}
