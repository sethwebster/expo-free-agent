import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { ControllerRegistry } from '../../services/ControllerRegistry';
import { requireApiKey } from '../../middleware/auth';

interface RegisterBody {
  id: string;
  url: string;
  name: string;
  metadata?: Record<string, unknown>;
  ttl?: number;
}

interface HeartbeatParams {
  id: string;
}

interface HeartbeatQuery {
  ttl?: string;
}

export async function registerControllerRoutes(
  app: FastifyInstance,
  registry: ControllerRegistry
) {
  // Register controller node
  app.post<{ Body: RegisterBody }>(
    '/api/controllers/register',
    { preHandler: requireApiKey },
    async (request: FastifyRequest<{ Body: RegisterBody }>, reply: FastifyReply) => {
      const { id, url, name, metadata, ttl } = request.body;

      if (!id || !url || !name) {
        return reply.status(400).send({ error: 'Missing required fields: id, url, name' });
      }

      try {
        const node = await registry.register({ id, url, name, metadata, ttl });
        return reply.send({
          id: node.id,
          expiresAt: node.expiresAt,
        });
      } catch (error) {
        return reply.status(500).send({
          error: error instanceof Error ? error.message : 'Failed to register controller',
        });
      }
    }
  );

  // Heartbeat for controller node
  app.post<{ Params: HeartbeatParams; Querystring: HeartbeatQuery }>(
    '/api/controllers/:id/heartbeat',
    { preHandler: requireApiKey },
    async (
      request: FastifyRequest<{ Params: HeartbeatParams; Querystring: HeartbeatQuery }>,
      reply: FastifyReply
    ) => {
      const { id } = request.params;
      const ttl = request.query.ttl ? parseInt(request.query.ttl, 10) : undefined;

      try {
        const expiresAt = await registry.heartbeat(id, ttl);
        return reply.send({ expiresAt: expiresAt.getTime() });
      } catch (error) {
        return reply.status(404).send({
          error: error instanceof Error ? error.message : 'Controller not found',
        });
      }
    }
  );

  // List active controllers
  app.get(
    '/api/controllers',
    { preHandler: requireApiKey },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      try {
        const controllers = await registry.getActive();
        return reply.send({ controllers });
      } catch (error) {
        return reply.status(500).send({
          error: error instanceof Error ? error.message : 'Failed to fetch controllers',
        });
      }
    }
  );

  // Get controller by ID
  app.get<{ Params: { id: string } }>(
    '/api/controllers/:id',
    { preHandler: requireApiKey },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      try {
        const controller = await registry.getById(id);
        if (!controller) {
          return reply.status(404).send({ error: 'Controller not found' });
        }
        return reply.send({ controller });
      } catch (error) {
        return reply.status(500).send({
          error: error instanceof Error ? error.message : 'Failed to fetch controller',
        });
      }
    }
  );
}
