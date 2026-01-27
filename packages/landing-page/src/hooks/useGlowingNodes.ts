import { useState, useEffect, useCallback, useRef, MutableRefObject } from 'react';
import { useNetworkEngine } from './useNetworkEngine';
import type { EngineState, EngineEvent } from '../services/meshNetworkEngine';

// ============================================================================
// HOOK: useGlowingNodes
// ============================================================================

/**
 * Subscribe to the set of glowing node IDs (active builds).
 */
export function useGlowingNodes(): Set<number> {
  const engine = useNetworkEngine();
  const [glowingIds, setGlowingIds] = useState<Set<number>>(
    () => new Set(engine.getState().glowingNodeIds)
  );

  useEffect(() => {
    const unsubscribe = engine.subscribe((state: EngineState, event?: EngineEvent) => {
      if (!event || event.type === 'glowing-changed') {
        setGlowingIds(new Set(state.glowingNodeIds));
      }
    });

    return unsubscribe;
  }, [engine]);

  return glowingIds;
}

// ============================================================================
// HOOK: useGlowingNodesRef
// ============================================================================

/**
 * Returns a mutable ref to glowing node IDs.
 * This avoids React re-renders and is ideal for animation loops.
 */
export function useGlowingNodesRef(): MutableRefObject<Map<number, boolean>> {
  const engine = useNetworkEngine();
  const mapRef = useRef<Map<number, boolean>>(new Map());

  useEffect(() => {
    // Initialize
    const state = engine.getState();
    mapRef.current.clear();
    state.glowingNodeIds.forEach((id) => {
      mapRef.current.set(id, true);
    });

    const unsubscribe = engine.subscribe((state: EngineState, event?: EngineEvent) => {
      if (!event || event.type === 'glowing-changed') {
        mapRef.current.clear();
        state.glowingNodeIds.forEach((id) => {
          mapRef.current.set(id, true);
        });
      }
    });

    return unsubscribe;
  }, [engine]);

  return mapRef;
}

// ============================================================================
// HOOK: useIsNodeGlowing
// ============================================================================

/**
 * Check if a specific node is glowing.
 */
export function useIsNodeGlowing(nodeId: number): boolean {
  const engine = useNetworkEngine();
  const [isGlowing, setIsGlowing] = useState(() =>
    engine.getState().glowingNodeIds.has(nodeId)
  );

  const prevGlowingRef = useRef(isGlowing);

  useEffect(() => {
    const unsubscribe = engine.subscribe((state: EngineState, event?: EngineEvent) => {
      if (!event || event.type === 'glowing-changed') {
        const nowGlowing = state.glowingNodeIds.has(nodeId);
        if (nowGlowing !== prevGlowingRef.current) {
          prevGlowingRef.current = nowGlowing;
          setIsGlowing(nowGlowing);
        }
      }
    });

    return unsubscribe;
  }, [engine, nodeId]);

  return isGlowing;
}

// ============================================================================
// HOOK: useGlowingNodeCount
// ============================================================================

/**
 * Get just the count of glowing nodes.
 */
export function useGlowingNodeCount(): number {
  const engine = useNetworkEngine();
  const [count, setCount] = useState(() => engine.getState().glowingNodeIds.size);
  const prevCountRef = useRef(count);

  useEffect(() => {
    const unsubscribe = engine.subscribe((state: EngineState, event?: EngineEvent) => {
      if (!event || event.type === 'glowing-changed') {
        const newCount = state.glowingNodeIds.size;
        if (newCount !== prevCountRef.current) {
          prevCountRef.current = newCount;
          setCount(newCount);
        }
      }
    });

    return unsubscribe;
  }, [engine]);

  return count;
}

// ============================================================================
// HOOK: usePulseHandlers
// ============================================================================

/**
 * Returns stable callbacks for pulse arrival/departure.
 * These trigger the glow effect on nodes.
 */
export function usePulseHandlers(): {
  onPulseArrival: (nodeId: number) => void;
  onPulseDeparture: (nodeId: number) => void;
} {
  const engine = useNetworkEngine();

  const onPulseArrival = useCallback(
    (nodeId: number) => {
      engine.setNodeGlowing(nodeId, true);
    },
    [engine]
  );

  const onPulseDeparture = useCallback(
    (nodeId: number) => {
      engine.setNodeGlowing(nodeId, false);
    },
    [engine]
  );

  return { onPulseArrival, onPulseDeparture };
}
