import type { Context, Next } from 'hono';

const WINDOW_MS = 60_000;
const MAX_REQUESTS_PER_WINDOW = 100;

interface WindowEntry {
  readonly count: number;
  readonly windowStart: number;
}

/**
 * Per-isolate in-memory rate limiter.
 * Tracks requests per userId within sliding windows.
 * Resets on cold start (acceptable for beta; upgrade to KV-backed for production).
 */
const userWindows = new Map<string, WindowEntry>();

export const rateLimiterMiddleware = async (context: Context, next: Next): Promise<void> => {
  const userId = (context.get('session') as { userId?: string } | undefined)?.userId;
  if (!userId) {
    await next();
    return;
  }

  const now = Date.now();
  const entry = userWindows.get(userId);

  if (!entry || now - entry.windowStart >= WINDOW_MS) {
    userWindows.set(userId, { count: 1, windowStart: now });
    await next();
    return;
  }

  if (entry.count >= MAX_REQUESTS_PER_WINDOW) {
    const retryAfterSeconds = Math.ceil((entry.windowStart + WINDOW_MS - now) / 1000);
    context.header('Retry-After', String(retryAfterSeconds));
    context.status(429);
    context.body(JSON.stringify({ error: 'rate_limited' }));
    return;
  }

  userWindows.set(userId, { count: entry.count + 1, windowStart: entry.windowStart });
  await next();
};
