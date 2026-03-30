import {
  APP_VERSION_HEADER,
  authRuntimeConfigurationError,
  buildCompatibilityMetadata,
} from '../../application/connection-check.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendApp } from '../types.js';

export const installHealthRoutes = (app: BackendApp): void => {
  app.get('/healthz', (context) => {
    const clientAppVersion = context.req.header(APP_VERSION_HEADER) ?? undefined;
    const runtimeConfigurationError = authRuntimeConfigurationError(
      asBackendRuntimeContext(context.env),
    );
    return context.json({
      appEnv: context.env.APP_ENV,
      errorSummary: runtimeConfigurationError,
      ...buildCompatibilityMetadata(clientAppVersion),
      ok: runtimeConfigurationError === undefined,
    });
  });
};
