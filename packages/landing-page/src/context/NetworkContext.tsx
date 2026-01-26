import { createContext, useContext, ReactNode } from 'react';
import { useNetworkStats, NetworkStats } from '../hooks/useNetworkStats';

const NetworkContext = createContext<NetworkStats | null>(null);

export function NetworkProvider({ children }: { children: ReactNode }) {
  const stats = useNetworkStats();

  return (
    <NetworkContext.Provider value={stats}>
      {children}
    </NetworkContext.Provider>
  );
}

export function useNetwork() {
  const context = useContext(NetworkContext);
  if (!context) {
    throw new Error('useNetwork must be used within a NetworkProvider');
  }
  return context;
}
