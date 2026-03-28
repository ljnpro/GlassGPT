import type { MiddlewareHandler } from 'hono';

export const requestIdMiddleware: MiddlewareHandler = async (context, next) => {
  const requestId = context.req.header('X-Request-ID') ?? crypto.randomUUID();
  context.set('requestId', requestId);
  await next();
  context.header('X-Request-ID', requestId);
};
