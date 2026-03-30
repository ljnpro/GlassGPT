import { openAiCredentialRequestSchema } from '@glassgpt/backend-contracts';

import { authRuntimeConfigurationError } from '../../application/connection-check.js';
import { ApplicationError } from '../../application/errors.js';
import { readBearerToken } from '../authorization.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installCredentialRoutes = (app: BackendApp, services: BackendServices): void => {
  app.put('/v1/credentials/openai', async (context) => {
    const runtimeContext = asBackendRuntimeContext(context.env);
    const runtimeConfigurationError = authRuntimeConfigurationError(runtimeContext);
    if (runtimeConfigurationError) {
      throw new ApplicationError('service_unavailable', runtimeConfigurationError);
    }

    const accessToken = readBearerToken(context.req.header('Authorization'));
    if (!accessToken) {
      throw new ApplicationError('unauthorized', 'authorization_header_missing');
    }

    const body = openAiCredentialRequestSchema.parse(await context.req.json());
    const session = await services.authService.resolveSession(runtimeContext, accessToken);
    const status = await services.credentialService.storeOpenAiKey(
      runtimeContext,
      session.userId,
      body.apiKey,
    );
    return context.json(status);
  });

  app.delete('/v1/credentials/openai', async (context) => {
    const runtimeContext = asBackendRuntimeContext(context.env);
    const runtimeConfigurationError = authRuntimeConfigurationError(runtimeContext);
    if (runtimeConfigurationError) {
      throw new ApplicationError('service_unavailable', runtimeConfigurationError);
    }

    const accessToken = readBearerToken(context.req.header('Authorization'));
    if (!accessToken) {
      throw new ApplicationError('unauthorized', 'authorization_header_missing');
    }

    const session = await services.authService.resolveSession(runtimeContext, accessToken);
    await services.credentialService.deleteOpenAiKey(runtimeContext, session.userId);
    return context.body(null, 204);
  });
};
