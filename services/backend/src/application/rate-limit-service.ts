import type { BackendRuntimeContext } from './runtime-context.js';

export interface RateLimitWindowRecord {
  readonly bucketKey: string;
  readonly requestCount: number;
  readonly updatedAtMs: number;
  readonly windowStartMs: number;
}

export interface RateLimitConsumptionResult {
  readonly allowed: boolean;
  readonly remaining: number;
  readonly resetAtMs: number;
  readonly retryAfterSeconds: number | null;
}

export interface RateLimitServiceDependencies {
  readonly loadRateLimitWindow: (
    env: BackendRuntimeContext,
    bucketKey: string,
  ) => Promise<RateLimitWindowRecord | null>;
  readonly pruneRateLimitWindows: (
    env: BackendRuntimeContext,
    olderThanMs: number,
  ) => Promise<void>;
  readonly saveRateLimitWindow: (
    env: BackendRuntimeContext,
    record: RateLimitWindowRecord,
  ) => Promise<void>;
}

export interface RateLimitService {
  consumeRequest(
    env: BackendRuntimeContext,
    input: {
      readonly bucketKey: string;
      readonly maxRequests: number;
      readonly nowMs: number;
      readonly staleWindowRetentionMs: number;
      readonly windowMs: number;
    },
  ): Promise<RateLimitConsumptionResult>;
}

export const createRateLimitService = (deps: RateLimitServiceDependencies): RateLimitService => {
  return {
    consumeRequest: async (env, input) => {
      await deps.pruneRateLimitWindows(env, input.nowMs - input.staleWindowRetentionMs);

      const entry = await deps.loadRateLimitWindow(env, input.bucketKey);
      const windowExpired = entry === null || input.nowMs - entry.windowStartMs >= input.windowMs;
      const windowStartMs = windowExpired ? input.nowMs : entry.windowStartMs;
      const nextRequestCount = windowExpired ? 1 : entry.requestCount + 1;
      const resetAtMs = windowStartMs + input.windowMs;

      if (!windowExpired && entry.requestCount >= input.maxRequests) {
        return {
          allowed: false,
          remaining: 0,
          resetAtMs,
          retryAfterSeconds: Math.ceil((resetAtMs - input.nowMs) / 1000),
        };
      }

      await deps.saveRateLimitWindow(env, {
        bucketKey: input.bucketKey,
        requestCount: nextRequestCount,
        updatedAtMs: input.nowMs,
        windowStartMs,
      });

      return {
        allowed: true,
        remaining: Math.max(input.maxRequests - nextRequestCount, 0),
        resetAtMs,
        retryAfterSeconds: null,
      };
    },
  };
};
