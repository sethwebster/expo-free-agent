import { useRef, useMemo, useCallback, useEffect } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';
import { MeshNode } from './MeshNode';
import { ConnectionLine } from './ConnectionLine';
import { useNetworkNodes } from '../../hooks/useNetworkNodes';
import { useNetworkConnections } from '../../hooks/useNetworkConnections';
import { useGlowingNodesRef, usePulseHandlers } from '../../hooks/useGlowingNodes';
import { COLORS } from './constants';
import { getGeometry, acquirePool, releasePool } from './geometryPool';
import { createCycloramaMaterial, disposeMaterial } from './materialPool';

interface DistributedMeshProps {
  pulseFrequencyScale?: number;
  scrollProgress?: number;
}

export function DistributedMesh({
  pulseFrequencyScale = 1,
  scrollProgress = 0,
}: DistributedMeshProps) {
  const rotationGroupRef = useRef<THREE.Group>(null);
  const parallaxGroupRef = useRef<THREE.Group>(null);
  const { pointer, camera, viewport, size } = useThree();

  const targetQuaternion = useRef(new THREE.Quaternion());
  const currentQuaternion = useRef(new THREE.Quaternion());
  const driftTime = useRef(0);

  // Subscribe to engine state via hooks
  const nodes = useNetworkNodes();
  const { connections, markRetracted } = useNetworkConnections();
  const glowingNodesRef = useGlowingNodesRef();
  const { onPulseArrival, onPulseDeparture } = usePulseHandlers();

  // Acquire geometry pool on mount
  useEffect(() => {
    acquirePool();
    return () => releasePool();
  }, []);

  // Adjust camera FOV for responsive viewing
  useEffect(() => {
    if (!camera) return;

    const aspect = size.width / size.height;
    // Wider FOV for portrait/narrow viewports to see more mesh
    let fov = 65; // Default desktop FOV

    if (aspect < 1.0) {
      // Portrait: wider FOV
      fov = 75 + (1.0 - aspect) * 10; // 75-85 degrees
    } else if (aspect < 1.3) {
      // Narrow landscape: slightly wider
      fov = 70;
    }

    camera.fov = Math.min(85, Math.max(65, fov));
    camera.updateProjectionMatrix();
  }, [camera, size.width, size.height]);

  const handleNodeClick = useCallback(
    (_id: number, pos: [number, number, number]) => {
      const target = new THREE.Vector3(...pos).normalize();
      const currentFront = new THREE.Vector3(0, 0, 1);
      const quat = new THREE.Quaternion().setFromUnitVectors(target, currentFront);
      targetQuaternion.current.copy(quat);
    },
    []
  );

  const handleRetractComplete = useCallback(
    (key: string) => {
      markRetracted(key);
    },
    [markRetracted]
  );

  useFrame((state, delta) => {
    // Increment drift time for organic motion
    driftTime.current += delta * 0.3;

    // Smoothed Focus Rotation
    currentQuaternion.current.slerp(targetQuaternion.current, 0.05);
    if (rotationGroupRef.current) {
      rotationGroupRef.current.quaternion.copy(currentQuaternion.current);
    }

    // Mouse Parallax, Responsive Scaling, and Gentle Drift
    if (parallaxGroupRef.current) {
      const targetX = pointer.x * 0.4;
      const targetY = pointer.y * 0.2;

      // Organic drift motion - multiple sine waves at different frequencies
      const driftY = Math.sin(driftTime.current * 0.5) * 0.15; // Slow Y-axis rotation
      const driftX = Math.cos(driftTime.current * 0.3) * 0.08; // Slower X-axis tilt
      const driftZ = Math.sin(driftTime.current * 0.4) * 0.05; // Subtle Z-axis roll

      // Combine mouse parallax with drift
      parallaxGroupRef.current.rotation.y +=
        (targetX + driftY - parallaxGroupRef.current.rotation.y) * 0.03;
      parallaxGroupRef.current.rotation.x +=
        (-targetY + driftX - parallaxGroupRef.current.rotation.x) * 0.03;
      parallaxGroupRef.current.rotation.z +=
        (driftZ - parallaxGroupRef.current.rotation.z) * 0.02;

      // Responsive scaling based on viewport aspect ratio
      // Viewport aspect: viewport.width / viewport.height
      // Reference aspect (desktop): 16/9 = 1.78
      const aspect = size.width / size.height;
      const referenceAspect = 16 / 9;

      // Scale mesh to fill narrower viewports (mobile portrait)
      // aspect < 1.0 = portrait, scale up
      // aspect > 1.78 = ultra-wide, scale down slightly
      let responsiveScale = 1;
      if (aspect < referenceAspect) {
        // Portrait/narrow: scale up to fill width
        responsiveScale = 1 + (referenceAspect - aspect) * 0.3;
      } else if (aspect > referenceAspect) {
        // Ultra-wide: scale down slightly to prevent stretching
        responsiveScale = 1 - (aspect - referenceAspect) * 0.1;
      }

      // Clamp to reasonable bounds
      responsiveScale = Math.max(0.8, Math.min(1.8, responsiveScale));

      // Expand mesh to fill globe as camera pulls back
      // Start at scale 1, expand to 3x to fill the globe sphere
      const expansionScale = 1 + (scrollProgress * 2);

      // Combine responsive and expansion scaling
      const finalScale = expansionScale * responsiveScale;
      parallaxGroupRef.current.scale.setScalar(finalScale);
    }

    // Scroll-based camera pullback reveal
    // scrollProgress 0 = inside mesh, scrollProgress 1 = pulled back to reveal globe
    const targetZ = 18 + (scrollProgress * 102); // 18 -> 120
    camera.position.z += (targetZ - camera.position.z) * 0.1;

  });

  return (
    <>
      <fog attach="fog" args={[COLORS.DARK_GRAY, 30, 200]} />

      <ambientLight intensity={0.5} />

      {/* Area light above mesh - illuminates from inside the globe */}
      <rectAreaLight
        position={[0, 25, 0]}
        rotation={[-Math.PI / 2, 0, 0]}
        width={120}
        height={120}
        intensity={4}
        color={0xffffff}
      />

      <group ref={rotationGroupRef}>
        <group ref={parallaxGroupRef}>
          {nodes.map((node) => (
            <MeshNode
              key={node.id}
              node={node}
              glowingNodesRef={glowingNodesRef}
              isOnline={node.status === 'active'}
              isJoining={node.isJoining}
              isHidden={node.status === 'hidden'}
              onClick={handleNodeClick}
            />
          ))}

          {connections.map((conn) => (
            <ConnectionLine
              key={conn.key}
              from={conn.from}
              to={conn.to}
              fromId={conn.fromId}
              toId={conn.toId}
              index={conn.fromId}
              pulseFrequencyScale={pulseFrequencyScale}
              onPulseArrival={onPulseArrival}
              onPulseDeparture={onPulseDeparture}
              isActive={!conn.isRemoving}
              isRemoving={conn.isRemoving}
              onRetractComplete={() => handleRetractComplete(conn.key)}
            />
          ))}
        </group>
      </group>
    </>
  );
}
