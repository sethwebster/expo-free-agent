import { useRef, useMemo, useEffect } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';

interface ConnectionLineProps {
  from: [number, number, number];
  to: [number, number, number];
  fromId: number;
  toId: number;
  index: number;
  pulseFrequencyScale?: number;
  onPulseArrival: (nodeId: number) => void;
  onPulseDeparture: (nodeId: number) => void;
  isActive?: boolean;
}

// Easing function
function easeInOutCubic(t: number): number {
  return t < 0.5
    ? 4 * t * t * t
    : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

export function ConnectionLine({
  from,
  to,
  fromId,
  toId,
  index,
  pulseFrequencyScale = 1,
  onPulseArrival,
  onPulseDeparture,
  isActive = true
}: ConnectionLineProps) {
  const lineRef = useRef<THREE.Line>(null);
  const pulseRef = useRef<THREE.Mesh>(null);

  // Use refs for animation state to avoid re-renders
  const pulseState = useRef<{
    progress: number | null;
    direction: 'forward' | 'backward';
    active: boolean;
    departureNodeId: number | null;
  }>({
    progress: null,
    direction: 'forward',
    active: false,
    departureNodeId: null
  });

  // Stable callback refs
  const onPulseArrivalRef = useRef(onPulseArrival);
  onPulseArrivalRef.current = onPulseArrival;
  const onPulseDepartureRef = useRef(onPulseDeparture);
  onPulseDepartureRef.current = onPulseDeparture;

  // Line geometry - create once
  const geometry = useMemo(() => {
    const geo = new THREE.BufferGeometry();
    const positions = new Float32Array([...from, ...to]);
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    return geo;
  }, [from, to]);

  // Material - create once (light for dark background visibility)
  const lineMaterial = useMemo(() => {
    return new THREE.LineBasicMaterial({
      color: '#a5b4fc', // Indigo-300 - visible on dark backgrounds
      transparent: true,
      opacity: 0.5,
    });
  }, []);

  // Pulse material - create once
  const pulseMaterial = useMemo(() => {
    return new THREE.MeshBasicMaterial({
      color: '#a5b4fc',
      transparent: true,
      opacity: 0,
    });
  }, []);

  // Pulse geometry - create once
  const pulseGeometry = useMemo(() => {
    return new THREE.SphereGeometry(0.1, 8, 8);
  }, []);

  // Track active state for line opacity
  const isActiveRef = useRef(isActive);
  isActiveRef.current = isActive;

  // Trigger random pulses - frequency controlled by pulseFrequencyScale
  useEffect(() => {
    const triggerPulse = () => {
      // Don't trigger pulses if connection is inactive
      if (!isActiveRef.current) return;

      if (!pulseState.current.active && Math.random() < 0.4) {
        pulseState.current.progress = 0;
        pulseState.current.direction = Math.random() < 0.5 ? 'forward' : 'backward';
        pulseState.current.active = true;

        // Determine which node the pulse is departing FROM
        const departingNodeId = pulseState.current.direction === 'forward' ? fromId : toId;
        pulseState.current.departureNodeId = departingNodeId;

        // Notify departure - this node stops glowing (it gave up its ball)
        onPulseDepartureRef.current(departingNodeId);
      }
    };

    // Calculate base interval based on frequency scale
    // Higher scale = shorter interval = more frequent pulses
    const baseInterval = 4000 / Math.max(0.2, pulseFrequencyScale);
    const randomVariance = 2000 / Math.max(0.2, pulseFrequencyScale);

    // Staggered initial timing
    const initialDelay = 500 + index * 150 + Math.random() * 1000;
    const timeout = setTimeout(triggerPulse, initialDelay);

    // Interval between pulses
    const interval = setInterval(triggerPulse, baseInterval + Math.random() * randomVariance);

    return () => {
      clearTimeout(timeout);
      clearInterval(interval);
    };
  }, [index, fromId, toId, pulseFrequencyScale]);

  // Animate pulse along line
  useFrame((_, delta) => {
    const state = pulseState.current;

    if (state.active && state.progress !== null && pulseRef.current) {
      const newProgress = state.progress + delta * 1.2; // Slightly faster

      if (newProgress >= 1) {
        // Pulse complete - notify arrival
        const targetId = state.direction === 'forward' ? toId : fromId;
        onPulseArrivalRef.current(targetId);
        state.progress = null;
        state.active = false;
        state.departureNodeId = null;
        pulseMaterial.opacity = 0;
      } else {
        state.progress = newProgress;

        // Ease function for smooth animation
        const eased = easeInOutCubic(newProgress);

        // Direction-aware interpolation
        const startPos = state.direction === 'forward' ? from : to;
        const endPos = state.direction === 'forward' ? to : from;

        // Update position directly on the mesh
        pulseRef.current.position.set(
          startPos[0] + (endPos[0] - startPos[0]) * eased,
          startPos[1] + (endPos[1] - startPos[1]) * eased,
          startPos[2] + (endPos[2] - startPos[2]) * eased
        );

        // Fade in and out
        const opacity = newProgress < 0.1
          ? newProgress * 10
          : newProgress > 0.9
            ? (1 - newProgress) * 10
            : 1;

        pulseMaterial.opacity = opacity * 0.9;
      }
    }
  });

  // Create line object
  const lineObject = useMemo(() => {
    return new THREE.Line(geometry, lineMaterial);
  }, [geometry, lineMaterial]);

  return (
    <>
      <primitive ref={lineRef} object={lineObject} />

      {/* Always render pulse mesh, control visibility via opacity */}
      <mesh
        ref={pulseRef}
        position={from}
        geometry={pulseGeometry}
        material={pulseMaterial}
      />
    </>
  );
}
