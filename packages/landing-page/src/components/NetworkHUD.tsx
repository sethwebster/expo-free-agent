import { useNetwork } from "../context/NetworkContext";

export function NetworkHUD() {
  const stats = useNetwork();

  return (
    <div className="flex flex-col items-center">
      <div className="mt-16 sm:mt-24 p-1 rounded-2xl bg-zinc-50/50 dark:bg-zinc-900/50 backdrop-blur-md border border-zinc-200/50 dark:border-zinc-800/50 shadow-xl inline-flex flex-col sm:flex-row gap-0 sm:gap-2 items-center overflow-hidden">

        {/* Live Indicator */}
        <div className="flex items-center gap-2 px-6 py-3 bg-white/50 dark:bg-black/50 rounded-xl w-full sm:w-auto justify-center sm:justify-start">
          <span className="relative flex h-3 w-3">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
          </span>
          <span className="text-xs font-bold tracking-wider uppercase text-zinc-500 dark:text-zinc-400">Mesh Status</span>
        </div>

        <div className="flex divide-y sm:divide-y-0 sm:divide-x divide-zinc-200 dark:divide-zinc-800 w-full sm:w-auto bg-white/30 dark:bg-black/30 rounded-xl">
          <StatItem label="Active Nodes" value={stats.nodesOnline} unit="online" />
          <StatItem label="Queued Jobs" value={stats.buildsQueued} unit="pending" />
          <StatItem label="Building" value={stats.activeBuilds} unit="now" warning={stats.activeBuilds > 10} />
          <StatItem label="24h Volume" value={stats.buildsToday} unit="completed" />
        </div>
      </div>
      <div className="mt-4 text-xs font-mono text-zinc-400 dark:text-zinc-500 tracking-tight flex items-center gap-2 opacity-70">
        <span>TOTAL LIFETIME BUILDS:</span>
        <span className="text-zinc-600 dark:text-zinc-300 font-bold bg-zinc-100 dark:bg-zinc-800/50 px-1.5 py-0.5 rounded text-[11px] tabular-nums">
          {stats.totalBuilds.toLocaleString()}
        </span>
      </div>
    </div>
  );
}

function StatItem({ label, value, unit, warning }: { label: string, value: number, unit: string, warning?: boolean }) {
  return (
    <div className="px-6 py-3 flex flex-col items-center sm:items-start min-w-[120px] relative group">
      <div className="text-[10px] uppercase tracking-widest text-zinc-500 dark:text-zinc-500 font-semibold mb-0.5">{label}</div>
      <div className="flex items-baseline gap-1.5">
        <span className={`text-2xl font-mono font-bold tracking-tighter tabular-nums ${warning ? 'text-amber-500' : 'text-zinc-900 dark:text-zinc-100'}`}>
          {value.toLocaleString()}
        </span>
        <span className="text-xs text-zinc-400 dark:text-zinc-500 font-medium">{unit}</span>
      </div>

      {/* Subtle glow effect on hover */}
      <div className="absolute inset-0 bg-gradient-to-b from-white/0 to-white/5 dark:to-white/5 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none" />
    </div>
  );
}
