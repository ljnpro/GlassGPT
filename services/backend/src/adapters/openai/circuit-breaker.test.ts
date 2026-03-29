import { describe, expect, it } from 'vitest';

import { CircuitBreaker } from './circuit-breaker.js';

describe('CircuitBreaker', () => {
  it('starts in closed state', () => {
    const cb = new CircuitBreaker();
    expect(cb.isOpen).toBe(false);
    expect(cb.currentState).toBe('closed');
  });

  it('stays closed after fewer failures than threshold', () => {
    const cb = new CircuitBreaker();
    for (let i = 0; i < 4; i++) {
      cb.recordFailure();
    }
    expect(cb.isOpen).toBe(false);
  });

  it('opens after 5 consecutive failures', () => {
    const cb = new CircuitBreaker();
    for (let i = 0; i < 5; i++) {
      cb.recordFailure();
    }
    expect(cb.isOpen).toBe(true);
    expect(cb.currentState).toBe('open');
  });

  it('resets failure count on success', () => {
    const cb = new CircuitBreaker();
    cb.recordFailure();
    cb.recordFailure();
    cb.recordFailure();
    cb.recordSuccess();
    cb.recordFailure();
    cb.recordFailure();
    // Only 2 consecutive failures after success, should not be open
    expect(cb.isOpen).toBe(false);
  });

  it('success after open transitions to closed', () => {
    const cb = new CircuitBreaker();
    for (let i = 0; i < 5; i++) {
      cb.recordFailure();
    }
    expect(cb.isOpen).toBe(true);
    cb.recordSuccess();
    expect(cb.isOpen).toBe(false);
    expect(cb.currentState).toBe('closed');
  });

  it('rejects immediately when open', () => {
    const cb = new CircuitBreaker();
    for (let i = 0; i < 5; i++) {
      cb.recordFailure();
    }
    expect(cb.isOpen).toBe(true);
  });
});
