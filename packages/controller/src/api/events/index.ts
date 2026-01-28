import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { EventLog } from '../../services/EventLog';
import { EventBroadcaster } from '../../services/EventBroadcaster';
import { Event } from '../../domain/Event';
import { requireApiKey } from '../../middleware/auth';

interface SinceParams {
  sequence: string;
}

interface SinceQuery {
  limit?: string;
}

export async function registerEventRoutes(
  app: FastifyInstance,
  eventLog: EventLog,
  broadcaster: EventBroadcaster
) {
  // Broadcast event from another controller
  app.post<{ Body: Event }>(
    '/api/events/broadcast',
    { preHandler: requireApiKey },
    async (request: FastifyRequest<{ Body: Event }>, reply: FastifyReply) => {
      const event = request.body;

      if (!event || !event.id || !event.eventHash) {
        return reply.status(400).send({ error: 'Invalid event format' });
      }

      try {
        // Receive and propagate event
        await broadcaster.receive(event);
        return reply.send({ success: true });
      } catch (error) {
        return reply.status(400).send({
          error: error instanceof Error ? error.message : 'Failed to process event',
        });
      }
    }
  );

  // Get events since sequence (for sync/catchup)
  app.get<{ Params: SinceParams; Querystring: SinceQuery }>(
    '/api/events/since/:sequence',
    { preHandler: requireApiKey },
    async (
      request: FastifyRequest<{ Params: SinceParams; Querystring: SinceQuery }>,
      reply: FastifyReply
    ) => {
      const sequence = parseInt(request.params.sequence, 10);
      const limit = request.query.limit ? parseInt(request.query.limit, 10) : 1000;

      if (isNaN(sequence) || sequence < 0) {
        return reply.status(400).send({ error: 'Invalid sequence number' });
      }

      try {
        const events = await eventLog.getSince(sequence, limit);
        return reply.send({ events });
      } catch (error) {
        return reply.status(500).send({
          error: error instanceof Error ? error.message : 'Failed to fetch events',
        });
      }
    }
  );

  // Verify event log integrity
  app.get(
    '/api/events/verify',
    { preHandler: requireApiKey },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      try {
        const result = await eventLog.verify();
        return reply.send(result);
      } catch (error) {
        return reply.status(500).send({
          error: error instanceof Error ? error.message : 'Verification failed',
        });
      }
    }
  );

  // Get all events (paginated)
  app.get<{ Querystring: { limit?: string; offset?: string } }>(
    '/api/events',
    { preHandler: requireApiKey },
    async (
      request: FastifyRequest<{ Querystring: { limit?: string; offset?: string } }>,
      reply: FastifyReply
    ) => {
      const limit = request.query.limit ? parseInt(request.query.limit, 10) : 100;
      const offset = request.query.offset ? parseInt(request.query.offset, 10) : 0;

      try {
        const events = await eventLog.getSince(offset, limit);
        const count = await eventLog.count();
        return reply.send({ events, count });
      } catch (error) {
        return reply.status(500).send({
          error: error instanceof Error ? error.message : 'Failed to fetch events',
        });
      }
    }
  );

  // Get event by ID
  app.get<{ Params: { id: string } }>(
    '/api/events/:id',
    { preHandler: requireApiKey },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      try {
        const event = await eventLog.getById(id);
        if (!event) {
          return reply.status(404).send({ error: 'Event not found' });
        }
        return reply.send({ event });
      } catch (error) {
        return reply.status(500).send({
          error: error instanceof Error ? error.message : 'Failed to fetch event',
        });
      }
    }
  );
}
