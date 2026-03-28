import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installSyncRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/sync/events', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const cursor = context.req.query('cursor') ?? null;

    return context.json(
      await services.syncService.syncEvents(
        asBackendRuntimeContext(context.env),
        session.userId,
        cursor,
      ),
    );
  });
};
