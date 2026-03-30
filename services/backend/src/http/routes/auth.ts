import { appleAuthRequestSchema, refreshSessionRequestSchema } from '@glassgpt/backend-contracts';

import { authRuntimeConfigurationError } from '../../application/connection-check.js';
import { ApplicationError } from '../../application/errors.js';
import { readBearerToken } from '../authorization.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installAuthRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/me', async (context) => {
    const runtimeContext = asBackendRuntimeContext(context.env);
    const runtimeConfigurationError = authRuntimeConfigurationError(runtimeContext);
    if (runtimeConfigurationError) {
      throw new ApplicationError('service_unavailable', runtimeConfigurationError);
    }

    const accessToken = readBearerToken(context.req.header('Authorization'));
    if (!accessToken) {
      throw new ApplicationError('unauthorized', 'authorization_header_missing');
    }

    const user = await services.authService.fetchCurrentUser(runtimeContext, accessToken);
    return context.json(user);
  });

  app.post('/v1/auth/apple', async (context) => {
    const runtimeContext = asBackendRuntimeContext(context.env);
    const runtimeConfigurationError = authRuntimeConfigurationError(runtimeContext);
    if (runtimeConfigurationError) {
      throw new ApplicationError('service_unavailable', runtimeConfigurationError);
    }

    const body = appleAuthRequestSchema.parse(await context.req.json());
    const session = await services.authService.authenticateWithApple(runtimeContext, body);
    return context.json(session);
  });

  app.post('/v1/auth/refresh', async (context) => {
    const runtimeContext = asBackendRuntimeContext(context.env);
    const runtimeConfigurationError = authRuntimeConfigurationError(runtimeContext);
    if (runtimeConfigurationError) {
      throw new ApplicationError('service_unavailable', runtimeConfigurationError);
    }

    const body = refreshSessionRequestSchema.parse(await context.req.json());
    const session = await services.authService.refreshSession(runtimeContext, body);
    return context.json(session);
  });

  app.post('/v1/auth/logout', async (context) => {
    const runtimeContext = asBackendRuntimeContext(context.env);
    const runtimeConfigurationError = authRuntimeConfigurationError(runtimeContext);
    if (runtimeConfigurationError) {
      throw new ApplicationError('service_unavailable', runtimeConfigurationError);
    }

    const accessToken = readBearerToken(context.req.header('Authorization'));
    if (!accessToken) {
      throw new ApplicationError('unauthorized', 'authorization_header_missing');
    }

    await services.authService.logout(runtimeContext, accessToken);
    return context.body(null, 204);
  });
};
