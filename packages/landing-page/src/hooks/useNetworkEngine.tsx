import { createContext, useContext, useRef, useEffect, ReactNode } from 'react';
import {
  MeshNetworkEngine,
  getMeshNetworkEngine,
  disposeMeshNetworkEngine,
} from '../services/meshNetworkEngine';
import {
  NetworkSyncService,
  getNetworkSyncService,
  disposeNetworkSyncService,
} from '../services/networkSync';

// ============================================================================
// CONTEXT
// ============================================================================

interface NetworkEngineContextValue {
  engine: MeshNetworkEngine;
  syncService: NetworkSyncService;
}

const NetworkEngineContext = createContext<NetworkEngineContextValue | null>(null);

// ============================================================================
// PROVIDER
// ============================================================================

interface NetworkEngineProviderProps {
  children: ReactNode;
  initialNodeCount?: number;
  appearanceRate?: number;
  disappearanceRate?: number;
}

export function NetworkEngineProvider({
  children,
  initialNodeCount = 18,
  appearanceRate = 10,
  disappearanceRate = 5,
}: NetworkEngineProviderProps) {
  const engineRef = useRef<MeshNetworkEngine | null>(null);
  const syncRef = useRef<NetworkSyncService | null>(null);
  const initializedRef = useRef(false);

  // Initialize engine only once
  if (!initializedRef.current) {
    const engine = getMeshNetworkEngine();
    engine.updateConfig({ appearanceRate, disappearanceRate });
    engine.initialize(initialNodeCount);

    const sync = getNetworkSyncService(engine);

    engineRef.current = engine;
    syncRef.current = sync;
    initializedRef.current = true;
  }

  // Start/stop lifecycle
  useEffect(() => {
    const engine = engineRef.current;
    const sync = syncRef.current;

    if (engine && sync) {
      engine.start();
      sync.start();

      // Sync engine stats to sync service on engine changes
      const unsubscribe = engine.subscribe(() => {
        sync.updateFromEngine();
      });

      return () => {
        unsubscribe();
        engine.stop();
        sync.stop();
      };
    }
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      disposeMeshNetworkEngine();
      disposeNetworkSyncService();
    };
  }, []);

  // Update config when props change
  useEffect(() => {
    if (engineRef.current) {
      engineRef.current.updateConfig({ appearanceRate, disappearanceRate });
    }
  }, [appearanceRate, disappearanceRate]);

  if (!engineRef.current || !syncRef.current) {
    return null;
  }

  return (
    <NetworkEngineContext.Provider
      value={{ engine: engineRef.current, syncService: syncRef.current }}
    >
      {children}
    </NetworkEngineContext.Provider>
  );
}

// ============================================================================
// HOOK
// ============================================================================

export function useNetworkEngine(): MeshNetworkEngine {
  const context = useContext(NetworkEngineContext);
  if (!context) {
    throw new Error('useNetworkEngine must be used within NetworkEngineProvider');
  }
  return context.engine;
}

export function useNetworkSyncService(): NetworkSyncService {
  const context = useContext(NetworkEngineContext);
  if (!context) {
    throw new Error('useNetworkSyncService must be used within NetworkEngineProvider');
  }
  return context.syncService;
}
