type CircuitState = 'closed' | 'half_open' | 'open';

const FAILURE_THRESHOLD = 5;
const FAILURE_WINDOW_MS = 60_000;
const COOLDOWN_MS = 30_000;
const REGISTRY_ENTRY_TTL_MS = 10 * 60_000;
const REGISTRY_MAX_ENTRIES = 512;

type Clock = () => number;

export interface CircuitBreakerOptions {
  readonly cooldownMs?: number;
  readonly failureThreshold?: number;
  readonly now?: Clock;
  readonly windowMs?: number;
}

export interface CircuitBreakerKeyInput {
  readonly apiKey: string;
  readonly model: string;
  readonly serviceTier?: string;
}

/**
 * Sliding-window circuit breaker for a single OpenAI request partition.
 * Trips to OPEN after enough recent failures, then allows a half-open probe
 * once the cooldown has elapsed.
 */
export class CircuitBreaker {
  private readonly cooldownMs: number;
  private readonly failureThreshold: number;
  private readonly now: Clock;
  private readonly windowMs: number;
  private state: CircuitState = 'closed';
  private failureTimestamps: number[] = [];
  private openedAt: number | null = null;
  private lastTouchedAt: number;

  constructor(options: CircuitBreakerOptions = {}) {
    this.cooldownMs = options.cooldownMs ?? COOLDOWN_MS;
    this.failureThreshold = options.failureThreshold ?? FAILURE_THRESHOLD;
    this.now = options.now ?? Date.now;
    this.windowMs = options.windowMs ?? FAILURE_WINDOW_MS;
    this.lastTouchedAt = this.now();
  }

  get isOpen(): boolean {
    return this.isOpenAt(this.now());
  }

  get currentState(): CircuitState {
    return this.state;
  }

  get lastInteractionAt(): number {
    return this.lastTouchedAt;
  }

  recordSuccess(): void {
    const now = this.now();
    this.touch(now);
    this.failureTimestamps = [];
    this.state = 'closed';
    this.openedAt = null;
  }

  recordFailure(): void {
    const now = this.now();
    this.touch(now);
    this.pruneFailures(now);
    this.failureTimestamps.push(now);

    if (this.failureTimestamps.length >= this.failureThreshold) {
      this.state = 'open';
      this.openedAt = now;
    }
  }

  private isOpenAt(now: number): boolean {
    this.touch(now);

    if (this.state === 'closed') {
      this.pruneFailures(now);
      return false;
    }

    if (this.state === 'open' && this.openedAt !== null) {
      if (now - this.openedAt >= this.cooldownMs) {
        this.state = 'half_open';
        return false;
      }
    }

    return this.state === 'open';
  }

  private pruneFailures(now: number): void {
    const cutoff = now - this.windowMs;
    this.failureTimestamps = this.failureTimestamps.filter((timestamp) => timestamp >= cutoff);
    if (this.failureTimestamps.length === 0 && this.state === 'closed') {
      this.openedAt = null;
    }
  }

  private touch(now: number): void {
    this.lastTouchedAt = now;
  }
}

export interface KeyedCircuitBreakerRegistryOptions {
  readonly breakerOptions?: Omit<CircuitBreakerOptions, 'now'>;
  readonly entryTtlMs?: number;
  readonly maxEntries?: number;
  readonly now?: Clock;
}

/**
 * Per-isolate keyed registry so one user's failures do not open the breaker
 * for unrelated users or models on the same worker.
 */
export class KeyedCircuitBreakerRegistry {
  private readonly breakers = new Map<string, CircuitBreaker>();
  private readonly breakerOptions: Omit<CircuitBreakerOptions, 'now'>;
  private readonly entryTtlMs: number;
  private readonly maxEntries: number;
  private readonly now: Clock;

  constructor(options: KeyedCircuitBreakerRegistryOptions = {}) {
    this.breakerOptions = options.breakerOptions ?? {};
    this.entryTtlMs = options.entryTtlMs ?? REGISTRY_ENTRY_TTL_MS;
    this.maxEntries = options.maxEntries ?? REGISTRY_MAX_ENTRIES;
    this.now = options.now ?? Date.now;
  }

  get size(): number {
    return this.breakers.size;
  }

  breakerFor(key: string): CircuitBreaker {
    const now = this.now();
    this.pruneExpired(now);

    const existing = this.breakers.get(key);
    if (existing) {
      return existing;
    }

    const breaker = new CircuitBreaker({
      ...this.breakerOptions,
      now: this.now,
    });
    this.breakers.set(key, breaker);
    this.trimToCapacity();
    return breaker;
  }

  private pruneExpired(now: number): void {
    for (const [key, breaker] of this.breakers.entries()) {
      if (now - breaker.lastInteractionAt > this.entryTtlMs) {
        this.breakers.delete(key);
      }
    }
  }

  private trimToCapacity(): void {
    if (this.breakers.size <= this.maxEntries) {
      return;
    }

    const oldestEntries = [...this.breakers.entries()].sort(
      (left, right) => left[1].lastInteractionAt - right[1].lastInteractionAt,
    );
    while (this.breakers.size > this.maxEntries) {
      const oldest = oldestEntries.shift();
      if (!oldest) {
        break;
      }
      this.breakers.delete(oldest[0]);
    }
  }
}

const hashPartition = (value: string): string => {
  let hash = 0x811c9dc5;
  for (const character of value) {
    hash ^= character.charCodeAt(0);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
};

export const openAiCircuitBreakerKey = (input: CircuitBreakerKeyInput): string => {
  return [
    `api:${hashPartition(input.apiKey)}`,
    `model:${input.model}`,
    `tier:${input.serviceTier ?? 'default'}`,
  ].join('|');
};

export const openAiCircuitBreakers = new KeyedCircuitBreakerRegistry();
