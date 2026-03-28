import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installRunRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/runs/:runId', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    return context.json(
      await services.runService.getRun(
        asBackendRuntimeContext(context.env),
        session.userId,
        context.req.param('runId'),
      ),
    );
  });

  app.post('/v1/runs/:runId/cancel', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    return context.json(
      await services.runService.cancelRun(
        asBackendRuntimeContext(context.env),
        session.userId,
        context.req.param('runId'),
      ),
    );
  });

  app.post('/v1/runs/:runId/retry', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    return context.json(
      await services.runService.retryRun(
        asBackendRuntimeContext(context.env),
        {
          agent: context.env.AGENT_RUN_WORKFLOW,
          chat: context.env.CHAT_RUN_WORKFLOW,
        },
        session.userId,
        context.req.param('runId'),
      ),
      202,
    );
  });
};
