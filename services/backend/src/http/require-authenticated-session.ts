import type { Context } from 'hono';

import { ApplicationError } from '../application/errors.js';
import { readBearerToken } from './authorization.js';
import { asBackendRuntimeContext } from './runtime-context.js';
import type { BackendServices } from './services.js';
import type { BackendAppContext } from './types.js';

export const requireAuthenticatedSession = async (
  context: Context<BackendAppContext>,
  services: BackendServices,
) => {
  const cachedSession = context.get('session');
  if (cachedSession) {
    return cachedSession;
  }

  const accessToken = readBearerToken(context.req.header('Authorization'));
  if (!accessToken) {
    throw new ApplicationError('unauthorized', 'authorization_header_missing');
  }

  const session = await services.authService.resolveSession(
    asBackendRuntimeContext(context.env),
    accessToken,
  );
  context.set('session', session);
  return session;
};
