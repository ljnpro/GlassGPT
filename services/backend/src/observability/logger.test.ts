import { describe, expect, it } from 'vitest';

import { sanitizeLogValue } from './logger.js';

describe('sanitizeLogValue', () => {
  it('truncates long messages to 200 chars', () => {
    const long = 'a'.repeat(300);
    const result = sanitizeLogValue(long);
    expect(result.length).toBeLessThanOrEqual(204); // 200 + "..."
    expect(result.endsWith('...')).toBe(true);
  });

  it('passes short messages through unchanged', () => {
    expect(sanitizeLogValue('short error')).toBe('short error');
  });

  it('masks OpenAI API keys', () => {
    const result = sanitizeLogValue('Error with key sk-proj1234567890abcdef in request');
    expect(result).not.toContain('sk-proj1234567890abcdef');
    expect(result).toContain('sk-***');
  });

  it('masks Bearer tokens', () => {
    const result = sanitizeLogValue('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9');
    expect(result).not.toContain('eyJhbGciOiJIUzI1NiJ9');
    expect(result).toContain('Bearer ***');
  });

  it('handles empty strings', () => {
    expect(sanitizeLogValue('')).toBe('');
  });

  it('masks multiple API keys in one message', () => {
    const result = sanitizeLogValue('keys: sk-abc123defghijk and sk-xyz789uvwxyzab');
    expect(result).not.toContain('sk-abc123defghijk');
    expect(result).not.toContain('sk-xyz789uvwxyzab');
  });
});
