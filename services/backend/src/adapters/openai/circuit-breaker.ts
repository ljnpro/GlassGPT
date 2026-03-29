type CircuitState = 'closed' | 'half_open' | 'open';

const FAILURE_THRESHOLD = 5;
const COOLDOWN_MS = 30_000;

/**
 * Per-isolate circuit breaker for OpenAI API calls.
 * Trips to OPEN after consecutive failures, then probes after cooldown.
 * Resets on cold start (acceptable for Cloudflare Workers beta).
 */
export class CircuitBreaker {
  private state: CircuitState = 'closed';
  private consecutiveFailures = 0;
  private openedAt: number | null = null;

  get isOpen(): boolean {
    if (this.state === 'closed') return false;

    if (this.state === 'open' && this.openedAt !== null) {
      if (Date.now() - this.openedAt >= COOLDOWN_MS) {
        this.state = 'half_open';
        return false;
      }
    }

    return this.state === 'open';
  }

  recordSuccess(): void {
    this.consecutiveFailures = 0;
    this.state = 'closed';
    this.openedAt = null;
  }

  recordFailure(): void {
    this.consecutiveFailures++;
    if (this.consecutiveFailures >= FAILURE_THRESHOLD) {
      this.state = 'open';
      this.openedAt = Date.now();
    }
  }

  get currentState(): CircuitState {
    return this.state;
  }
}

/** Shared per-isolate instance. Resets on cold start. */
export const openAiCircuitBreaker = new CircuitBreaker();
