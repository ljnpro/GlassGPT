import { errorResponseSchema } from '@glassgpt/backend-contracts';
import { Hono } from 'hono';
import { ZodError } from 'zod';

import { isApplicationError } from '../application/errors.js';
import { logError } from '../observability/logger.js';
import { installArtifactRoutes } from './routes/artifacts.js';
import { installAuthRoutes } from './routes/auth.js';
import { installConnectionRoutes } from './routes/connection.js';
import { installConversationRoutes } from './routes/conversations.js';
import { installCredentialRoutes } from './routes/credentials.js';
import { installHealthRoutes } from './routes/health.js';
import { installRunRoutes } from './routes/runs.js';
import { installSyncRoutes } from './routes/sync.js';
import type { BackendServices } from './services.js';
import type { BackendApp } from './types.js';

type ApplicationErrorStatusCode = 400 | 401 | 403 | 404 | 409 | 500;

const statusCodeForApplicationError = (code: string): ApplicationErrorStatusCode => {
  switch (code) {
    case 'invalid_request':
      return 400;
    case 'unauthorized':
      return 401;
    case 'forbidden':
      return 403;
    case 'not_found':
      return 404;
    case 'conflict':
      return 409;
    default:
      return 500;
  }
};

export const createApp = (services: BackendServices): BackendApp => {
  const app = new Hono<{ Bindings: Env }>();

  installHealthRoutes(app);
  installConnectionRoutes(app, services);
  installAuthRoutes(app, services);
  installCredentialRoutes(app, services);
  installConversationRoutes(app, services);
  installRunRoutes(app, services);
  installSyncRoutes(app, services);
  installArtifactRoutes(app);

  app.notFound((context) => {
    return context.json(errorResponseSchema.parse({ error: 'not_found' }), 404);
  });

  app.onError((error, context) => {
    if (error instanceof ZodError) {
      return context.json(errorResponseSchema.parse({ error: 'invalid_request' }), 400);
    }

    if (isApplicationError(error)) {
      return context.json(errorResponseSchema.parse({ error: error.code }), {
        status: statusCodeForApplicationError(error.code),
      });
    }

    logError('backend_request_failed', {
      errorName: error.name,
      errorMessage: error.message,
    });

    return context.json(errorResponseSchema.parse({ error: 'internal_server_error' }), 500);
  });

  return app;
};
