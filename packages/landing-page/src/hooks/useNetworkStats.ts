import { useState, useEffect } from 'react';

export interface NetworkStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
}

export function useNetworkStats() {
  const [stats, setStats] = useState<NetworkStats>({
    nodesOnline: 124,
    buildsQueued: 0,
    activeBuilds: 3,
    buildsToday: 1402,
  });

  useEffect(() => {
    // Simulate live data changes
    const interval = setInterval(() => {
      setStats(prev => {
        const change = Math.random() > 0.7; // Only change sometimes
        if (!change) return prev;

        const newActive = Math.max(0, prev.activeBuilds + (Math.random() > 0.5 ? 1 : -1));
        const newQueued = Math.max(0, prev.buildsQueued + (Math.random() > 0.8 ? 1 : -1));
        const newToday = prev.buildsToday + (Math.random() > 0.9 ? 1 : 0);
        
        // Occasionally fluctuate nodes
        const newNodes = prev.nodesOnline + (Math.random() > 0.95 ? (Math.random() > 0.5 ? 1 : -1) : 0);

        return {
          nodesOnline: newNodes,
          buildsQueued: newQueued,
          activeBuilds: newActive,
          buildsToday: newToday,
        };
      });
    }, 2000);

    return () => clearInterval(interval);
  }, []);

  return stats;
}
