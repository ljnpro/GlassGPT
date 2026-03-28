import { openAiCredentialRequestSchema } from '@glassgpt/backend-contracts';

import { ApplicationError } from '../../application/errors.js';
import { readBearerToken } from '../authorization.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installCredentialRoutes = (app: BackendApp, services: BackendServices): void => {
  app.put('/v1/credentials/openai', async (context) => {
    const accessToken = readBearerToken(context.req.header('Authorization'));
    if (!accessToken) {
      throw new ApplicationError('unauthorized', 'authorization_header_missing');
    }

    const body = openAiCredentialRequestSchema.parse(await context.req.json());
    const session = await services.authService.resolveSession(
      asBackendRuntimeContext(context.env),
      accessToken,
    );
    const status = await services.credentialService.storeOpenAiKey(
      asBackendRuntimeContext(context.env),
      session.userId,
      body.apiKey,
    );
    return context.json(status);
  });

  app.delete('/v1/credentials/openai', async (context) => {
    const accessToken = readBearerToken(context.req.header('Authorization'));
    if (!accessToken) {
      throw new ApplicationError('unauthorized', 'authorization_header_missing');
    }

    const session = await services.authService.resolveSession(
      asBackendRuntimeContext(context.env),
      accessToken,
    );
    await services.credentialService.deleteOpenAiKey(
      asBackendRuntimeContext(context.env),
      session.userId,
    );
    return context.body(null, 204);
  });
};
