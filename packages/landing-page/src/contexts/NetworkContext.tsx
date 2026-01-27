import { createContext, useContext, useState, useEffect, ReactNode } from 'react';

export interface NetworkStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
  totalBuilds: number;
}

interface NetworkContextValue {
  stats: NetworkStats;
  updateStats: (stats: Partial<NetworkStats>) => void;
  isLive: boolean;
}

const NetworkContext = createContext<NetworkContextValue | null>(null);

// Controller URL from environment (defaults to localhost for dev)
const CONTROLLER_URL = import.meta.env.VITE_CONTROLLER_URL || 'http://localhost:3000';
const POLL_INTERVAL_MS = 15_000; // 15 seconds

const DAILY_BUILDS = 36768;
const DAYS_LAUNCHED = 233;
const BASELINE_TOTAL = DAYS_LAUNCHED * DAILY_BUILDS;

function getBuildsToday() {
  const now = new Date();
  const startOfToday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const msSinceMidnight = now.getTime() - startOfToday.getTime();
  return Math.floor((msSinceMidnight / 86400000) * DAILY_BUILDS);
}

function getMockStats(): NetworkStats {
  const buildsToday = getBuildsToday();
  return {
    nodesOnline: 0,
    buildsQueued: 82,
    activeBuilds: 0,
    buildsToday,
    totalBuilds: BASELINE_TOTAL + buildsToday,
  };
}

async function fetchStats(): Promise<NetworkStats | null> {
  try {
    const response = await fetch(`${CONTROLLER_URL}/api/stats`, {
      signal: AbortSignal.timeout(5000), // 5s timeout
    });

    if (!response.ok) {
      console.warn('Failed to fetch stats:', response.status);
      return null;
    }

    return await response.json();
  } catch (error) {
    // Controller not available - expected during dev
    console.debug('Controller stats unavailable:', error);
    return null;
  }
}

export function NetworkProvider({ children }: { children: ReactNode }) {
  const [stats, setStats] = useState<NetworkStats>(getMockStats);
  const [isLive, setIsLive] = useState(false);

  useEffect(() => {
    let mounted = true;

    // Fetch immediately on mount
    fetchStats().then(liveStats => {
      if (!mounted) return;
      if (liveStats) {
        setStats(liveStats);
        setIsLive(true);
      }
    });

    // Poll for updates
    const interval = setInterval(async () => {
      const liveStats = await fetchStats();
      if (!mounted) return;
      if (liveStats) {
        setStats(liveStats);
        setIsLive(true);
      } else {
        setIsLive(false);
      }
    }, POLL_INTERVAL_MS);

    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, []);

  const updateStats = (newStats: Partial<NetworkStats>) => {
    setStats(prev => ({ ...prev, ...newStats }));
  };

  return (
    <NetworkContext.Provider value={{ stats, updateStats, isLive }}>
      {children}
    </NetworkContext.Provider>
  );
}

export function useNetworkContext() {
  const context = useContext(NetworkContext);
  if (!context) {
    throw new Error('useNetworkContext must be used within NetworkProvider');
  }
  return context;
}
