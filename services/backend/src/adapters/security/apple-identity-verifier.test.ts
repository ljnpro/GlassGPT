import { describe, expect, it } from 'vitest';

import { InvalidAppleIdentityTokenError } from '../../application/errors.js';
import { verifyAppleIdentityToken } from './apple-identity-verifier.js';

describe('verifyAppleIdentityToken', () => {
  it('fails fast when the configured Apple audience and bundle id disagree', async () => {
    await expect(
      verifyAppleIdentityToken(
        {
          APPLE_AUDIENCE: 'space.manus.glassgpt',
          APPLE_BUNDLE_ID: 'space.manus.glassgpt.mismatch',
        } as Env,
        'not-a-real-token',
      ),
    ).rejects.toEqual(new InvalidAppleIdentityTokenError('apple_bundle_id_mismatch'));
  });
});
