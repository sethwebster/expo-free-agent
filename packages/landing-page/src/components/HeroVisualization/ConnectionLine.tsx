import { useRef, useMemo, useEffect, useState } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import {
  ANIM_SPEED,
  GEOMETRY,
  COLORS,
  tempVec3A,
  tempQuat,
  Y_AXIS,
} from './constants';
import { getGeometry, acquirePool, releasePool } from './geometryPool';
import { createEmissiveMaterial, disposeMaterial } from './materialPool';

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
  isRemoving?: boolean;
  onRetractComplete?: () => void;
}

function easeInOutCubic(t: number): number {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

/**
 * Update tube mesh transform using scale instead of recreating geometry.
 * Uses a unit cylinder (radius=1, height=1) and scales it to desired dimensions.
 */
function updateTubeTransform(
  mesh: THREE.Mesh | null,
  start: [number, number, number],
  end: [number, number, number],
  radius: number
): void {
  if (!mesh) return;

  // Calculate direction and length
  tempVec3A.set(end[0] - start[0], end[1] - start[1], end[2] - start[2]);
  const length = tempVec3A.length();

  if (length < 0.001) {
    mesh.scale.set(0, 0, 0);
    return;
  }

  // Scale: X and Z for radius, Y for length
  mesh.scale.set(radius, length, radius);

  // Position at midpoint
  mesh.position.set(
    (start[0] + end[0]) / 2,
    (start[1] + end[1]) / 2,
    (start[2] + end[2]) / 2
  );

  // Rotate to align with direction
  tempVec3A.normalize();
  tempQuat.setFromUnitVectors(Y_AXIS, tempVec3A);
  mesh.quaternion.copy(tempQuat);
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
  isActive = true,
  isRemoving = false,
  onRetractComplete,
}: ConnectionLineProps) {
  const pulseRef = useRef<THREE.Mesh>(null);

  // Lightsaber extend/retract animation state
  const extendProgress = useRef(0);
  const [isExtending, setIsExtending] = useState(true);
  const [isRetracting, setIsRetracting] = useState(false);

  // Connection flash effect at both ends
  const flashRefFrom = useRef<THREE.Mesh>(null);
  const flashRefTo = useRef<THREE.Mesh>(null);
  const flashProgress = useRef(0);
  const flashActive = useRef(false);

  // Animation state refs (avoid re-renders)
  const pulseState = useRef<{
    progress: number | null;
    direction: 'forward' | 'backward';
    active: boolean;
    departureNodeId: number | null;
  }>({
    progress: null,
    direction: 'forward',
    active: false,
    departureNodeId: null,
  });

  // Stable callback refs
  const onPulseArrivalRef = useRef(onPulseArrival);
  onPulseArrivalRef.current = onPulseArrival;
  const onPulseDepartureRef = useRef(onPulseDeparture);
  onPulseDepartureRef.current = onPulseDeparture;

  // Tube refs
  const innerTubeRef = useRef<THREE.Mesh>(null);
  const outerTubeRef = useRef<THREE.Mesh>(null);

  // Acquire geometry pool reference on mount
  useEffect(() => {
    acquirePool();
    return () => releasePool();
  }, []);

  // Get shared unit cylinder geometry from pool (scaled for each tube)
  const unitCylinderGeometry = useMemo(() => getGeometry('cylinderUnit'), []);

  // Get shared sphere geometries from pool
  const pulseGeometry = useMemo(() => getGeometry('sphereSmall'), []);
  const flashGeometry = useMemo(() => getGeometry('sphereMedium'), []);

  // Create materials (per-instance since they animate independently)
  const innerTubeMaterial = useMemo(
    () => createEmissiveMaterial(COLORS.WHITE, false),
    []
  );
  const outerTubeMaterial = useMemo(
    () => createEmissiveMaterial(COLORS.INDIGO, false),
    []
  );
  const pulseMaterial = useMemo(
    () => createEmissiveMaterial(COLORS.WHITE),
    []
  );
  const flashMaterialFrom = useMemo(
    () => createEmissiveMaterial(COLORS.WHITE),
    []
  );
  const flashMaterialTo = useMemo(
    () => createEmissiveMaterial(COLORS.WHITE),
    []
  );

  // Track active state for line opacity
  const isActiveRef = useRef(isActive);
  isActiveRef.current = isActive;

  // Dispose materials on unmount
  useEffect(() => {
    return () => {
      disposeMaterial(innerTubeMaterial);
      disposeMaterial(outerTubeMaterial);
      disposeMaterial(pulseMaterial);
      disposeMaterial(flashMaterialFrom);
      disposeMaterial(flashMaterialTo);
    };
  }, [
    innerTubeMaterial,
    outerTubeMaterial,
    pulseMaterial,
    flashMaterialFrom,
    flashMaterialTo,
  ]);

  // Trigger retract animation when isRemoving becomes true
  useEffect(() => {
    if (isRemoving && !isRetracting) {
      setIsExtending(false);
      setIsRetracting(true);
    }
  }, [isRemoving, isRetracting]);

  // Trigger random pulses
  useEffect(() => {
    const triggerPulse = () => {
      if (!isActiveRef.current) {
        console.log(`[ConnectionLine ${fromId}-${toId}] Pulse skipped - inactive connection`);
        return;
      }

      if (!pulseState.current.active && Math.random() < 0.4) {
        pulseState.current.progress = 0;
        pulseState.current.direction = Math.random() < 0.5 ? 'forward' : 'backward';
        pulseState.current.active = true;

        const departingNodeId =
          pulseState.current.direction === 'forward' ? fromId : toId;
        pulseState.current.departureNodeId = departingNodeId;

        onPulseDepartureRef.current(departingNodeId);
      }
    };

    const baseInterval = 4000 / Math.max(0.2, pulseFrequencyScale);
    const randomVariance = 2000 / Math.max(0.2, pulseFrequencyScale);

    const initialDelay = 500 + index * 150 + Math.random() * 1000;
    const timeout = setTimeout(triggerPulse, initialDelay);

    const interval = setInterval(
      triggerPulse,
      baseInterval + Math.random() * randomVariance
    );

    return () => {
      clearTimeout(timeout);
      clearInterval(interval);
    };
  }, [index, fromId, toId, pulseFrequencyScale]);

  useFrame((_, delta) => {
    // Lightsaber extend animation
    if (isExtending) {
      extendProgress.current = Math.min(
        1,
        extendProgress.current + delta * ANIM_SPEED.LIGHTSABER
      );

      if (extendProgress.current >= 1) {
        setIsExtending(false);
        flashActive.current = true;
        flashProgress.current = 0;
      }

      const eased = easeInOutCubic(extendProgress.current);

      const currentEnd: [number, number, number] = [
        from[0] + (to[0] - from[0]) * eased,
        from[1] + (to[1] - from[1]) * eased,
        from[2] + (to[2] - from[2]) * eased,
      ];

      updateTubeTransform(
        innerTubeRef.current,
        from,
        currentEnd,
        GEOMETRY.TUBE.INNER_RADIUS
      );
      updateTubeTransform(
        outerTubeRef.current,
        from,
        currentEnd,
        GEOMETRY.TUBE.OUTER_RADIUS
      );

      innerTubeMaterial.opacity = 0.9 * eased;
      outerTubeMaterial.opacity = 0.4 * eased;
    }

    // Connection flash animation
    if (flashActive.current && flashRefFrom.current && flashRefTo.current) {
      if (flashProgress.current === 0) {
        flashRefFrom.current.position.set(from[0], from[1], from[2]);
        flashRefTo.current.position.set(to[0], to[1], to[2]);
        flashMaterialFrom.opacity = 1.0;
        flashMaterialTo.opacity = 1.0;
        flashRefFrom.current.scale.setScalar(1);
        flashRefTo.current.scale.setScalar(1);
        flashProgress.current += 1;
      } else if (flashProgress.current === 1) {
        flashMaterialFrom.opacity = 0;
        flashMaterialTo.opacity = 0;
        flashProgress.current += 1;
      } else {
        flashActive.current = false;
        flashMaterialFrom.opacity = 0;
        flashMaterialTo.opacity = 0;
      }
    }

    // Lightsaber retract animation
    if (isRetracting) {
      extendProgress.current = Math.max(
        0,
        extendProgress.current - delta * ANIM_SPEED.LIGHTSABER
      );

      if (extendProgress.current <= 0) {
        setIsRetracting(false);
        onRetractComplete?.();
      }

      const eased = easeInOutCubic(extendProgress.current);

      const currentEnd: [number, number, number] = [
        from[0] + (to[0] - from[0]) * eased,
        from[1] + (to[1] - from[1]) * eased,
        from[2] + (to[2] - from[2]) * eased,
      ];

      updateTubeTransform(
        innerTubeRef.current,
        from,
        currentEnd,
        GEOMETRY.TUBE.INNER_RADIUS
      );
      updateTubeTransform(
        outerTubeRef.current,
        from,
        currentEnd,
        GEOMETRY.TUBE.OUTER_RADIUS
      );

      innerTubeMaterial.opacity = 0.9 * eased;
      outerTubeMaterial.opacity = 0.4 * eased;
    }

    // Pulse animation
    const state = pulseState.current;

    if (state.active && state.progress !== null && pulseRef.current) {
      const newProgress = state.progress + delta * ANIM_SPEED.PULSE;

      if (newProgress >= 1) {
        const targetId = state.direction === 'forward' ? toId : fromId;
        onPulseArrivalRef.current(targetId);
        state.progress = null;
        state.active = false;
        state.departureNodeId = null;
        pulseMaterial.opacity = 0;
      } else {
        state.progress = newProgress;

        const eased = easeInOutCubic(newProgress);

        const startPos = state.direction === 'forward' ? from : to;
        const endPos = state.direction === 'forward' ? to : from;

        pulseRef.current.position.set(
          startPos[0] + (endPos[0] - startPos[0]) * eased,
          startPos[1] + (endPos[1] - startPos[1]) * eased,
          startPos[2] + (endPos[2] - startPos[2]) * eased
        );

        const opacity =
          newProgress < 0.1
            ? newProgress * 10
            : newProgress > 0.9
              ? (1 - newProgress) * 10
              : 1;

        pulseMaterial.opacity = opacity * 0.9;
      }
    }
  });

  return (
    <>
      {/* Hot inner core tube - uses unit cylinder scaled */}
      <mesh
        ref={innerTubeRef}
        geometry={unitCylinderGeometry}
        material={innerTubeMaterial}
      />

      {/* Soft outer glow tube - uses unit cylinder scaled */}
      <mesh
        ref={outerTubeRef}
        geometry={unitCylinderGeometry}
        material={outerTubeMaterial}
      />

      {/* Pulse mesh - always rendered, visibility via opacity */}
      <mesh
        ref={pulseRef}
        position={from}
        geometry={pulseGeometry}
        material={pulseMaterial}
      />

      {/* Connection flash effect at both ends */}
      <mesh
        ref={flashRefFrom}
        position={from}
        geometry={flashGeometry}
        material={flashMaterialFrom}
      />
      <mesh
        ref={flashRefTo}
        position={to}
        geometry={flashGeometry}
        material={flashMaterialTo}
      />
    </>
  );
}
