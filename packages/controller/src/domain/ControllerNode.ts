export interface ControllerNode {
  id: string;
  url: string;
  name: string;
  registeredAt: number;
  lastHeartbeatAt: number;
  expiresAt: number;
  isActive: boolean;
  metadata?: Record<string, unknown>;
}

export interface ControllerNodeRow {
  id: string;
  url: string;
  name: string;
  registered_at: number;
  last_heartbeat_at: number;
  expires_at: number;
  is_active: number;
  metadata: string | null;
}

export function controllerNodeFromRow(row: ControllerNodeRow): ControllerNode {
  return {
    id: row.id,
    url: row.url,
    name: row.name,
    registeredAt: row.registered_at,
    lastHeartbeatAt: row.last_heartbeat_at,
    expiresAt: row.expires_at,
    isActive: row.is_active === 1,
    metadata: row.metadata ? JSON.parse(row.metadata) : undefined,
  };
}

export function controllerNodeToRow(node: Omit<ControllerNode, 'isActive'> & { isActive?: boolean }): ControllerNodeRow {
  return {
    id: node.id,
    url: node.url,
    name: node.name,
    registered_at: node.registeredAt,
    last_heartbeat_at: node.lastHeartbeatAt,
    expires_at: node.expiresAt,
    is_active: node.isActive === false ? 0 : 1,
    metadata: node.metadata ? JSON.stringify(node.metadata) : null,
  };
}
