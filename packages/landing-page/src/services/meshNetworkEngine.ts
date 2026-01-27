import { MESH_CONFIG, tempVec3A } from '../components/HeroVisualization/constants';

// ============================================================================
// TYPES
// ============================================================================

export type NodeStatus = 'hidden' | 'offline' | 'active';

export interface NodeState {
  id: number;
  position: [number, number, number];
  scale: number;
  rotationSpeed: number;
  driftOffset: number;
  status: NodeStatus;
  isJoining: boolean;
}

export interface Connection {
  fromId: number;
  toId: number;
  key: string;
  from: [number, number, number];
  to: [number, number, number];
}

export interface EngineState {
  nodes: NodeState[];
  connections: Connection[];
  glowingNodeIds: Set<number>;
  removingConnectionKeys: Set<string>;
}

export type EngineEventType =
  | 'nodes-changed'
  | 'connections-changed'
  | 'glowing-changed'
  | 'node-added'
  | 'node-removed'
  | 'connection-removed';

export interface EngineEvent {
  type: EngineEventType;
  payload?: unknown;
}

export type EngineSubscriber = (state: EngineState, event?: EngineEvent) => void;

// ============================================================================
// ENGINE CONFIGURATION
// ============================================================================

interface EngineConfig {
  maxNodes: number;
  minNodes: number;
  appearanceRate: number;    // 0-100 probability per tick
  disappearanceRate: number; // 0-100 probability per tick
  offlineToggleRate: number; // 0-100 probability per tick
  onlineRestoreRate: number; // 0-100 probability per tick
  tickIntervalMs: number;
  joiningDurationMs: number;
}

const DEFAULT_CONFIG: EngineConfig = {
  maxNodes: 80,
  minNodes: 5,
  appearanceRate: 10,
  disappearanceRate: 5,
  offlineToggleRate: 2,
  onlineRestoreRate: 3,
  tickIntervalMs: 100,
  joiningDurationMs: 1200,
};

// ============================================================================
// POSITION GENERATION
// ============================================================================

function generateNodePosition(
  id: number,
  existingNodes: NodeState[]
): Omit<NodeState, 'status' | 'isJoining'> {
  const { BOUNDS, MIN_NODE_DISTANCE } = MESH_CONFIG;
  const maxAttempts = 50;

  let attempts = 0;
  let x: number, y: number, z: number;
  let validPosition = false;

  do {
    x = (Math.random() - 0.5) * BOUNDS.X_SPREAD;
    y = (Math.random() - 0.5) * BOUNDS.Y_SPREAD;
    z = BOUNDS.Z_MIN + Math.random() * (BOUNDS.Z_MAX - BOUNDS.Z_MIN);

    validPosition = existingNodes.every((node) => {
      tempVec3A.set(
        x - node.position[0],
        y - node.position[1],
        z - node.position[2]
      );
      return tempVec3A.length() >= MIN_NODE_DISTANCE;
    });

    attempts++;
  } while (!validPosition && attempts < maxAttempts);

  const depthFactor = (z - BOUNDS.Z_MIN) / (BOUNDS.Z_MAX - BOUNDS.Z_MIN);
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

function generateInitialNodes(count: number): NodeState[] {
  const nodes: NodeState[] = [];
  const { BOUNDS, GRID, MIN_NODE_DISTANCE } = MESH_CONFIG;

  for (let i = 0; i < count; i++) {
    let x: number, y: number, z: number;
    let validPosition = false;
    let attempts = 0;
    const maxAttempts = 100;

    do {
      if (i < GRID.COLS * GRID.ROWS) {
        const col = i % GRID.COLS;
        const row = Math.floor(i / GRID.COLS);
        const cellWidth = BOUNDS.X_SPREAD / GRID.COLS;
        const cellHeight = BOUNDS.Y_SPREAD / GRID.ROWS;
        const jitterX = (Math.random() - 0.5) * cellWidth * 0.8;
        const jitterY = (Math.random() - 0.5) * cellHeight * 0.8;

        x = -BOUNDS.X_SPREAD / 2 + cellWidth * (col + 0.5) + jitterX;
        y = -BOUNDS.Y_SPREAD / 2 + cellHeight * (row + 0.5) + jitterY;
        z = BOUNDS.Z_MIN + Math.random() * (BOUNDS.Z_MAX - BOUNDS.Z_MIN);
      } else {
        x = (Math.random() - 0.5) * BOUNDS.X_SPREAD;
        y = (Math.random() - 0.5) * BOUNDS.Y_SPREAD;
        z = BOUNDS.Z_MIN + Math.random() * (BOUNDS.Z_MAX - BOUNDS.Z_MIN);
      }

      validPosition = nodes.every((node) => {
        const dx = x - node.position[0];
        const dy = y - node.position[1];
        const dz = z - node.position[2];
        return Math.sqrt(dx * dx + dy * dy + dz * dz) >= MIN_NODE_DISTANCE;
      });

      attempts++;
    } while (!validPosition && attempts < maxAttempts);

    if (validPosition || nodes.length === 0) {
      const depthFactor =
        (z - BOUNDS.Z_MIN) / (BOUNDS.Z_MAX - BOUNDS.Z_MIN);
      const baseScale = 0.5 + depthFactor * 0.4;
      const scaleVariation = (Math.random() - 0.5) * 0.3;

      // Randomize initial status
      const rand = Math.random();
      let status: NodeStatus;
      if (rand < 0.6) status = 'active';
      else if (rand < 0.8) status = 'offline';
      else status = 'hidden';

      nodes.push({
        id: i,
        position: [x, y, z],
        scale: Math.max(0.3, baseScale + scaleVariation),
        rotationSpeed: 0.1 + Math.random() * 0.3,
        driftOffset: Math.random() * Math.PI * 2,
        status,
        isJoining: false,
      });
    }
  }

  return nodes;
}

// ============================================================================
// MESH NETWORK ENGINE
// ============================================================================

export class MeshNetworkEngine {
  private nodes: Map<number, NodeState> = new Map();
  private connections: Map<string, Connection> = new Map();
  private glowingNodeIds: Set<number> = new Set();
  private removingConnectionKeys: Set<string> = new Set();
  private subscribers: Set<EngineSubscriber> = new Set();
  private nextNodeId = 0;
  private tickInterval: ReturnType<typeof setInterval> | null = null;
  private config: EngineConfig;
  private isRunning = false;

  constructor(config: Partial<EngineConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  // --------------------------------------------------------------------------
  // INITIALIZATION
  // --------------------------------------------------------------------------

  initialize(initialNodeCount: number): void {
    const initialNodes = generateInitialNodes(initialNodeCount);
    initialNodes.forEach((node) => {
      this.nodes.set(node.id, node);
      if (node.id >= this.nextNodeId) {
        this.nextNodeId = node.id + 1;
      }
    });
    this.recalculateConnections();
    this.emit({ type: 'nodes-changed' });
    this.emit({ type: 'connections-changed' });
  }

  // --------------------------------------------------------------------------
  // LIFECYCLE
  // --------------------------------------------------------------------------

  start(): void {
    if (this.isRunning) return;
    this.isRunning = true;

    this.tickInterval = setInterval(() => {
      this.tick();
    }, this.config.tickIntervalMs);
  }

  stop(): void {
    if (!this.isRunning) return;
    this.isRunning = false;

    if (this.tickInterval) {
      clearInterval(this.tickInterval);
      this.tickInterval = null;
    }
  }

  dispose(): void {
    this.stop();
    this.nodes.clear();
    this.connections.clear();
    this.glowingNodeIds.clear();
    this.removingConnectionKeys.clear();
    this.subscribers.clear();
  }

  // --------------------------------------------------------------------------
  // CONFIGURATION
  // --------------------------------------------------------------------------

  updateConfig(config: Partial<EngineConfig>): void {
    this.config = { ...this.config, ...config };
  }

  getConfig(): Readonly<EngineConfig> {
    return { ...this.config };
  }

  // --------------------------------------------------------------------------
  // TICK (LIFECYCLE SIMULATION)
  // --------------------------------------------------------------------------

  private tick(): void {
    let nodesChanged = false;
    let connectionsNeedRecalc = false;

    // Create new node
    if (Math.random() < this.config.appearanceRate / 100) {
      if (this.nodes.size < this.config.maxNodes) {
        this.addNode();
        nodesChanged = true;
        connectionsNeedRecalc = true;
      }
    }

    // Remove node
    if (Math.random() < this.config.disappearanceRate / 100) {
      const removed = this.removeRandomNode();
      if (removed) {
        nodesChanged = true;
        connectionsNeedRecalc = true;
      }
    }

    // Toggle offline
    if (Math.random() < this.config.offlineToggleRate / 100) {
      const toggled = this.toggleRandomNodeOffline();
      if (toggled) {
        nodesChanged = true;
        connectionsNeedRecalc = true;
      }
    }

    // Restore online
    if (Math.random() < this.config.onlineRestoreRate / 100) {
      const restored = this.restoreRandomOfflineNode();
      if (restored) {
        nodesChanged = true;
        connectionsNeedRecalc = true;
      }
    }

    if (connectionsNeedRecalc) {
      this.recalculateConnections();
    }

    if (nodesChanged) {
      this.emit({ type: 'nodes-changed' });
    }
    if (connectionsNeedRecalc) {
      this.emit({ type: 'connections-changed' });
    }
  }

  // --------------------------------------------------------------------------
  // NODE OPERATIONS
  // --------------------------------------------------------------------------

  addNode(): NodeState | null {
    if (this.nodes.size >= this.config.maxNodes) return null;

    const existingNodes = Array.from(this.nodes.values());
    const nodeBase = generateNodePosition(this.nextNodeId, existingNodes);

    const node: NodeState = {
      ...nodeBase,
      status: 'active',
      isJoining: true,
    };

    this.nodes.set(node.id, node);
    this.nextNodeId++;

    // Clear joining flag after duration
    setTimeout(() => {
      const n = this.nodes.get(node.id);
      if (n) {
        n.isJoining = false;
        this.emit({ type: 'nodes-changed' });
      }
    }, this.config.joiningDurationMs);

    this.emit({ type: 'node-added', payload: node });
    return node;
  }

  removeNode(id: number): boolean {
    const node = this.nodes.get(id);
    if (!node) return false;

    // Check for orphans before removal
    if (this.wouldCreateOrphan(id)) return false;

    this.glowingNodeIds.delete(id);
    this.nodes.delete(id);
    this.emit({ type: 'node-removed', payload: id });
    return true;
  }

  private removeRandomNode(): boolean {
    const activeNodes = Array.from(this.nodes.values()).filter(
      (n) => n.status === 'active'
    );

    if (activeNodes.length <= this.config.minNodes) return false;

    const candidate = activeNodes[Math.floor(Math.random() * activeNodes.length)];
    return this.removeNode(candidate.id);
  }

  private toggleRandomNodeOffline(): boolean {
    const activeNodes = Array.from(this.nodes.values()).filter(
      (n) => n.status === 'active'
    );

    if (activeNodes.length <= this.config.minNodes) return false;

    const candidate = activeNodes[Math.floor(Math.random() * activeNodes.length)];

    if (this.wouldCreateOrphan(candidate.id)) return false;

    candidate.status = 'offline';
    this.glowingNodeIds.delete(candidate.id);
    return true;
  }

  private restoreRandomOfflineNode(): boolean {
    const offlineNodes = Array.from(this.nodes.values()).filter(
      (n) => n.status === 'offline'
    );

    if (offlineNodes.length === 0) return false;

    const candidate = offlineNodes[Math.floor(Math.random() * offlineNodes.length)];
    candidate.status = 'active';
    return true;
  }

  updateNodeStatus(id: number, status: NodeStatus): boolean {
    const node = this.nodes.get(id);
    if (!node) return false;

    if (status !== 'active') {
      this.glowingNodeIds.delete(id);
    }

    node.status = status;
    this.emit({ type: 'nodes-changed' });
    return true;
  }

  // --------------------------------------------------------------------------
  // GLOWING NODES (ACTIVE BUILDS)
  // --------------------------------------------------------------------------

  setNodeGlowing(id: number, glowing: boolean): void {
    const node = this.nodes.get(id);
    if (!node || node.status !== 'active') return;

    const changed = glowing
      ? !this.glowingNodeIds.has(id)
      : this.glowingNodeIds.has(id);

    if (glowing) {
      this.glowingNodeIds.add(id);
    } else {
      this.glowingNodeIds.delete(id);
    }

    if (changed) {
      this.emit({ type: 'glowing-changed' });
    }
  }

  isNodeGlowing(id: number): boolean {
    return this.glowingNodeIds.has(id);
  }

  // --------------------------------------------------------------------------
  // CONNECTIONS
  // --------------------------------------------------------------------------

  private recalculateConnections(): void {
    const prevKeys = new Set(this.connections.keys());
    const newConnections = new Map<string, Connection>();
    const connectionCounts = new Map<number, number>();

    const activeNodes = Array.from(this.nodes.values()).filter(
      (n) => n.status === 'active'
    );

    if (activeNodes.length === 0) {
      // Mark all existing connections as removing
      prevKeys.forEach((key) => {
        if (!this.removingConnectionKeys.has(key)) {
          this.removingConnectionKeys.add(key);
          this.emit({ type: 'connection-removed', payload: key });
        }
      });
      return;
    }

    // Pass 1: Distance-based connections
    for (let i = 0; i < activeNodes.length; i++) {
      for (let j = i + 1; j < activeNodes.length; j++) {
        const a = activeNodes[i];
        const b = activeNodes[j];

        const aCount = connectionCounts.get(a.id) ?? 0;
        const bCount = connectionCounts.get(b.id) ?? 0;

        if (
          aCount >= MESH_CONFIG.MAX_CONNECTIONS_PER_NODE ||
          bCount >= MESH_CONFIG.MAX_CONNECTIONS_PER_NODE
        )
          continue;

        tempVec3A.set(
          a.position[0] - b.position[0],
          a.position[1] - b.position[1],
          a.position[2] - b.position[2]
        );
        const dist = tempVec3A.length();

        if (dist < MESH_CONFIG.CONNECTION_DISTANCE) {
          const key = `${a.id}-${b.id}`;
          newConnections.set(key, {
            fromId: a.id,
            toId: b.id,
            key,
            from: a.position,
            to: b.position,
          });
          connectionCounts.set(a.id, aCount + 1);
          connectionCounts.set(b.id, bCount + 1);
        }
      }
    }

    // Pass 2: Orphan protection - override max connections if needed
    // Run this pass up to 3 times to catch cascading orphans
    for (let pass = 0; pass < 3; pass++) {
      let orphansFixed = 0;

      activeNodes.forEach((node) => {
        const count = connectionCounts.get(node.id) ?? 0;
        if (count === 0 && activeNodes.length > 1) {
          // Find nearest node, ignoring connection limits for orphan rescue
          let nearestNode: NodeState | undefined = undefined;
          let minDist = Infinity;

          for (const other of activeNodes) {
            if (node.id === other.id) continue;
            tempVec3A.set(
              node.position[0] - other.position[0],
              node.position[1] - other.position[1],
              node.position[2] - other.position[2]
            );
            const distSq = tempVec3A.lengthSq();
            if (distSq < minDist) {
              minDist = distSq;
              nearestNode = other;
            }
          }

          if (nearestNode) {
            // Normalize key: always smaller ID first (matches Pass 1 behavior)
            const smaller = Math.min(node.id, nearestNode.id);
            const larger = Math.max(node.id, nearestNode.id);
            const key = `${smaller}-${larger}`;

            // Check if connection already exists with normalized key
            if (!newConnections.has(key)) {
              // Force connection even if nearestNode is at max - orphan prevention takes priority
              newConnections.set(key, {
                fromId: smaller,
                toId: larger,
                key,
                from: smaller === node.id ? node.position : nearestNode.position,
                to: smaller === node.id ? nearestNode.position : node.position,
              });
              connectionCounts.set(node.id, (connectionCounts.get(node.id) ?? 0) + 1);
              connectionCounts.set(nearestNode.id, (connectionCounts.get(nearestNode.id) ?? 0) + 1);
              orphansFixed++;
            }
          }
        }
      });

      // If no orphans were fixed this pass, we're done
      if (orphansFixed === 0) break;
    }

    // Find removed connections
    const newKeys = new Set(newConnections.keys());
    prevKeys.forEach((key) => {
      if (!newKeys.has(key) && !this.removingConnectionKeys.has(key)) {
        this.removingConnectionKeys.add(key);
        this.emit({ type: 'connection-removed', payload: key });
      }
    });

    this.connections = newConnections;
  }

  markConnectionRetracted(key: string): void {
    this.removingConnectionKeys.delete(key);
    this.emit({ type: 'connections-changed' });
  }

  // --------------------------------------------------------------------------
  // ORPHAN DETECTION
  // --------------------------------------------------------------------------

  private wouldCreateOrphan(nodeIdToRemove: number): boolean {
    const activeNodes = Array.from(this.nodes.values()).filter(
      (n) => n.status === 'active' && n.id !== nodeIdToRemove
    );

    if (activeNodes.length === 0) return false;

    const connectionCounts = new Map<number, number>();

    for (let i = 0; i < activeNodes.length; i++) {
      for (let j = i + 1; j < activeNodes.length; j++) {
        const a = activeNodes[i];
        const b = activeNodes[j];

        const aCount = connectionCounts.get(a.id) ?? 0;
        const bCount = connectionCounts.get(b.id) ?? 0;
        if (
          aCount >= MESH_CONFIG.MAX_CONNECTIONS_PER_NODE ||
          bCount >= MESH_CONFIG.MAX_CONNECTIONS_PER_NODE
        )
          continue;

        tempVec3A.set(
          a.position[0] - b.position[0],
          a.position[1] - b.position[1],
          a.position[2] - b.position[2]
        );
        const dist = tempVec3A.length();

        if (dist < MESH_CONFIG.CONNECTION_DISTANCE) {
          connectionCounts.set(a.id, aCount + 1);
          connectionCounts.set(b.id, bCount + 1);
        }
      }
    }

    return activeNodes.some(
      (node) => (connectionCounts.get(node.id) ?? 0) === 0
    );
  }

  // --------------------------------------------------------------------------
  // SUBSCRIPTION
  // --------------------------------------------------------------------------

  subscribe(callback: EngineSubscriber): () => void {
    this.subscribers.add(callback);
    // Immediately call with current state
    callback(this.getState());
    return () => {
      this.subscribers.delete(callback);
    };
  }

  private emit(event: EngineEvent): void {
    const state = this.getState();
    this.subscribers.forEach((callback) => {
      callback(state, event);
    });
  }

  // --------------------------------------------------------------------------
  // STATE ACCESS
  // --------------------------------------------------------------------------

  getState(): EngineState {
    // Include both active connections and removing connections
    const activeConnections = Array.from(this.connections.values());

    return {
      nodes: Array.from(this.nodes.values()),
      connections: activeConnections,
      glowingNodeIds: new Set(this.glowingNodeIds),
      removingConnectionKeys: new Set(this.removingConnectionKeys),
    };
  }

  getNode(id: number): NodeState | undefined {
    return this.nodes.get(id);
  }

  getActiveNodeCount(): number {
    return Array.from(this.nodes.values()).filter(
      (n) => n.status === 'active'
    ).length;
  }

  getGlowingNodeCount(): number {
    return this.glowingNodeIds.size;
  }
}

// ============================================================================
// SINGLETON INSTANCE
// ============================================================================

let engineInstance: MeshNetworkEngine | null = null;

export function getMeshNetworkEngine(): MeshNetworkEngine {
  if (!engineInstance) {
    engineInstance = new MeshNetworkEngine();
  }
  return engineInstance;
}

export function disposeMeshNetworkEngine(): void {
  if (engineInstance) {
    engineInstance.dispose();
    engineInstance = null;
  }
}
