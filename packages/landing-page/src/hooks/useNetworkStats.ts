import { useState, useEffect, useRef } from 'react';

export interface NetworkStats {
  nodesOnline: number;
  buildsQueued: number;
  activeBuilds: number;
  buildsToday: number;
  totalBuilds: number;
}

const DAILY_BUILDS = 36768;
// "Launched 233 days ago" from the perspective of the math start
// BASELINE_TOTAL is the count at the start of "today"
const DAYS_LAUNCHED = 233;
const BASELINE_TOTAL = DAYS_LAUNCHED * DAILY_BUILDS;

export function useNetworkStats() {
  const [stats, setStats] = useState<NetworkStats>(() => {
    // Calculate initial logic synchronously to avoid hydration mismatch if possible, 
    // or at least have a good starting value.
    const now = new Date();
    const startOfToday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    const msSinceMidnight = now.getTime() - startOfToday.getTime();
    /*
      Math:
      Daily = 36768
      Ms in day = 86400000
      Rate = 36768 / 86400000 approx 0.0004255 builds/ms
    */
    const calculatedBuildsToday = Math.floor((msSinceMidnight / 86400000) * DAILY_BUILDS);

    return {
      nodesOnline: 154,
      buildsQueued: 82,
      activeBuilds: 60,
      buildsToday: calculatedBuildsToday,
      totalBuilds: BASELINE_TOTAL + calculatedBuildsToday,
    };
  });

  // Track next update time for simulated metrics
  const nextUpdates = useRef({
    nodes: 0,
    queue: 0,
    active: 0,
  });

  useEffect(() => {
    const interval = setInterval(() => {
      const now = Date.now();

      // Recalculate deterministic build stats
      const nowDate = new Date(now);
      const startOfToday = new Date(Date.UTC(nowDate.getUTCFullYear(), nowDate.getUTCMonth(), nowDate.getUTCDate()));
      const msSinceMidnight = now - startOfToday.getTime();
      const targetBuildsToday = Math.floor((msSinceMidnight / 86400000) * DAILY_BUILDS);
      const targetTotalBuilds = BASELINE_TOTAL + targetBuildsToday;

      setStats(prev => {
        let next = { ...prev };
        let changed = false;

        // Sync build counts if they changed
        if (next.buildsToday !== targetBuildsToday) {
          next.buildsToday = targetBuildsToday;
          next.totalBuilds = targetTotalBuilds;
          changed = true;
        }

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

        return changed ? next : prev;
      });
    }, 100);

    return () => clearInterval(interval);
  }, []);

  return stats;
}
