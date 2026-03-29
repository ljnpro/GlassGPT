import { describe, expect, it } from 'vitest';

import {
  CircuitBreaker,
  KeyedCircuitBreakerRegistry,
  openAiCircuitBreakerKey,
} from './circuit-breaker.js';

describe('CircuitBreaker', () => {
  it('starts in closed state', () => {
    const breaker = new CircuitBreaker();
    expect(breaker.isOpen).toBe(false);
    expect(breaker.currentState).toBe('closed');
  });

  it('opens after enough failures inside the sliding window', () => {
    let now = 1_000;
    const breaker = new CircuitBreaker({
      cooldownMs: 100,
      failureThreshold: 3,
      now: () => now,
      windowMs: 1_000,
    });

    breaker.recordFailure();
    now += 100;
    breaker.recordFailure();
    now += 100;
    breaker.recordFailure();

    expect(breaker.isOpen).toBe(true);
    expect(breaker.currentState).toBe('open');
  });

  it('drops old failures that fall outside the sliding window', () => {
    let now = 1_000;
    const breaker = new CircuitBreaker({
      cooldownMs: 100,
      failureThreshold: 3,
      now: () => now,
      windowMs: 500,
    });

    breaker.recordFailure();
    now += 600;
    breaker.recordFailure();
    now += 100;
    breaker.recordFailure();

    expect(breaker.isOpen).toBe(false);
    expect(breaker.currentState).toBe('closed');
  });

  it('moves to half-open after the cooldown elapses', () => {
    let now = 1_000;
    const breaker = new CircuitBreaker({
      cooldownMs: 200,
      failureThreshold: 2,
      now: () => now,
      windowMs: 1_000,
    });

    breaker.recordFailure();
    breaker.recordFailure();
    expect(breaker.isOpen).toBe(true);

    now += 250;
    expect(breaker.isOpen).toBe(false);
    expect(breaker.currentState).toBe('half_open');
  });

  it('closes and clears recent failures after a success', () => {
    let now = 1_000;
    const breaker = new CircuitBreaker({
      cooldownMs: 200,
      failureThreshold: 2,
      now: () => now,
      windowMs: 1_000,
    });

    breaker.recordFailure();
    breaker.recordFailure();
    now += 250;
    expect(breaker.isOpen).toBe(false);

    breaker.recordSuccess();
    expect(breaker.currentState).toBe('closed');
    expect(breaker.isOpen).toBe(false);

    breaker.recordFailure();
    expect(breaker.isOpen).toBe(false);
  });
});

describe('KeyedCircuitBreakerRegistry', () => {
  it('keeps breaker state isolated per key', () => {
    const now = 1_000;
    const registry = new KeyedCircuitBreakerRegistry({
      breakerOptions: {
        cooldownMs: 100,
        failureThreshold: 2,
        windowMs: 1_000,
      },
      now: () => now,
    });

    const first = registry.breakerFor('user-a');
    const second = registry.breakerFor('user-b');

    first.recordFailure();
    first.recordFailure();

    expect(first.isOpen).toBe(true);
    expect(second.isOpen).toBe(false);
  });

  it('evicts stale breaker entries', () => {
    let now = 1_000;
    const registry = new KeyedCircuitBreakerRegistry({
      entryTtlMs: 50,
      now: () => now,
    });

    const breaker = registry.breakerFor('user-a');
    breaker.recordFailure();
    expect(registry.size).toBe(1);

    now += 100;
    registry.breakerFor('user-b');
    expect(registry.size).toBe(1);
  });
});

describe('openAiCircuitBreakerKey', () => {
  it('separates breaker partitions by api key hash and model metadata', () => {
    const base = openAiCircuitBreakerKey({
      apiKey: 'sk-first',
      model: 'gpt-5.4',
      serviceTier: 'default',
    });
    const differentKey = openAiCircuitBreakerKey({
      apiKey: 'sk-second',
      model: 'gpt-5.4',
      serviceTier: 'default',
    });
    const differentModel = openAiCircuitBreakerKey({
      apiKey: 'sk-first',
      model: 'gpt-5.4-mini',
      serviceTier: 'default',
    });

    expect(base).not.toBe(differentKey);
    expect(base).not.toBe(differentModel);
  });
});
