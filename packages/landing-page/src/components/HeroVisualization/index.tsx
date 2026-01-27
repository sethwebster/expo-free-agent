import { Canvas } from '@react-three/fiber';
import { Suspense, useMemo } from 'react';
import { DistributedMesh } from './DistributedMesh';
import { EffectComposer, Bloom } from '@react-three/postprocessing';
import { NetworkEngineProvider } from '../../hooks/useNetworkEngine';
import { getQualitySettings } from './quality';

interface HeroVisualizationProps {
  className?: string;
  nodeCount?: number;
  pulseFrequencyScale?: number; // 0.1 = slow, 1 = normal, 2 = fast
  appearanceRate?: number; // 0-100 probability
  disappearanceRate?: number; // 0-100 probability
  scrollProgress?: number; // 0-1, scroll position
}

export function HeroVisualization({
  className,
  nodeCount = 18,
  pulseFrequencyScale = 1,
  appearanceRate = 10,
  disappearanceRate = 5,
  scrollProgress = 0,
}: HeroVisualizationProps) {
  // Lighter background for distant walls effect
  const backgroundColor = '#0a0a0a';

  // Get browser-adaptive quality settings
  const quality = useMemo(() => getQualitySettings(), []);

  // Cap node count based on browser capabilities
  const effectiveNodeCount = Math.min(nodeCount, quality.maxNodes);

  // Stop spawning nodes as mesh fades out
  // scrollProgress 0 = normal appearance rate
  // scrollProgress 0.3+ = 0% appearance rate (mesh gone)
  const expandedAppearanceRate = useMemo(() => {
    if (scrollProgress >= 0.3) return 0;
    return appearanceRate * (1 - scrollProgress / 0.3);
  }, [scrollProgress, appearanceRate]);

  return (
    <div className={`w-full h-full ${className ?? ''}`}>
      <NetworkEngineProvider
        initialNodeCount={effectiveNodeCount}
        appearanceRate={expandedAppearanceRate}
        disappearanceRate={scrollProgress > 0 ? 100 : disappearanceRate}
      >
        <Canvas
          camera={{ position: [0, 0, 18], fov: 65 }}
          dpr={quality.dpr}
          gl={{
            antialias: true,
            alpha: false,
            powerPreference: 'high-performance',
          }}
          style={{ background: backgroundColor, transition: 'background 300ms' }}
        >
          <Suspense fallback={null}>
            <DistributedMesh
              pulseFrequencyScale={pulseFrequencyScale}
              scrollProgress={scrollProgress}
            />
            <EffectComposer>
              <Bloom
                intensity={quality.bloomIntensity}
                luminanceThreshold={quality.bloomThreshold}
                luminanceSmoothing={quality.bloomSmoothing}
                mipmapBlur={quality.useMipmapBlur}
              />
            </EffectComposer>
          </Suspense>
        </Canvas>
      </NetworkEngineProvider>
    </div>
  );
}

// Re-export NodeData type for backward compatibility
export interface NodeData {
  id: number;
  position: [number, number, number];
  scale: number;
  rotationSpeed: number;
  driftOffset: number;
}

export type { NodeData as default };
