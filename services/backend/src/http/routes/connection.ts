import {
  buildConnectionCheck,
  buildUnsignedConnectionCheck,
  healthStateForCredentialStatus,
} from '../../application/connection-check.js';
import { isApplicationError } from '../../application/errors.js';
import { readBearerToken } from '../authorization.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installConnectionRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/connection/check', async (context) => {
    const accessToken = readBearerToken(context.req.header('Authorization'));
    if (!accessToken) {
      return context.json(buildUnsignedConnectionCheck());
    }

    try {
      const session = await services.authService.resolveSession(
        asBackendRuntimeContext(context.env),
        accessToken,
      );
      const credentialStatus = await services.credentialService.readOpenAiKeyStatus(
        asBackendRuntimeContext(context.env),
        session.userId,
      );

      return context.json(
        buildConnectionCheck({
          auth: 'healthy',
          latencyMs: 0,
          openaiCredential: healthStateForCredentialStatus(credentialStatus.state),
        }),
      );
    } catch (error) {
      if (!isApplicationError(error) || error.code !== 'unauthorized') {
        throw error;
      }

      return context.json(
        buildConnectionCheck({
          auth: 'unauthorized',
          errorSummary: 'authentication_failed',
          latencyMs: 0,
          openaiCredential: 'missing',
        }),
      );
    }
  });
};
