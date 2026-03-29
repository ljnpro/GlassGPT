import { errorResponseSchema } from '@glassgpt/backend-contracts';
import type { Context, Next } from 'hono';

import { readBearerToken } from '../authorization.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { AuthenticatedBackendSession, BackendServices } from '../services.js';
import type { BackendAppContext } from '../types.js';

export const RATE_LIMIT_WINDOW_MS = 60_000;
export const AUTHENTICATED_MAX_REQUESTS_PER_WINDOW = 120;
export const ANONYMOUS_MAX_REQUESTS_PER_WINDOW = 30;

const STALE_WINDOW_RETENTION_MS = 24 * 60 * 60 * 1000;

interface RateLimitIdentity {
  readonly bucketKey: string;
  readonly maxRequests: number;
  readonly session: AuthenticatedBackendSession | null;
}

const readClientAddress = (context: Context<BackendAppContext>): string => {
  const cloudflareAddress = context.req.header('CF-Connecting-IP');
  if (cloudflareAddress && cloudflareAddress.length > 0) {
    return cloudflareAddress;
  }

  const forwardedFor = context.req.header('X-Forwarded-For');
  if (forwardedFor && forwardedFor.length > 0) {
    return forwardedFor.split(',')[0]?.trim() ?? 'unknown';
  }

  return 'unknown';
};

const resolveRateLimitIdentity = async (
  context: Context<BackendAppContext>,
  services: BackendServices,
): Promise<RateLimitIdentity> => {
  const authorizationHeader = context.req.header('Authorization');
  if (authorizationHeader) {
    try {
      const accessToken = readBearerToken(authorizationHeader);
      if (accessToken) {
        const session = await services.authService.resolveSession(
          asBackendRuntimeContext(context.env),
          accessToken,
        );
        context.set('session', session);
        return {
          bucketKey: `user:${session.userId}`,
          maxRequests: AUTHENTICATED_MAX_REQUESTS_PER_WINDOW,
          session,
        };
      }
    } catch {
      // Invalid or expired tokens still fall back to anonymous rate limiting.
    }
  }

  return {
    bucketKey: `anon:${readClientAddress(context)}`,
    maxRequests: ANONYMOUS_MAX_REQUESTS_PER_WINDOW,
    session: null,
  };
};

export const createRateLimiterMiddleware = (services: BackendServices) => {
  return async (context: Context<BackendAppContext>, next: Next): Promise<Response | undefined> => {
    if (context.req.method === 'OPTIONS') {
      await next();
      return undefined;
    }

    const now = Date.now();
    const runtimeContext = asBackendRuntimeContext(context.env);
    const identity = await resolveRateLimitIdentity(context, services);

    const rateLimitResult = await services.rateLimitService.consumeRequest(runtimeContext, {
      bucketKey: identity.bucketKey,
      maxRequests: identity.maxRequests,
      nowMs: now,
      staleWindowRetentionMs: STALE_WINDOW_RETENTION_MS,
      windowMs: RATE_LIMIT_WINDOW_MS,
    });

    if (!rateLimitResult.allowed) {
      context.header('Retry-After', String(rateLimitResult.retryAfterSeconds));
      context.header('X-RateLimit-Limit', String(identity.maxRequests));
      context.header('X-RateLimit-Remaining', '0');
      context.header('X-RateLimit-Reset', String(rateLimitResult.resetAtMs));
      return context.json(errorResponseSchema.parse({ error: 'rate_limited' }), 429);
    }

    context.header('X-RateLimit-Limit', String(identity.maxRequests));
    context.header('X-RateLimit-Remaining', String(rateLimitResult.remaining));
    context.header('X-RateLimit-Reset', String(rateLimitResult.resetAtMs));

    await next();
    return undefined;
  };
};
