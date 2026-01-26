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
    buildsQueued: 82, // Start high
    activeBuilds: 60,
    buildsToday: 1402,
  });

  useEffect(() => {
    // Simulate live data changes with a faster tick for dynamic feel
    const interval = setInterval(() => {
      setStats(prev => {
        // 1. Slowly increase nodes online (trend upwards)
        // 90% chance to stay same, 7% chance to +1, 3% chance to -1
        const nodeRandom = Math.random();
        let nodeChange = 0;
        if (nodeRandom > 0.93) nodeChange = 1;      // Grow
        else if (nodeRandom > 0.90) nodeChange = -1; // Churn

        const newNodes = Math.max(100, prev.nodesOnline + nodeChange);

        // 2. Active builds is a function of nodes (~50% utilization + variation)
        // Utilization fluctuates between 45% and 55%
        const utilization = 0.45 + (Math.random() * 0.10);
        const targetActive = Math.floor(newNodes * utilization);

        // Smoothly move current active towards target (active doesn't jump instantly)
        // Move by 1-3 units towards target
        let newActive = prev.activeBuilds;
        if (newActive < targetActive) newActive += Math.floor(Math.random() * 3);
        if (newActive > targetActive) newActive -= Math.floor(Math.random() * 2); // Drops slower than it rises

        // 3. Queue logic:
        // As nodes increase (more capacity), queue should decrease
        // But random bursts of jobs come in.

        // Base queue "pressure" that lowers as nodes rise
        // If we have 124 nodes -> 80 queue.
        // If we have 200 nodes -> 20 queue.
        const idealQueueFromCapacity = Math.max(10, 80 - ((newNodes - 124) * 0.8));

        // Add noise/burstiness
        const noise = Math.floor((Math.random() * 20) - 10);
        let targetQueue = idealQueueFromCapacity + noise;

        // Move queued towards target
        let newQueued = prev.buildsQueued;
        if (newQueued < targetQueue) newQueued += 1;
        if (newQueued > targetQueue) newQueued -= 1;

        // Ensure bounds
        newQueued = Math.max(0, Math.floor(newQueued));
        newNodes = Math.floor(newNodes);
        newActive = Math.floor(newActive);


        // 4. Builds completed today
        // Every active build has a small chance of finishing *right now*
        // e.g. 5% chance per active build per tick? 
        // Simpler: Just increment based on purely probability weighted by active count
        const completions = Math.random() < (newActive * 0.05) ? 1 : 0;
        const newToday = prev.buildsToday + completions;

        return {
          nodesOnline: newNodes,
          buildsQueued: newQueued,
          activeBuilds: newActive,
          buildsToday: newToday,
        };
      });
    }, 800); // 800ms tick for "alive" feeling

    return () => clearInterval(interval);
  }, []);

  return stats;
}
