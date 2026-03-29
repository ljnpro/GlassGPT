import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { parseOptionalJSONPayload } from './json-payload-codec.js';

describe('parseOptionalJSONPayload', () => {
  it('returns undefined when the payload is absent or malformed', () => {
    const schema = z.object({ value: z.string() });

    expect(parseOptionalJSONPayload(null, schema)).toBeUndefined();
    expect(parseOptionalJSONPayload('not-json', schema)).toBeUndefined();
    expect(parseOptionalJSONPayload(JSON.stringify({ value: 42 }), schema)).toBeUndefined();
  });

  it('returns parsed data when the payload matches the schema', () => {
    const schema = z.object({ value: z.string() });

    expect(parseOptionalJSONPayload(JSON.stringify({ value: 'ok' }), schema)).toEqual({
      value: 'ok',
    });
  });
});
