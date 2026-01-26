import { useState, useEffect } from 'react';

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

  useEffect(() => {
    // Simulate live data changes with a faster tick for dynamic feel
    const interval = setInterval(() => {
      setStats(prev => {
        // 1. Slowly increase nodes online (trend upwards)
        // Fluctuate between 150 and 300
        const currentNodes = prev.nodesOnline;
        let nodeChange = 0;

        // Strong push back if out of bounds
        if (currentNodes < 150) nodeChange = 1;
        else if (currentNodes > 300) nodeChange = -1;
        else {
          // Random drift
          const r = Math.random();
          if (r > 0.6) nodeChange = 1;
          else if (r < 0.4) nodeChange = -1;
        }

        const newNodes = Math.max(10, currentNodes + nodeChange);

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
        const finalQueued = Math.max(0, Math.floor(newQueued));
        const finalNodes = Math.floor(newNodes);
        const finalActive = Math.floor(newActive);


        // 4. Builds completed today
        // Every active build has a small chance of finishing *right now*
        const completions = Math.random() < (finalActive * 0.05) ? 1 : 0;
        const newToday = prev.buildsToday + completions;
        const newTotal = prev.totalBuilds + completions;

        return {
          nodesOnline: finalNodes,
          buildsQueued: finalQueued,
          activeBuilds: finalActive,
          buildsToday: newToday,
          totalBuilds: newTotal,
        };
      });
    }, 800); // 800ms tick for "alive" feeling

    return () => clearInterval(interval);
  }, []);

  return stats;
}
