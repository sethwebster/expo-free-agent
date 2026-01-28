import { createContext, useContext, ReactNode } from 'react';
import { useNetworkStats } from '../hooks/useNetworkStatsFromSync';

export interface NetworkStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
  totalBuilds: number;
  totalBuildTimeMs: number;
  totalCpuCycles: number;
}

interface NetworkContextValue {
  stats: NetworkStats;
  updateStats: (stats: Partial<NetworkStats>) => void;
  isLive: boolean;
}

const NetworkContext = createContext<NetworkContextValue | null>(null);

export function NetworkProvider({ children }: { children: ReactNode }) {
  const { stats, isLive, updateStats } = useNetworkStats();

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
