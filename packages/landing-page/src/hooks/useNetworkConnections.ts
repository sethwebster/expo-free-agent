import { useState, useEffect, useCallback, useRef } from 'react';
import { useNetworkEngine } from './useNetworkEngine';
import type { Connection, EngineState, EngineEvent } from '../services/meshNetworkEngine';

// ============================================================================
// TYPES
// ============================================================================

export interface ConnectionWithStatus extends Connection {
  isRemoving: boolean;
}

// ============================================================================
// HOOK: useNetworkConnections
// ============================================================================

/**
 * Subscribe to the network engine's connections.
 * Includes both active connections and those being animated out.
 */
export function useNetworkConnections(): {
  connections: ConnectionWithStatus[];
  markRetracted: (key: string) => void;
} {
  const engine = useNetworkEngine();

  // Track connections that are being animated out
  const removingKeysRef = useRef<Set<string>>(new Set());
  // Keep removed connection data for animation
  const removedConnectionsRef = useRef<Map<string, Connection>>(new Map());

  const [connections, setConnections] = useState<ConnectionWithStatus[]>(() => {
    const state = engine.getState();
    return state.connections.map((c) => ({
      ...c,
      isRemoving: state.removingConnectionKeys.has(c.key),
    }));
  });

  useEffect(() => {
    const unsubscribe = engine.subscribe((state: EngineState, event?: EngineEvent) => {
      // Handle connection removal events
      if (event?.type === 'connection-removed') {
        const key = event.payload as string;
        removingKeysRef.current.add(key);

        // Store the connection data for animation
        const existing = state.connections.find((c) => c.key === key);
        if (existing) {
          removedConnectionsRef.current.set(key, existing);
        }
      }

      // Only update on connection-related events
      if (
        !event ||
        event.type === 'connections-changed' ||
        event.type === 'connection-removed'
      ) {
        // Merge active connections with removing ones
        const activeConnections = state.connections;
        const activeKeys = new Set(activeConnections.map((c) => c.key));

        // Build connection list: active + removing (that aren't also active)
        const merged: ConnectionWithStatus[] = [];

        // Add all active connections
        activeConnections.forEach((c) => {
          merged.push({
            ...c,
            isRemoving: state.removingConnectionKeys.has(c.key),
          });
        });

        // Add removing connections that are no longer in active list
        removingKeysRef.current.forEach((key) => {
          if (!activeKeys.has(key)) {
            const cachedConnection = removedConnectionsRef.current.get(key);
            if (cachedConnection) {
              merged.push({
                ...cachedConnection,
                isRemoving: true,
              });
            }
          }
        });

        setConnections(merged);
      }
    });

    return unsubscribe;
  }, [engine]);

  // Callback to mark a connection as fully retracted
  const markRetracted = useCallback(
    (key: string) => {
      removingKeysRef.current.delete(key);
      removedConnectionsRef.current.delete(key);
      engine.markConnectionRetracted(key);
    },
    [engine]
  );

  return { connections, markRetracted };
}

// ============================================================================
// HOOK: useConnectionCount
// ============================================================================

/**
 * Get just the count of active connections.
 */
export function useConnectionCount(): number {
  const engine = useNetworkEngine();
  const [count, setCount] = useState(() => engine.getState().connections.length);
  const prevCountRef = useRef(count);

  useEffect(() => {
    const unsubscribe = engine.subscribe((state: EngineState, event?: EngineEvent) => {
      if (!event || event.type === 'connections-changed') {
        const newCount = state.connections.length;
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
