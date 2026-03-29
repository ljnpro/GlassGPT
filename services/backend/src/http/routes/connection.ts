import {
  APP_VERSION_HEADER,
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
    const clientAppVersion = context.req.header(APP_VERSION_HEADER) ?? undefined;
    const accessToken = readBearerToken(context.req.header('Authorization'));
    if (!accessToken) {
      return context.json(buildUnsignedConnectionCheck(clientAppVersion));
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
          clientAppVersion,
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
          clientAppVersion,
          errorSummary: 'authentication_failed',
          latencyMs: 0,
          openaiCredential: 'missing',
        }),
      );
    }
  });
};
