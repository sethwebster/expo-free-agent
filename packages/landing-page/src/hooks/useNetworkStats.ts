import { useState, useEffect, useRef } from 'react';

export interface NetworkStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
  totalBuilds: number;
}

export function useNetworkStats() {
  const [stats, setStats] = useState<NetworkStats>({
    nodesOnline: 154,
    buildsQueued: 82, // Start high
    activeBuilds: 60,
    buildsToday: 1402,
    totalBuilds: 8439021, // ~8.4M lifetime
  });

  // Track next update time for each metric independently
  const nextUpdates = useRef({
    nodes: 0,
    queue: 0,
    active: 0,
    builds: 0
  });

  useEffect(() => {
    const interval = setInterval(() => {
      const now = Date.now();

      setStats(prev => {
        let next = { ...prev };
        let changed = false;

        // 1. Nodes Online (Updates slowly: 800ms - 2000ms)
        if (now > nextUpdates.current.nodes) {
          const currentNodes = prev.nodesOnline;
          let nodeChange = 0;
          if (currentNodes < 150) nodeChange = 1;
          else if (currentNodes > 300) nodeChange = -1;
          else {
            const r = Math.random();
            if (r > 0.6) nodeChange = 1;
            else if (r < 0.4) nodeChange = -1;
          }
          next.nodesOnline = Math.max(10, currentNodes + nodeChange);
          nextUpdates.current.nodes = now + 800 + (Math.random() * 1200);
          changed = true;
        }

        // 2. Active Builds (Updates medium: 400ms - 1000ms)
        // Dependent on nodes, so usually follows node trend but with jitter
        if (now > nextUpdates.current.active) {
          const utilization = 0.45 + (Math.random() * 0.15);
          const targetActive = Math.floor(next.nodesOnline * utilization);

          let newActive = prev.activeBuilds;
          if (newActive < targetActive) newActive += 1;
          if (newActive > targetActive) newActive -= 1;

          next.activeBuilds = newActive;
          nextUpdates.current.active = now + 400 + (Math.random() * 600);
          changed = true;
        }

        // 3. Queue (Updates quickly: 200ms - 600ms)
        if (now > nextUpdates.current.queue) {
          const idealQueue = Math.max(10, 100 - (next.nodesOnline * 0.3));
          const noise = Math.floor((Math.random() * 20) - 10);
          const targetQueue = idealQueue + noise;

          let newQueued = prev.buildsQueued;
          if (newQueued < targetQueue) newQueued += 1;
          if (newQueued > targetQueue) newQueued -= 1;

          next.buildsQueued = Math.max(0, newQueued);
          nextUpdates.current.queue = now + 200 + (Math.random() * 400);
          changed = true;
        }

        // 4. Completions (Updates randomly: 100ms - 8000ms based on probability)
        if (now > nextUpdates.current.builds) {
          // Chance to finish a build
          // Higher active builds = more frequent completions
          const chance = Math.max(0.1, next.activeBuilds / 500);
          if (Math.random() < chance) {
            next.buildsToday += 1;
            next.totalBuilds += 1;
            changed = true;
            // If we finished one, maybe finish another soon?
            nextUpdates.current.builds = now + 100 + (Math.random() * 500);
          } else {
            // Check again soon
            nextUpdates.current.builds = now + 100;
          }
        }

        return changed ? next : prev;
      });
    }, 100); // 100ms tick to check for updates

    return () => clearInterval(interval);
  }, []);

  return stats;
}
