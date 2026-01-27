import { useRef, useMemo, useState, MutableRefObject } from 'react';
import { useFrame } from '@react-three/fiber';
import { Html } from '@react-three/drei';
import * as THREE from 'three';
import type { NodeData } from './index';

interface MeshNodeProps {
  node: NodeData;
  glowingNodesRef: MutableRefObject<Map<number, boolean>>;
  isOnline?: boolean;
  isJoining?: boolean;
  isHidden?: boolean;
  onClick?: (nodeId: number, position: [number, number, number]) => void;
}

// Generate random but stable stats for each node
function generateNodeStats(nodeId: number) {
  // Use nodeId as seed for pseudo-random but stable values
  const seed = (nodeId * 9301 + 49297) % 233280;
  const random = (offset: number) => ((seed + offset * 1000) % 100) / 100;

  const cpuCores = Math.floor(random(1) * 8) + 4; // 4-12 cores
  const ramGB = Math.floor(random(2) * 48) + 16; // 16-64 GB
  const uptimeHours = Math.floor(random(3) * 720); // 0-720 hours
  const buildsCompleted = Math.floor(random(4) * 500) + 50; // 50-550
  const successRate = Math.floor(random(5) * 15) + 85; // 85-100%

  return { cpuCores, ramGB, uptimeHours, buildsCompleted, successRate };
}

const createGlassMaterial = () => {
  return new THREE.MeshPhysicalMaterial({
    color: '#e0e7ff',
    metalness: 0.1,
    roughness: 0.1,
    transparent: true,
    opacity: 0.7,
    envMapIntensity: 1.5,
    clearcoat: 1,
    clearcoatRoughness: 0.1,
    reflectivity: 0.9,
    side: THREE.DoubleSide,
  });
};

export function MeshNode({
  node,
  glowingNodesRef,
  isOnline = true,
  isJoining = false,
  isHidden = false,
  onClick
}: MeshNodeProps) {
  const meshRef = useRef<THREE.Mesh>(null);
  const initialY = node.position[1];
  const glowRef = useRef(0);
  const glowStartTimeRef = useRef<number | null>(null);
  const onlineTransitionRef = useRef(isOnline ? 1 : 0);

  // Spring physics for the "Bubble Pop" effect
  const springRef = useRef({
    current: isHidden ? 0 : 1,
    velocity: 0,
    target: isHidden ? 0 : 1
  });

  const joiningTransitionRef = useRef(0);
  const [isHovered, setIsHovered] = useState(false);
  const hoverTimeoutRef = useRef<number | null>(null);

  const stats = useMemo(() => generateNodeStats(node.id), [node.id]);
  const geometry = useMemo(() => new THREE.DodecahedronGeometry(1, 0), []);
  const edgesGeometry = useMemo(() => new THREE.EdgesGeometry(geometry), [geometry]);
  const material = useMemo(() => createGlassMaterial(), []);
  const edgeMaterial = useMemo(() => new THREE.LineBasicMaterial({ transparent: true, opacity: 0.8 }), []);

  useFrame((state, delta) => {
    if (meshRef.current) {
      const time = state.clock.elapsedTime;
      const now = Date.now();

      // Update Spring Target
      springRef.current.target = isHidden ? 0 : 1;

      // Bubble Pop Spring Physics
      // Entry: High tension, some bounce (Overshoot)
      // Exit: Snappy scale to zero
      const stiffness = isHidden ? 180 : 140;
      const damping = isHidden ? 25 : 15;

      const force = (springRef.current.target - springRef.current.current) * stiffness;
      const friction = springRef.current.velocity * damping;
      const acceleration = force - friction;

      springRef.current.velocity += acceleration * delta;
      springRef.current.current += springRef.current.velocity * delta;

      const popAmount = Math.max(0, springRef.current.current);

      // Animate online/offline transition
      const targetOnline = isOnline ? 1 : 0;
      onlineTransitionRef.current += (targetOnline - onlineTransitionRef.current) * 0.05;
      const onlineAmount = onlineTransitionRef.current;

      // Animate joining flash
      const targetJoining = isJoining ? 1 : 0;
      joiningTransitionRef.current += (targetJoining - joiningTransitionRef.current) * 0.1;

      // Rotation & Floating
      meshRef.current.rotation.x += node.rotationSpeed * 0.01 * onlineAmount * (popAmount > 0.1 ? 1 : 0);
      meshRef.current.rotation.y += node.rotationSpeed * 0.015 * onlineAmount * (popAmount > 0.1 ? 1 : 0);
      const driftY = Math.sin(time * 0.5 + node.driftOffset) * 0.15 * onlineAmount;
      const driftX = Math.cos(time * 0.3 + node.driftOffset) * 0.1 * onlineAmount;
      meshRef.current.position.y = initialY + driftY;
      meshRef.current.position.x = node.position[0] + driftX;

      // Final Bubble Scale
      const breathe = 1 + Math.sin(time * 0.8 + node.driftOffset) * 0.05 * onlineAmount;
      const offlineScale = 0.3 + onlineAmount * 0.7;
      meshRef.current.scale.setScalar(node.scale * breathe * offlineScale * popAmount);

      // Materials & Colors
      const isGlowing = isOnline && glowingNodesRef.current.has(node.id) && !isHidden;
      if (isGlowing && glowStartTimeRef.current === null) glowStartTimeRef.current = now;
      else if (!isGlowing) glowStartTimeRef.current = null;

      const targetGlow = isGlowing ? 1 : 0;
      glowRef.current += (targetGlow - glowRef.current) * 0.15;

      const mat = meshRef.current.material as THREE.MeshPhysicalMaterial;
      const lineMat = edgeMaterial;

      const baseColor = 0xe0e7ff;
      const offlineColor = 0x52525b;
      const amberColor = 0xfef3c7;
      const greenColor = 0xbbf7d0;

      mat.opacity = (0.3 + onlineAmount * 0.5) * Math.min(1, popAmount);

      if (glowRef.current > 0.01 && isOnline && !isHidden) {
        lineMat.opacity = (0.2 + onlineAmount * 0.6) * Math.min(1, popAmount);
        const timeSinceGlowStart = glowStartTimeRef.current ? now - glowStartTimeRef.current : 0;
        if (timeSinceGlowStart < 200) {
          mat.color.copy(new THREE.Color(baseColor).lerp(new THREE.Color(amberColor), glowRef.current));
          mat.emissive.setHex(0xfbbf24);
          mat.emissiveIntensity = glowRef.current * 1.2;
          lineMat.color.setHex(0xfbbf24);
        } else {
          mat.color.copy(new THREE.Color(baseColor).lerp(new THREE.Color(greenColor), glowRef.current));
          mat.emissive.setHex(0x4ade80);
          mat.emissiveIntensity = glowRef.current * 1.0;
          lineMat.color.setHex(0x4ade80);
        }
      } else {
        // Black Onyx appearance for inactive nodes
        if (onlineAmount < 0.5) {
          // Offline: Pure black onyx - polished stone with clearcoat
          mat.color.setHex(0x000000); // Pure black
          mat.emissive.setHex(0x111111); // Very subtle self-illumination
          mat.emissiveIntensity = 0.15;
          mat.metalness = 0.1; // Stone, not metal
          mat.roughness = 0.05; // Very smooth, polished
          mat.clearcoat = 1.0; // High gloss polish
          mat.clearcoatRoughness = 0.05;
          mat.reflectivity = 0.95;
          lineMat.opacity = 0.2;
          lineMat.color.setHex(0x222222);
        } else {
          // Transitioning to online
          const currentBase = new THREE.Color(offlineColor).lerp(new THREE.Color(baseColor), onlineAmount);
          mat.color.copy(currentBase);
          mat.emissive.copy(currentBase);
          mat.emissiveIntensity = (onlineAmount - 0.5) * 0.4;
          mat.metalness = 0.1;
          mat.roughness = 0.1;
          mat.clearcoat = 1.0;
          mat.clearcoatRoughness = 0.1;
          lineMat.opacity = (onlineAmount - 0.5) * 2 * 0.4;
          lineMat.color.copy(currentBase);
        }
      }

      meshRef.current.visible = popAmount > 0.001;
    }
  });

  return (
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
        }, 100);
      }}
      onPointerDown={(e) => {
        if (isHidden) return;
        e.stopPropagation();
        onClick?.(node.id, node.position);
      }}
    >
      <lineSegments geometry={edgesGeometry} material={edgeMaterial} />
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
              <span className="text-[10px] bg-blue-500/10 px-1.5 py-0.5 rounded border border-blue-500/20">AGENT_v2.4</span>
            </div>
            <div className="space-y-1.5 text-[11px]">
              <div className="flex justify-between items-center text-zinc-300">
                <span className="text-zinc-500 uppercase tracking-wider font-semibold">Cores</span>
                <span className="font-mono text-blue-200">{stats.cpuCores} @ 4.2GHz</span>
              </div>
              <div className="flex justify-between items-center text-zinc-300">
                <span className="text-zinc-500 uppercase tracking-wider font-semibold">Memory</span>
                <span className="font-mono text-blue-200">{stats.ramGB} GB DDR5</span>
              </div>
              <div className="h-px bg-white/10 my-1.5" />
              <div className="flex justify-between items-center">
                <span className="text-zinc-500 uppercase tracking-wider font-semibold">Integrity</span>
                <span className="font-mono text-green-400 font-bold">{stats.successRate}%</span>
              </div>
            </div>
          </div>
        </Html>
      )}
    </mesh>
  );
}
