import {
  APP_VERSION_HEADER,
  buildCompatibilityMetadata,
} from '../../application/connection-check.js';
import type { BackendApp } from '../types.js';

export const installHealthRoutes = (app: BackendApp): void => {
  app.get('/healthz', (context) => {
    const clientAppVersion = context.req.header(APP_VERSION_HEADER) ?? undefined;
    return context.json({
      appEnv: context.env.APP_ENV,
      ...buildCompatibilityMetadata(clientAppVersion),
      ok: true,
    });
  });
};
