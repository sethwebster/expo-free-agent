import { useState, useEffect, useRef, useCallback } from 'react';
import { useNetworkEngine } from './useNetworkEngine';
import type { NodeState, EngineState, EngineEvent } from '../services/meshNetworkEngine';

// ============================================================================
// HOOK: useNetworkNodes
// ============================================================================

/**
 * Subscribe to the network engine's nodes array.
 * Only re-renders when nodes change.
 */
export function useNetworkNodes(): NodeState[] {
  const engine = useNetworkEngine();
  const [nodes, setNodes] = useState<NodeState[]>(() => engine.getState().nodes);

  useEffect(() => {
    const unsubscribe = engine.subscribe((state: EngineState, event?: EngineEvent) => {
      // Only update on node-related events
      if (
        !event ||
        event.type === 'nodes-changed' ||
        event.type === 'node-added' ||
        event.type === 'node-removed'
      ) {
        setNodes(state.nodes);
      }
    });

    return unsubscribe;
  }, [engine]);

  return nodes;
}

// ============================================================================
// HOOK: useNodeLifecycle
// ============================================================================

interface NodeLifecycleState {
  joiningNodeIds: Set<number>;
}

/**
 * Subscribe to node lifecycle events (joining animations).
 */
export function useNodeLifecycle(): NodeLifecycleState {
  const engine = useNetworkEngine();
  const [state, setState] = useState<NodeLifecycleState>(() => {
    const nodes = engine.getState().nodes;
    return {
      joiningNodeIds: new Set(nodes.filter((n) => n.isJoining).map((n) => n.id)),
    };
  });

  useEffect(() => {
    const unsubscribe = engine.subscribe((engineState: EngineState) => {
      setState({
        joiningNodeIds: new Set(
          engineState.nodes.filter((n) => n.isJoining).map((n) => n.id)
        ),
      });
    });

    return unsubscribe;
  }, [engine]);

  return state;
}

// ============================================================================
// HOOK: useNodeById
// ============================================================================

/**
 * Get a specific node by ID with automatic updates.
 */
export function useNodeById(id: number): NodeState | undefined {
  const engine = useNetworkEngine();
  const [node, setNode] = useState<NodeState | undefined>(() => engine.getNode(id));

  useEffect(() => {
    const unsubscribe = engine.subscribe((state: EngineState) => {
      const found = state.nodes.find((n) => n.id === id);
      setNode(found);
    });

    return unsubscribe;
  }, [engine, id]);

  return node;
}

// ============================================================================
// HOOK: useNodeStatus
// ============================================================================

/**
 * Get just the status of a node without full state updates.
 * Uses ref comparison to minimize re-renders.
 */
export function useNodeStatus(id: number): { status: string; isJoining: boolean } | null {
  const engine = useNetworkEngine();
  const [status, setStatus] = useState<{ status: string; isJoining: boolean } | null>(
    () => {
      const node = engine.getNode(id);
      return node ? { status: node.status, isJoining: node.isJoining } : null;
    }
  );

  const prevStatusRef = useRef(status);

  useEffect(() => {
    const unsubscribe = engine.subscribe((state: EngineState) => {
      const node = state.nodes.find((n) => n.id === id);
      const newStatus = node
        ? { status: node.status, isJoining: node.isJoining }
        : null;

      // Only update if status actually changed
      if (
        !prevStatusRef.current ||
        !newStatus ||
        prevStatusRef.current.status !== newStatus.status ||
        prevStatusRef.current.isJoining !== newStatus.isJoining
      ) {
        prevStatusRef.current = newStatus;
        setStatus(newStatus);
      }
    });

    return unsubscribe;
  }, [engine, id]);

  return status;
}

// ============================================================================
// HOOK: useActiveNodeCount
// ============================================================================

/**
 * Get just the count of active nodes.
 * More efficient than subscribing to full node array.
 */
export function useActiveNodeCount(): number {
  const engine = useNetworkEngine();
  const [count, setCount] = useState(() => engine.getActiveNodeCount());
  const prevCountRef = useRef(count);

  useEffect(() => {
    const unsubscribe = engine.subscribe(() => {
      const newCount = engine.getActiveNodeCount();
      if (newCount !== prevCountRef.current) {
        prevCountRef.current = newCount;
        setCount(newCount);
      }
    });

    return unsubscribe;
  }, [engine]);

  return count;
}

// ============================================================================
// HOOK: useNodeClickHandler
// ============================================================================

/**
 * Returns a stable click handler for focusing on nodes.
 * Doesn't cause re-renders.
 */
export function useNodeClickHandler(): (
  id: number,
  position: [number, number, number]
) => void {
  // This is a pure function that doesn't need state
  // Consumers can use this to track focus externally
  return useCallback((_id: number, _position: [number, number, number]) => {
    // No-op for now - consumers can wrap this if they need focus behavior
  }, []);
}
