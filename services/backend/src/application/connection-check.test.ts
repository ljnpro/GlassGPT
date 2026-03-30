import { describe, expect, it } from 'vitest';

import {
  AUTH_RUNTIME_CONFIGURATION_ERROR,
  appCompatibilityForVersion,
  authRuntimeConfigurationError,
  buildCompatibilityMetadata,
  buildConnectionCheck,
  buildUnsignedConnectionCheck,
} from './connection-check.js';

describe('connection-check', () => {
  it('marks matching and newer app versions as compatible', () => {
    expect(appCompatibilityForVersion('5.3.0')).toBe('compatible');
    expect(appCompatibilityForVersion('5.3.2')).toBe('compatible');
    expect(appCompatibilityForVersion('6.0.0')).toBe('compatible');
  });

  it('marks missing invalid and older app versions as update required', () => {
    expect(appCompatibilityForVersion(undefined)).toBe('update_required');
    expect(appCompatibilityForVersion('')).toBe('update_required');
    expect(appCompatibilityForVersion('broken-version')).toBe('update_required');
    expect(appCompatibilityForVersion('5.2.9')).toBe('update_required');
  });

  it('builds compatibility metadata from the client app version header', () => {
    expect(buildCompatibilityMetadata('5.3.0')).toEqual({
      appCompatibility: 'compatible',
      backendVersion: '5.3.2',
      minimumSupportedAppVersion: '5.3.0',
    });
    expect(buildCompatibilityMetadata('5.2.0')).toEqual({
      appCompatibility: 'update_required',
      backendVersion: '5.3.2',
      minimumSupportedAppVersion: '5.3.0',
    });
  });

  it('injects compatibility metadata into signed and unsigned connection checks', () => {
    expect(
      buildConnectionCheck({
        auth: 'healthy',
        clientAppVersion: '5.3.0',
        latencyMs: 0,
        openaiCredential: 'healthy',
      }).appCompatibility,
    ).toBe('compatible');

    expect(buildUnsignedConnectionCheck('5.2.0').appCompatibility).toBe('update_required');
  });

  it('detects missing auth runtime secrets', () => {
    expect(
      authRuntimeConfigurationError({
        APPLE_AUDIENCE: 'space.manus.liquid.glass.chat.t20260308214621',
        APPLE_BUNDLE_ID: 'space.manus.liquid.glass.chat.t20260308214621',
        CREDENTIAL_ENCRYPTION_KEY: '',
        CREDENTIAL_ENCRYPTION_KEY_VERSION: 'v1',
        REFRESH_TOKEN_SIGNING_KEY: 'refresh',
        SESSION_SIGNING_KEY: 'session',
      }),
    ).toBe(AUTH_RUNTIME_CONFIGURATION_ERROR);
  });
});
