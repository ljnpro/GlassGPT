import type { BackendApp } from '../types.js';

export const installHealthRoutes = (app: BackendApp): void => {
  app.get('/healthz', (context) => {
    return context.json({
      ok: true,
    });
  });
};
