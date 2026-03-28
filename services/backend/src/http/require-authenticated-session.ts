import type { Context } from 'hono';

import { ApplicationError } from '../application/errors.js';
import { readBearerToken } from './authorization.js';
import { asBackendRuntimeContext } from './runtime-context.js';
import type { BackendServices } from './services.js';

export const requireAuthenticatedSession = async (
  context: Context<{ Bindings: Env }>,
  services: BackendServices,
) => {
  const accessToken = readBearerToken(context.req.header('Authorization'));
  if (!accessToken) {
    throw new ApplicationError('unauthorized', 'authorization_header_missing');
  }

  return services.authService.resolveSession(asBackendRuntimeContext(context.env), accessToken);
};
