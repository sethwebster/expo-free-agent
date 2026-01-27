import { useRef, useMemo, useCallback, useState, useEffect } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';
import { MeshNode } from './MeshNode';
import { ConnectionLine } from './ConnectionLine';
import type { NodeData } from './index';
import { useNetworkContext } from '../../contexts/NetworkContext';

interface DistributedMeshProps {
  nodeData: NodeData[];
  pulseFrequencyScale?: number;
  appearanceRate?: number; // 0-100 probability
  disappearanceRate?: number; // 0-100 probability
  scrollProgress?: number; // 0-1, scroll position
}

interface NodeState {
  status: 'hidden' | 'offline' | 'active';
}

// Helper to generate a single node position with collision avoidance
function generateNodePosition(id: number, existingNodes: NodeData[]): NodeData {
  const xSpread = 32;
  const ySpread = 20;
  const zMin = -10;
  const zMax = 4;
  const minDistance = 2.5; // Minimum distance between node centers (1 node width + buffer)
  const maxAttempts = 50;

  let attempts = 0;
  let x: number, y: number, z: number;
  let validPosition = false;

  do {
    x = (Math.random() - 0.5) * xSpread;
    y = (Math.random() - 0.5) * ySpread;
    z = zMin + Math.random() * (zMax - zMin);

    // Check distance to all existing nodes
    validPosition = existingNodes.every(node => {
      const dx = x - node.position[0];
      const dy = y - node.position[1];
      const dz = z - node.position[2];
      const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
      return dist >= minDistance;
    });

    attempts++;
  } while (!validPosition && attempts < maxAttempts);

  const depthFactor = (z - zMin) / (zMax - zMin);
  const baseScale = 0.5 + depthFactor * 0.4;
  const scaleVariation = (Math.random() - 0.5) * 0.3;

  return {
    id,
    position: [x, y, z],
    scale: Math.max(0.3, baseScale + scaleVariation),
    rotationSpeed: 0.1 + Math.random() * 0.3,
    driftOffset: Math.random() * Math.PI * 2,
  };
}

export function DistributedMesh({
  nodeData: initialNodeData,
  pulseFrequencyScale = 1,
  appearanceRate = 10,
  disappearanceRate = 5,
  scrollProgress = 0
}: DistributedMeshProps) {
  const rotationGroupRef = useRef<THREE.Group>(null);
  const parallaxGroupRef = useRef<THREE.Group>(null);
  const { pointer, camera } = useThree();

  // Track glowing nodes
  const glowingNodesRef = useRef<Map<number, boolean>>(new Map());

  // Target rotation for clicking nodes
  const targetQuaternion = useRef(new THREE.Quaternion());
  const currentQuaternion = useRef(new THREE.Quaternion());

  // Dynamic node array - can grow/shrink
  const [nodeData, setNodeData] = useState<NodeData[]>(initialNodeData);
  const nextNodeId = useRef(initialNodeData.length);

  // Track the lifecycle state of every node
  const [nodeLifecycle, setNodeLifecycle] = useState<Record<number, NodeState>>(() => {
    const initial: Record<number, NodeState> = {};
    initialNodeData.forEach(node => {
      const rand = Math.random();
      if (rand < 0.6) initial[node.id] = { status: 'active' };
      else if (rand < 0.8) initial[node.id] = { status: 'offline' };
      else initial[node.id] = { status: 'hidden' };
    });
    return initial;
  });

  const [joiningNodes, setJoiningNodes] = useState<Set<number>>(new Set());

  // Sync stats to context
  const networkContext = useNetworkContext();

  useEffect(() => {
    const interval = setInterval(() => {
      const activeCount = Object.values(nodeLifecycle).filter(l => l.status === 'active').length;
      const glowingCount = glowingNodesRef.current.size;

      networkContext.updateStats({
        nodesOnline: activeCount,
        activeBuilds: glowingCount,
      });
    }, 100);

    return () => clearInterval(interval);
  }, [nodeLifecycle, networkContext]);

  // Check if removing a node would create orphans
  const checkForOrphans = useCallback((lifecycle: Record<number, NodeState>, nodeIdToRemove: number) => {
    const activeNodes = nodeData.filter(n =>
      lifecycle[n.id]?.status === 'active' && n.id !== nodeIdToRemove
    );

    if (activeNodes.length === 0) return false;

    // Simulate connections without the node being removed
    const connectionCounts = new Map<number, number>();
    const maxConnections = 4;
    const connectionDistance = 10;

    for (let i = 0; i < activeNodes.length; i++) {
      for (let j = i + 1; j < activeNodes.length; j++) {
        const a = activeNodes[i];
        const b = activeNodes[j];

        const aCount = connectionCounts.get(a.id) ?? 0;
        const bCount = connectionCounts.get(b.id) ?? 0;
        if (aCount >= maxConnections || bCount >= maxConnections) continue;

        const dx = a.position[0] - b.position[0];
        const dy = a.position[1] - b.position[1];
        const dz = a.position[2] - b.position[2];
        const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);

        if (dist < connectionDistance) {
          connectionCounts.set(a.id, aCount + 1);
          connectionCounts.set(b.id, bCount + 1);
        }
      }
    }

    // Check if any active node would have 0 connections
    return activeNodes.some(node => (connectionCounts.get(node.id) ?? 0) === 0);
  }, [nodeData]);

  // Lifecycle Tick - Create/Destroy nodes dynamically
  useEffect(() => {
    const tickInterval = setInterval(() => {
      const rand = Math.random();

      // Create new node
      if (rand < appearanceRate / 100) {
        const newId = nextNodeId.current++;

        setNodeData(prev => {
          const newNode = generateNodePosition(newId, prev);

          // Update lifecycle state
          setNodeLifecycle(lifecycle => ({
            ...lifecycle,
            [newId]: { status: 'active' }
          }));

          return [...prev, newNode];
        });

        setJoiningNodes(current => new Set(current).add(newId));
        setTimeout(() => {
          setJoiningNodes(current => {
            const updated = new Set(current);
            updated.delete(newId);
            return updated;
          });
        }, 1200);
      }

      // Delete node entirely
      if (Math.random() < disappearanceRate / 100) {
        // Use ref to coordinate state updates
        let nodeToDelete: number | null = null;

        setNodeLifecycle(currentLifecycle => {
          const activeNodeIds = Object.keys(currentLifecycle).map(Number).filter(id => currentLifecycle[id]?.status === 'active');
          if (activeNodeIds.length <= 5) return currentLifecycle;

          const candidate = activeNodeIds[Math.floor(Math.random() * activeNodeIds.length)];

          // Check if removing this node would create orphans
          if (checkForOrphans(currentLifecycle, candidate)) {
            return currentLifecycle; // Would create orphans, abort
          }

          // Mark for deletion
          nodeToDelete = candidate;
          glowingNodesRef.current.delete(candidate);

          const updated = { ...currentLifecycle };
          delete updated[candidate];
          return updated;
        });

        // Delete from nodeData if we successfully removed from lifecycle
        if (nodeToDelete !== null) {
          const idToDelete = nodeToDelete;
          setNodeData(prev => prev.filter(n => n.id !== idToDelete));
        }
      }

      // Toggle offline/online occasionally
      if (Math.random() < 0.02) {
        setNodeLifecycle(prev => {
          const activeNodes = Object.keys(prev).map(Number).filter(id => prev[id].status === 'active');
          if (activeNodes.length > 5) {
            const id = activeNodes[Math.floor(Math.random() * activeNodes.length)];

            if (!checkForOrphans(prev, id)) {
              const next = { ...prev };
              next[id] = { status: 'offline' };
              glowingNodesRef.current.delete(id);
              return next;
            }
          }
          return prev;
        });
      }

      // Bring offline nodes back online
      if (Math.random() < 0.03) {
        setNodeLifecycle(prev => {
          const offlineNodes = Object.keys(prev).map(Number).filter(id => prev[id].status === 'offline');
          if (offlineNodes.length > 0) {
            const id = offlineNodes[Math.floor(Math.random() * offlineNodes.length)];
            const next = { ...prev };
            next[id] = { status: 'active' };
            return next;
          }
          return prev;
        });
      }
    }, 100);
    return () => clearInterval(tickInterval);
  }, [checkForOrphans]);

  // Connections Pass: No Orphans Allowed
  const connections = useMemo(() => {
    const conns: Array<{ from: NodeData; to: NodeData }> = [];
    const connectionCounts = new Map<number, number>();
    const maxConnections = 4;
    const connectionDistance = 10;

    const activeNodes = nodeData.filter(n => nodeLifecycle[n.id]?.status === 'active');
    if (activeNodes.length === 0) return [];

    // Pass 1: Distance-based connections
    for (let i = 0; i < activeNodes.length; i++) {
      for (let j = i + 1; j < activeNodes.length; j++) {
        const a = activeNodes[i];
        const b = activeNodes[j];

        const aCount = connectionCounts.get(a.id) ?? 0;
        const bCount = connectionCounts.get(b.id) ?? 0;
        if (aCount >= maxConnections || bCount >= maxConnections) continue;

        const dx = a.position[0] - b.position[0];
        const dy = a.position[1] - b.position[1];
        const dz = a.position[2] - b.position[2];
        const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);

        if (dist < connectionDistance) {
          conns.push({ from: a, to: b });
          connectionCounts.set(a.id, aCount + 1);
          connectionCounts.set(b.id, bCount + 1);
        }
      }
    }

    // Pass 2: Orphan Protection (Hard Rule)
    activeNodes.forEach(node => {
      const count = connectionCounts.get(node.id) ?? 0;
      if (count === 0 && activeNodes.length > 1) {
        // Find nearest active neighbor
        let nearest: NodeData | null = null;
        let minDist = Infinity;

        activeNodes.forEach(other => {
          if (node.id === other.id) return;
          const distSq =
            Math.pow(node.position[0] - other.position[0], 2) +
            Math.pow(node.position[1] - other.position[1], 2) +
            Math.pow(node.position[2] - other.position[2], 2);
          if (distSq < minDist) {
            minDist = distSq;
            nearest = other;
          }
        });

        if (nearest) {
          conns.push({ from: node, to: nearest });
          connectionCounts.set(node.id, 1);
          const nId = (nearest as NodeData).id;
          connectionCounts.set(nId, (connectionCounts.get(nId) ?? 0) + 1);
        }
      }
    });

    return conns;
  }, [nodeData, nodeLifecycle]);

  const handleNodeClick = useCallback((_id: number, pos: [number, number, number]) => {
    // To bring pos to front (towards camera at +Z):
    // We want the group's rotation to be such that POS transformed is at (0, 0, Z)
    // Actually, simple lookAt from (0,0,0) towards pos, then invert it for the group
    const target = new THREE.Vector3(...pos).normalize();
    const currentFront = new THREE.Vector3(0, 0, 1);

    // Quaternion that rotates target to currentFront
    const quat = new THREE.Quaternion().setFromUnitVectors(target, currentFront);
    targetQuaternion.current.copy(quat);
  }, []);

  const handlePulseArrival = useCallback((nodeId: number) => {
    glowingNodesRef.current.set(nodeId, true);
  }, []);

  const handlePulseDeparture = useCallback((nodeId: number) => {
    glowingNodesRef.current.delete(nodeId);
  }, []);

  useFrame(() => {
    // Smoothed Focus Rotation
    currentQuaternion.current.slerp(targetQuaternion.current, 0.05);
    if (rotationGroupRef.current) {
      rotationGroupRef.current.quaternion.copy(currentQuaternion.current);
    }

    // Mouse Parallax
    if (parallaxGroupRef.current) {
      const targetX = pointer.x * 0.4;
      const targetY = pointer.y * 0.2;
      parallaxGroupRef.current.rotation.y += (targetX - parallaxGroupRef.current.rotation.y) * 0.03;
      parallaxGroupRef.current.rotation.x += (-targetY - parallaxGroupRef.current.rotation.x) * 0.03;
    }

    // Scroll-based camera movement
    const targetY = -scrollProgress * 20; // Move down 20 units over scroll
    camera.position.y += (targetY - camera.position.y) * 0.1;
  });

  return (
    <>
      {/* Area light from above */}
      <rectAreaLight
        position={[0, 15, 0]}
        width={3}
        height={3}
        intensity={3}
        rotation={[-Math.PI / 2, 0, 0]}
      />

      <group ref={rotationGroupRef}>
        <group ref={parallaxGroupRef}>
          {nodeData.map((node) => {
            const lifecycle = nodeLifecycle[node.id];
            if (!lifecycle) return null; // Skip nodes without lifecycle (race condition)
            return (
              <MeshNode
                key={node.id}
                node={node}
                glowingNodesRef={glowingNodesRef}
                isOnline={lifecycle.status === 'active'}
                isJoining={joiningNodes.has(node.id)}
                isHidden={lifecycle.status === 'hidden'}
                onClick={handleNodeClick}
              />
            );
          })}

          {connections.map((conn) => (
            <ConnectionLine
              key={`${conn.from.id}-${conn.to.id}`}
              from={conn.from.position}
              to={conn.to.position}
              fromId={conn.from.id}
              toId={conn.to.id}
              index={conn.from.id}
              pulseFrequencyScale={pulseFrequencyScale}
              onPulseArrival={handlePulseArrival}
              onPulseDeparture={handlePulseDeparture}
              isActive={true}
            />
          ))}
        </group>
      </group>
    </>
  );
}
