import { useState, useMemo, useEffect, useRef } from 'react';
import { HeroVisualization } from '../components/HeroVisualization';

export function HeroGlobePage() {
  // Visualization settings
  const [nodeCount, setNodeCount] = useState(18);
  const [jobFrequency, setJobFrequency] = useState(50); // 0-100 scale
  const [appearanceRate, setAppearanceRate] = useState(10); // 0-100%
  const [disappearanceRate, setDisappearanceRate] = useState(5); // 0-100%

  // Mouse position for spotlight
  const [mousePos, setMousePos] = useState({ x: 0.5, y: 0.5 });
  const containerRef = useRef<HTMLDivElement>(null);

  // Track mouse position
  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (containerRef.current) {
        const rect = containerRef.current.getBoundingClientRect();
        setMousePos({
          x: (e.clientX - rect.left) / rect.width,
          y: (e.clientY - rect.top) / rect.height,
        });
      }
    };

    window.addEventListener('mousemove', handleMouseMove);
    return () => window.removeEventListener('mousemove', handleMouseMove);
  }, []);

  // Generate a key to force remount when nodeCount changes
  const visualizationKey = useMemo(() => `viz-${nodeCount}`, [nodeCount]);

  return (
    <div ref={containerRef} className="min-h-screen bg-zinc-800 flex flex-col">
      {/* Header */}
      <header className="p-6 border-b border-zinc-800/50 bg-black/20 backdrop-blur-sm relative z-20">
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-white">
              Hero Visualization Test
            </h1>
            <p className="text-sm text-zinc-400">
              Testing the distributed mesh visualization
            </p>
          </div>
          <a
            href="/"
            className="px-4 py-2 bg-white text-black rounded-full text-sm font-medium hover:scale-105 transition-transform"
          >
            ← Back to Home
          </a>
        </div>
      </header>

      {/* Main visualization area */}
      <main className="flex-1 relative">
        {/* Full-screen visualization - z-0 base layer */}
        <div className="absolute inset-0 z-0">
          <HeroVisualization
            key={visualizationKey}
            className="w-full h-full"
            nodeCount={nodeCount}
            pulseFrequencyScale={jobFrequency / 50} // 0 = slow, 1 = normal, 2 = fast
            appearanceRate={appearanceRate}
            disappearanceRate={disappearanceRate}
          />
        </div>

        {/* Spotlight overlay - follows mouse */}
        <div
          className="absolute inset-0 z-[5] pointer-events-none transition-opacity duration-300"
          style={{
            background: `radial-gradient(
              circle 400px at ${mousePos.x * 100}% ${mousePos.y * 100}%,
              transparent 0%,
              rgba(0, 0, 0, 0.3) 50%,
              rgba(0, 0, 0, 0.6) 100%
            )`
          }}
        />
        {/* Overlay content to test readability */}
        <div className="relative z-10 max-w-4xl mx-auto py-32 px-6 text-center pointer-events-none">
          <div className="inline-block mb-6 px-4 py-1.5 rounded-full border border-white/10 bg-black/40 backdrop-blur-md text-[11px] font-semibold uppercase tracking-widest text-zinc-400">
            Open Source • Distributed • Secure
          </div>

          <h2 className="text-7xl md:text-9xl font-bold tracking-tighter mb-8 leading-[0.85] text-white drop-shadow-lg">
            <span>Distributed.</span>
            <br />
            <span className="bg-clip-text text-transparent bg-[linear-gradient(8deg,rgba(79,70,229,0.9)_0%,rgba(129,140,248,1)_50%,rgba(79,70,229,0.9)_100%)]">
              Unlimited.
            </span>
          </h2>

          <p className="text-2xl font-medium text-zinc-300 max-w-2xl mx-auto mb-12">
            Turn your idle Mac into build credits.
            <br />
            Build your Expo apps for free.
          </p>
        </div>
      </main>

      {/* Controls panel */}
      <footer className="p-6 border-t border-zinc-800/50 bg-black/60 backdrop-blur-md">
        <div className="max-w-6xl mx-auto">
          <h3 className="text-sm font-semibold text-white mb-4">
            Visualization Controls
          </h3>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Node Count Slider */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm text-zinc-600 dark:text-zinc-400">
                  Nodes
                </label>
                <span className="text-sm font-mono text-zinc-900 dark:text-white bg-zinc-100 dark:bg-zinc-800 px-2 py-0.5 rounded">
                  {nodeCount}
                </span>
              </div>
              <input
                type="range"
                min="5"
                max="40"
                value={nodeCount}
                onChange={(e) => setNodeCount(Number(e.target.value))}
                className="w-full h-2 bg-zinc-200 dark:bg-zinc-700 rounded-lg appearance-none cursor-pointer accent-indigo-500"
              />
              <div className="flex justify-between text-xs text-zinc-400">
                <span>5</span>
                <span>40</span>
              </div>
            </div>

            {/* Job Frequency Slider */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm text-zinc-600 dark:text-zinc-400">
                  Job Frequency
                </label>
                <span className="text-sm font-mono text-zinc-900 dark:text-white bg-zinc-100 dark:bg-zinc-800 px-2 py-0.5 rounded">
                  {jobFrequency < 33 ? 'Slow' : jobFrequency < 66 ? 'Normal' : 'Fast'}
                </span>
              </div>
              <input
                type="range"
                min="10"
                max="100"
                value={jobFrequency}
                onChange={(e) => setJobFrequency(Number(e.target.value))}
                className="w-full h-2 bg-zinc-200 dark:bg-zinc-700 rounded-lg appearance-none cursor-pointer accent-green-500"
              />
              <div className="flex justify-between text-xs text-zinc-400">
                <span>Slow</span>
                <span>Fast</span>
              </div>
            </div>

            {/* Appearance Rate Slider */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm text-zinc-600 dark:text-zinc-400">
                  Appearance Rate
                </label>
                <span className="text-sm font-mono text-zinc-900 dark:text-white bg-zinc-100 dark:bg-zinc-800 px-2 py-0.5 rounded">
                  {appearanceRate.toFixed(1)}%
                </span>
              </div>
              <input
                type="range"
                min="0"
                max="20"
                step="0.1"
                value={appearanceRate}
                onChange={(e) => setAppearanceRate(Number(e.target.value))}
                className="w-full h-2 bg-zinc-200 dark:bg-zinc-700 rounded-lg appearance-none cursor-pointer accent-emerald-500"
              />
              <div className="flex justify-between text-xs text-zinc-400">
                <span>0%</span>
                <span>20%</span>
              </div>
            </div>

            {/* Disappearance Rate Slider */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm text-zinc-600 dark:text-zinc-400">
                  Disappearance Rate
                </label>
                <span className="text-sm font-mono text-zinc-900 dark:text-white bg-zinc-100 dark:bg-zinc-800 px-2 py-0.5 rounded">
                  {disappearanceRate.toFixed(1)}%
                </span>
              </div>
              <input
                type="range"
                min="0"
                max="10"
                step="0.1"
                value={disappearanceRate}
                onChange={(e) => setDisappearanceRate(Number(e.target.value))}
                className="w-full h-2 bg-zinc-200 dark:bg-zinc-700 rounded-lg appearance-none cursor-pointer accent-rose-500"
              />
              <div className="flex justify-between text-xs text-zinc-400">
                <span>0%</span>
                <span>10%</span>
              </div>
            </div>
          </div>

          {/* Status notes */}
          <div className="mt-4 pt-4 border-t border-zinc-200 dark:border-zinc-700">
            <ul className="text-xs text-zinc-500 space-y-1 grid grid-cols-2 gap-x-4">
              <li>✓ Mouse movement creates parallax effect</li>
              <li>✓ Nodes gently rotate and drift</li>
              <li>✓ Connection lines with traveling pulses</li>
              <li>✓ Amber → Green glow on job arrival</li>
            </ul>
          </div>
        </div>
      </footer>
    </div>
  );
}
