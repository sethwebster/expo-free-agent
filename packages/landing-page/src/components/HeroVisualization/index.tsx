import { Canvas } from '@react-three/fiber';
import { Suspense, useMemo } from 'react';
import { DistributedMesh } from './DistributedMesh';
import { EffectComposer, Bloom } from '@react-three/postprocessing';

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
  scrollProgress = 0
}: HeroVisualizationProps) {
  // Generate node positions based on nodeCount
  const nodeData = useMemo(() => generateNodePositions(nodeCount), [nodeCount]);

  // Pure black background for starfield
  const backgroundColor = '#000000';

  return (
    <div className={`w-full h-full ${className ?? ''}`}>
      <Canvas
        camera={{ position: [0, 0, 18], fov: 65 }} // Wider FOV to show more
        dpr={[1, 1.5]} // Capped pixel ratio for performance
        gl={{
          antialias: true,
          alpha: false,
          powerPreference: 'high-performance'
        }}
        style={{ background: backgroundColor, transition: 'background 300ms' }}
      >
        <Suspense fallback={null}>
          <DistributedMesh
            nodeData={nodeData}
            pulseFrequencyScale={pulseFrequencyScale}
            appearanceRate={appearanceRate}
            disappearanceRate={disappearanceRate}
            scrollProgress={scrollProgress}
          />
          <EffectComposer>
            <Bloom
              intensity={2}
              luminanceThreshold={0.2}
              luminanceSmoothing={0.9}
              mipmapBlur
            />
          </EffectComposer>
        </Suspense>
      </Canvas>
    </div>
  );
}

// Generate random node positions with clustering
interface NodeData {
  id: number;
  position: [number, number, number];
  scale: number;
  rotationSpeed: number;
  driftOffset: number;
}

function generateNodePositions(count: number): NodeData[] {
  const nodes: NodeData[] = [];
  const minDistance = 2.5; // Minimum distance between node centers
  const maxAttempts = 100;

  // Use a hybrid approach: some in a grid pattern, some random
  // This ensures good coverage while maintaining organic feel

  const gridCols = 6;
  const gridRows = 5;
  const xSpread = 32;
  const ySpread = 20;
  const zMin = -10;
  const zMax = 4;

  for (let i = 0; i < count; i++) {
    let x: number, y: number, z: number;
    let validPosition = false;
    let attempts = 0;

    do {
      if (i < gridCols * gridRows) {
        // Grid-based positioning with jitter for first batch
        const col = i % gridCols;
        const row = Math.floor(i / gridCols);

        const cellWidth = xSpread / gridCols;
        const cellHeight = ySpread / gridRows;

        const jitterX = (Math.random() - 0.5) * cellWidth * 0.8;
        const jitterY = (Math.random() - 0.5) * cellHeight * 0.8;

        x = -xSpread / 2 + cellWidth * (col + 0.5) + jitterX;
        y = -ySpread / 2 + cellHeight * (row + 0.5) + jitterY;
        z = zMin + Math.random() * (zMax - zMin);
      } else {
        // Extra nodes placed randomly across the full area
        x = (Math.random() - 0.5) * xSpread;
        y = (Math.random() - 0.5) * ySpread;
        z = zMin + Math.random() * (zMax - zMin);
      }

      // Check distance to all existing nodes
      validPosition = nodes.every(node => {
        const dx = x - node.position[0];
        const dy = y - node.position[1];
        const dz = z - node.position[2];
        const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
        return dist >= minDistance;
      });

      attempts++;
    } while (!validPosition && attempts < maxAttempts);

    // Only add node if we found a valid position
    if (validPosition || nodes.length === 0) {
      const depthFactor = (z - zMin) / (zMax - zMin);
      const baseScale = 0.5 + depthFactor * 0.4;
      const scaleVariation = (Math.random() - 0.5) * 0.3;

      nodes.push({
        id: i,
        position: [x, y, z],
        scale: Math.max(0.3, baseScale + scaleVariation),
        rotationSpeed: 0.1 + Math.random() * 0.3,
        driftOffset: Math.random() * Math.PI * 2,
      });
    }
  }

  return nodes;
}

export type { NodeData };
