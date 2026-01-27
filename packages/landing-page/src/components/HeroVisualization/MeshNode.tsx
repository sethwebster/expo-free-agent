import { useRef, useMemo, useState, useEffect, MutableRefObject } from 'react';
import { useFrame } from '@react-three/fiber';
import { Html } from '@react-three/drei';
import * as THREE from 'three';
import type { NodeState } from '../../services/meshNetworkEngine';
import {
  MESH_CONFIG,
  SPRING,
  ANIM_SPEED,
  COLORS,
  TIMING,
  tempColor,
  tempColorB,
} from './constants';
import { getQualitySettings } from './quality';
import { getGeometry, createEdgesGeometry, acquirePool, releasePool } from './geometryPool';
import {
  cloneGlassMaterial,
  createEmissiveMaterial,
  createLineMaterial,
  createPointMaterial,
  applyGlowingState,
  applyObsidianState,
  disposeMaterial,
  NodeMaterial,
} from './materialPool';

interface MeshNodeProps {
  node: NodeState;
  glowingNodesRef: MutableRefObject<Map<number, boolean>>;
  isOnline?: boolean;
  isJoining?: boolean;
  isHidden?: boolean;
  onClick?: (nodeId: number, position: [number, number, number]) => void;
}

// Generate random but stable stats for each node
function generateNodeStats(nodeId: number) {
  const seed = (nodeId * 9301 + 49297) % 233280;
  const random = (offset: number) => ((seed + offset * 1000) % 100) / 100;

  return {
    cpuCores: Math.floor(random(1) * 8) + 4,
    ramGB: Math.floor(random(2) * 48) + 16,
    uptimeHours: Math.floor(random(3) * 720),
    buildsCompleted: Math.floor(random(4) * 500) + 50,
    successRate: Math.floor(random(5) * 15) + 85,
  };
}

export function MeshNode({
  node,
  glowingNodesRef,
  isOnline = true,
  isJoining = false,
  isHidden = false,
  onClick,
}: MeshNodeProps) {
  const meshRef = useRef<THREE.Mesh>(null);
  const bigBangRef = useRef<THREE.Mesh>(null);
  const initialY = node.position[1];
  const glowRef = useRef(0);
  const glowStartTimeRef = useRef<number | null>(null);
  const onlineTransitionRef = useRef(isOnline ? 1 : 0);

  // Big bang flash effect
  const bigBangProgress = useRef(0);
  const [bigBangActive, setBigBangActive] = useState(false);
  const bigBangTriggered = useRef(false);

  // Track last material state to avoid redundant updates (Chrome optimization)
  const lastMaterialState = useRef<'glowing' | 'obsidian' | null>(null);
  const frameCounter = useRef(0);

  // Particle ring effect
  const particleRingRef = useRef<THREE.Points>(null);
  const ringProgress = useRef(0);
  const [ringActive, setRingActive] = useState(false);
  const ringStarted = useRef(false);

  // Store particle velocities for chaotic paths
  const particleVelocities = useRef<Float32Array | null>(null);

  // Spring physics for the "Bubble Pop" effect
  const springRef = useRef({
    current: isHidden ? 0 : 1,
    velocity: 0,
    target: isHidden ? 0 : 1,
  });

  const joiningTransitionRef = useRef(0);
  const [isHovered, setIsHovered] = useState(false);
  const hoverTimeoutRef = useRef<number | null>(null);

  const stats = useMemo(() => generateNodeStats(node.id), [node.id]);

  // Acquire geometry pool reference on mount
  useEffect(() => {
    acquirePool();
    return () => releasePool();
  }, []);

  // Get shared geometries from pool
  const geometry = useMemo(() => getGeometry('icosahedron'), []);
  const innerCoreGeometry = useMemo(() => getGeometry('innerCore'), []);
  const bigBangGeometry = useMemo(() => getGeometry('sphereLarge'), []);

  // Create edges geometry (depends on icosahedron, so not pooled)
  const edgesGeometry = useMemo(() => createEdgesGeometry(geometry), [geometry]);

  // Create materials (cloned so we can mutate per-instance)
  const material = useMemo(() => cloneGlassMaterial(), []);
  const edgeMaterial = useMemo(() => createLineMaterial(), []);
  const innerCoreMaterial = useMemo(() => createEmissiveMaterial(COLORS.GLOW_GREEN, false), []);
  const bigBangMaterial = useMemo(() => createEmissiveMaterial(COLORS.WHITE), []);
  const particleRingMaterial = useMemo(() => createPointMaterial(COLORS.WHITE, 0.15), []);

  // Get quality settings for particle count
  const qualitySettings = useMemo(() => getQualitySettings(), []);
  const particleCount = qualitySettings.particleCount;

  // Particle ring geometry with velocities
  const particleRingGeometry = useMemo(() => {
    const geom = new THREE.BufferGeometry();
    const positions = new Float32Array(particleCount * 3);
    const velocities = new Float32Array(particleCount * 3);

    for (let i = 0; i < particleCount; i++) {
      const angle = (i / particleCount) * Math.PI * 2;
      const radius = 1;
      positions[i * 3] = Math.cos(angle) * radius;
      positions[i * 3 + 1] = Math.sin(angle) * radius;
      positions[i * 3 + 2] = 0;

      const speed = 0.5 + Math.random() * 1.5;
      const angleVariance = (Math.random() - 0.5) * 0.8;
      velocities[i * 3] = Math.cos(angle + angleVariance) * speed;
      velocities[i * 3 + 1] = Math.sin(angle + angleVariance) * speed;
      velocities[i * 3 + 2] = (Math.random() - 0.5) * 0.5;
    }

    geom.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    particleVelocities.current = velocities;
    return geom;
  }, [particleCount]);

  // Inner core ref
  const innerCoreRef = useRef<THREE.Mesh>(null);

  // Dispose materials and non-pooled geometry on unmount
  useEffect(() => {
    return () => {
      edgesGeometry.dispose();
      particleRingGeometry.dispose();
      disposeMaterial(material);
      disposeMaterial(edgeMaterial);
      disposeMaterial(innerCoreMaterial);
      disposeMaterial(bigBangMaterial);
      disposeMaterial(particleRingMaterial);
    };
  }, [
    edgesGeometry,
    particleRingGeometry,
    material,
    edgeMaterial,
    innerCoreMaterial,
    bigBangMaterial,
    particleRingMaterial,
  ]);

  useFrame((state, delta) => {
    const mesh = meshRef.current;
    if (!mesh) return;

    const time = state.clock.elapsedTime;
    const now = Date.now();

    // Trigger big bang flash when node first appears
    if (isJoining && !bigBangTriggered.current && !isHidden) {
      setBigBangActive(true);
      bigBangProgress.current = 0;
      bigBangTriggered.current = true;
    }

    if (!isJoining) {
      bigBangTriggered.current = false;
    }

    // Animate big bang flash
    if (bigBangActive && bigBangRef.current) {
      bigBangProgress.current += delta * ANIM_SPEED.BIG_BANG;

      if (bigBangProgress.current >= 1) {
        setBigBangActive(false);
        bigBangMaterial.opacity = 0;
        setRingActive(true);
        ringProgress.current = 0;
        ringStarted.current = false;
      } else {
        bigBangRef.current.position.copy(mesh.position);
        const scale = 1 + bigBangProgress.current * MESH_CONFIG.BIG_BANG_EXPANSION;
        bigBangRef.current.scale.setScalar(scale);
        const opacity = Math.pow(1 - bigBangProgress.current, 2) * 1.5;
        bigBangMaterial.opacity = Math.min(1, opacity);
      }
    }

    // Animate particle ring
    if (ringActive && particleRingRef.current && particleVelocities.current) {
      if (!ringStarted.current) {
        const positions = particleRingRef.current.geometry.attributes.position
          .array as Float32Array;
        for (let i = 0; i < particleCount; i++) {
          const angle = (i / particleCount) * Math.PI * 2;
          positions[i * 3] = Math.cos(angle);
          positions[i * 3 + 1] = Math.sin(angle);
          positions[i * 3 + 2] = 0;
        }
        particleRingRef.current.geometry.attributes.position.needsUpdate = true;
        ringStarted.current = true;
      }

      ringProgress.current += delta * ANIM_SPEED.PARTICLE_RING;

      if (ringProgress.current >= 1) {
        setRingActive(false);
        particleRingMaterial.opacity = 0;
        ringStarted.current = false;
      } else {
        particleRingRef.current.position.copy(mesh.position);

        const positions = particleRingRef.current.geometry.attributes.position
          .array as Float32Array;
        const velocities = particleVelocities.current;

        for (let i = 0; i < particleCount; i++) {
          const idx = i * 3;
          positions[idx] += velocities[idx] * delta * 3;
          positions[idx + 1] += velocities[idx + 1] * delta * 3;
          positions[idx + 2] += velocities[idx + 2] * delta * 3;
          positions[idx] += Math.sin(time * 2 + i) * 0.02;
          positions[idx + 1] += Math.cos(time * 2 + i) * 0.02;
        }

        particleRingRef.current.geometry.attributes.position.needsUpdate = true;

        particleRingMaterial.opacity = (1 - ringProgress.current) * 0.9;

        // Color transition using temp colors
        const progress = ringProgress.current;
        if (progress < 0.33) {
          const t = progress / 0.33;
          tempColor.setHex(COLORS.WHITE);
          tempColorB.setHex(COLORS.ORANGE);
          tempColor.lerp(tempColorB, t);
        } else if (progress < 0.66) {
          const t = (progress - 0.33) / 0.33;
          tempColor.setHex(COLORS.ORANGE);
          tempColorB.setHex(COLORS.RED);
          tempColor.lerp(tempColorB, t);
        } else {
          tempColor.setHex(COLORS.RED);
        }
        particleRingMaterial.color.copy(tempColor);
      }
    }

    // Update Spring Target
    springRef.current.target = isHidden ? 0 : 1;

    // Bubble Pop Spring Physics
    const stiffness = isHidden ? SPRING.EXIT_STIFFNESS : SPRING.ENTRY_STIFFNESS;
    const damping = isHidden ? SPRING.EXIT_DAMPING : SPRING.ENTRY_DAMPING;

    const force = (springRef.current.target - springRef.current.current) * stiffness;
    const friction = springRef.current.velocity * damping;
    const acceleration = force - friction;

    springRef.current.velocity += acceleration * delta;
    springRef.current.current += springRef.current.velocity * delta;

    const popAmount = Math.max(0, springRef.current.current);

    // Animate online/offline transition
    const targetOnline = isOnline ? 1 : 0;
    onlineTransitionRef.current +=
      (targetOnline - onlineTransitionRef.current) * ANIM_SPEED.ONLINE_LERP;
    const onlineAmount = onlineTransitionRef.current;

    // Animate joining flash
    const targetJoining = isJoining ? 1 : 0;
    joiningTransitionRef.current +=
      (targetJoining - joiningTransitionRef.current) * ANIM_SPEED.JOINING_LERP;

    // Rotation & Floating
    const rotationActive = popAmount > 0.1 ? 1 : 0;
    mesh.rotation.x += node.rotationSpeed * 0.01 * onlineAmount * rotationActive;
    mesh.rotation.y += node.rotationSpeed * 0.015 * onlineAmount * rotationActive;
    const driftY = Math.sin(time * 0.5 + node.driftOffset) * 0.15 * onlineAmount;
    const driftX = Math.cos(time * 0.3 + node.driftOffset) * 0.1 * onlineAmount;
    mesh.position.y = initialY + driftY;
    mesh.position.x = node.position[0] + driftX;

    // Final Bubble Scale
    const breathe = 1 + Math.sin(time * 0.8 + node.driftOffset) * 0.05 * onlineAmount;
    const offlineScale = 0.3 + onlineAmount * 0.7;
    mesh.scale.setScalar(node.scale * breathe * offlineScale * popAmount);

    // Materials & Colors
    const isGlowing = isOnline && glowingNodesRef.current.has(node.id) && !isHidden;
    if (isGlowing && glowStartTimeRef.current === null) {
      glowStartTimeRef.current = now;
    } else if (!isGlowing) {
      glowStartTimeRef.current = null;
    }

    const targetGlow = isGlowing ? 1 : 0;
    glowRef.current += (targetGlow - glowRef.current) * ANIM_SPEED.GLOW_LERP;

    const mat = mesh.material as NodeMaterial;

    // Opacity is cheap - update every frame
    mat.opacity = Math.min(1, popAmount);

    // Determine target material state
    const targetState: 'glowing' | 'obsidian' =
      glowRef.current > 0.01 && isOnline && !isHidden ? 'glowing' : 'obsidian';

    // Only apply full material updates on state transitions or every few frames
    // This dramatically reduces shader recompilation on Chrome
    frameCounter.current++;
    const shouldUpdateMaterial =
      lastMaterialState.current !== targetState ||
      (targetState === 'glowing' && frameCounter.current % 3 === 0);

    if (targetState === 'glowing') {
      const timeSinceGlowStart = glowStartTimeRef.current
        ? now - glowStartTimeRef.current
        : 0;
      const isAmber = timeSinceGlowStart < TIMING.AMBER_DURATION;
      const glowColorHex = isAmber ? COLORS.GLOW_AMBER : COLORS.GLOW_GREEN;
      tempColor.setHex(glowColorHex);

      // Only apply expensive material state on transitions or throttled frames
      if (shouldUpdateMaterial) {
        applyGlowingState(mat, tempColor, glowRef.current);
        lastMaterialState.current = 'glowing';
      } else {
        // Cheap updates only - emissive intensity for glow animation
        mat.emissiveIntensity = 0.2 * glowRef.current;
      }

      const pulse = 1 + Math.sin(time * 3) * 0.15;
      const edgePulse = 0.4 + Math.sin(time * 2.5) * 0.3;

      edgeMaterial.opacity = edgePulse * glowRef.current;
      edgeMaterial.color.copy(tempColor);

      if (innerCoreRef.current) {
        innerCoreMaterial.color.copy(tempColor);
        innerCoreMaterial.opacity = glowRef.current;
        innerCoreRef.current.scale.setScalar(pulse * 0.85);
      }
    } else {
      // Only apply obsidian state on transition, not every frame
      if (lastMaterialState.current !== 'obsidian') {
        applyObsidianState(mat);
        lastMaterialState.current = 'obsidian';
      }
      edgeMaterial.opacity = 0.3 * onlineAmount;
      edgeMaterial.color.setHex(COLORS.DARK_GRAY);
      innerCoreMaterial.opacity = 0;
    }

    mesh.visible = popAmount > 0.001;
  });

  return (
    <>
      <mesh
        ref={meshRef}
        position={node.position}
        scale={node.scale}
        geometry={geometry}
        material={material}
        onPointerEnter={(e) => {
          if (isHidden) return;
          e.stopPropagation();
          if (hoverTimeoutRef.current) {
            clearTimeout(hoverTimeoutRef.current);
            hoverTimeoutRef.current = null;
          }
          setIsHovered(true);
          document.body.style.cursor = 'pointer';
        }}
        onPointerLeave={() => {
          hoverTimeoutRef.current = window.setTimeout(() => {
            setIsHovered(false);
            document.body.style.cursor = 'default';
          }, TIMING.HOVER_TIMEOUT);
        }}
        onPointerDown={(e) => {
          if (isHidden) return;
          e.stopPropagation();
          onClick?.(node.id, node.position);
        }}
      >
        <lineSegments geometry={edgesGeometry} material={edgeMaterial} />

        <mesh
          ref={innerCoreRef}
          geometry={innerCoreGeometry}
          material={innerCoreMaterial}
        />

        {isHovered && isOnline && !isHidden && (
          <Html position={[-0.5, 2.5, 0]} center distanceFactor={15}>
            <div
              className="bg-black/90 backdrop-blur-md border border-blue-500/40 rounded-lg p-3 shadow-[0_0_20px_rgba(59,130,246,0.2)] min-w-[200px]"
              onPointerEnter={() => {
                if (hoverTimeoutRef.current) {
                  clearTimeout(hoverTimeoutRef.current);
                  hoverTimeoutRef.current = null;
                }
              }}
              onPointerLeave={() => {
                setIsHovered(false);
                document.body.style.cursor = 'default';
              }}
            >
              <div className="text-blue-400 font-bold text-xs mb-2 flex items-center justify-between">
                <span className="flex items-center gap-2">
                  <span className="w-2 h-2 rounded-full bg-blue-400 animate-pulse outline outline-blue-400/50"></span>
                  Node #{node.id + 1}
                </span>
                <span className="text-[10px] bg-blue-500/10 px-1.5 py-0.5 rounded border border-blue-500/20">
                  AGENT_v2.4
                </span>
              </div>
              <div className="space-y-1.5 text-[11px]">
                <div className="flex justify-between items-center text-zinc-300">
                  <span className="text-zinc-500 uppercase tracking-wider font-semibold">
                    Cores
                  </span>
                  <span className="font-mono text-blue-200">
                    {stats.cpuCores} @ 4.2GHz
                  </span>
                </div>
                <div className="flex justify-between items-center text-zinc-300">
                  <span className="text-zinc-500 uppercase tracking-wider font-semibold">
                    Memory
                  </span>
                  <span className="font-mono text-blue-200">
                    {stats.ramGB} GB DDR5
                  </span>
                </div>
                <div className="h-px bg-white/10 my-1.5" />
                <div className="flex justify-between items-center">
                  <span className="text-zinc-500 uppercase tracking-wider font-semibold">
                    Integrity
                  </span>
                  <span className="font-mono text-green-400 font-bold">
                    {stats.successRate}%
                  </span>
                </div>
              </div>
            </div>
          </Html>
        )}
      </mesh>

      {bigBangActive && (
        <mesh
          ref={bigBangRef}
          position={node.position}
          geometry={bigBangGeometry}
          material={bigBangMaterial}
        />
      )}

      {ringActive && (
        <points
          ref={particleRingRef}
          position={node.position}
          geometry={particleRingGeometry}
          material={particleRingMaterial}
        />
      )}
    </>
  );
}
