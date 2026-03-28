import { describe, expect, it } from 'vitest';

import { formatCursorSequence, parseCursorSequence } from './ids.js';

describe('cursor formatting', () => {
  it('formats cursor sequences into fixed-width sortable cursors', () => {
    expect(formatCursorSequence(42)).toBe('cur_00000000000000000042');
  });

  it('parses valid cursor sequences', () => {
    expect(parseCursorSequence('cur_00000000000000000042')).toBe(42);
  });

  it('rejects invalid cursor values', () => {
    expect(() => parseCursorSequence('cursor_legacy')).toThrow(/invalid_cursor_format/);
    expect(() => parseCursorSequence('cur_00000000000000000000')).toThrow(
      /invalid_cursor_sequence/,
    );
  });
});
