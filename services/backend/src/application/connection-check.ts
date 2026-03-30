import {
  type ConnectionCheckDTO,
  type CredentialStatusDTO,
  connectionCheckSchema,
} from '@glassgpt/backend-contracts';
import type { BackendSecretEnv } from './runtime-context.js';

export const BACKEND_VERSION = '5.4.0';
export const MINIMUM_SUPPORTED_APP_VERSION = '5.4.0';
export const APP_VERSION_HEADER = 'X-GlassGPT-App-Version';
export const AUTH_RUNTIME_CONFIGURATION_ERROR = 'auth_runtime_configuration_missing';

const REQUIRED_AUTH_SECRET_FIELDS = [
  'APPLE_AUDIENCE',
  'APPLE_BUNDLE_ID',
  'SESSION_SIGNING_KEY',
  'REFRESH_TOKEN_SIGNING_KEY',
  'CREDENTIAL_ENCRYPTION_KEY',
  'CREDENTIAL_ENCRYPTION_KEY_VERSION',
] as const;

export interface BuildConnectionCheckInput {
  readonly auth: ConnectionCheckDTO['auth'];
  readonly openaiCredential: ConnectionCheckDTO['openaiCredential'];
  readonly backend?: ConnectionCheckDTO['backend'];
  readonly clientAppVersion?: string | undefined;
  readonly sse?: ConnectionCheckDTO['sse'];
  readonly latencyMs?: number;
  readonly errorSummary?: string;
}

const parseVersionComponents = (value: string): number[] | null => {
  const match = value.trim().match(/^(\d+(?:\.\d+)*)/);
  if (!match) {
    return null;
  }

  const versionToken = match.at(1);
  if (!versionToken) {
    return null;
  }

  const components = versionToken.split('.').map((part) => Number.parseInt(part, 10));
  return components.every(Number.isFinite) ? components : null;
};

const compareVersions = (left: string, right: string): number => {
  const leftComponents = parseVersionComponents(left);
  const rightComponents = parseVersionComponents(right);
  if (!leftComponents || !rightComponents) {
    return Number.NaN;
  }

  const maxLength = Math.max(leftComponents.length, rightComponents.length);
  for (let index = 0; index < maxLength; index += 1) {
    const leftValue = leftComponents[index] ?? 0;
    const rightValue = rightComponents[index] ?? 0;
    if (leftValue !== rightValue) {
      return leftValue < rightValue ? -1 : 1;
    }
  }

  return 0;
};

export const appCompatibilityForVersion = (
  clientAppVersion: string | undefined,
): ConnectionCheckDTO['appCompatibility'] => {
  if (!clientAppVersion) {
    return 'update_required';
  }

  const comparison = compareVersions(clientAppVersion, MINIMUM_SUPPORTED_APP_VERSION);
  if (Number.isNaN(comparison)) {
    return 'update_required';
  }

  return comparison >= 0 ? 'compatible' : 'update_required';
};

export const buildCompatibilityMetadata = (
  clientAppVersion: string | undefined,
): Pick<
  ConnectionCheckDTO,
  'appCompatibility' | 'backendVersion' | 'minimumSupportedAppVersion'
> => ({
  appCompatibility: appCompatibilityForVersion(clientAppVersion),
  backendVersion: BACKEND_VERSION,
  minimumSupportedAppVersion: MINIMUM_SUPPORTED_APP_VERSION,
});

export const healthStateForCredentialStatus = (
  status: CredentialStatusDTO['state'],
): ConnectionCheckDTO['openaiCredential'] => {
  switch (status) {
    case 'valid':
      return 'healthy';
    case 'invalid':
      return 'invalid';
    case 'missing':
      return 'missing';
  }
};

export const authRuntimeConfigurationError = (
  env: Partial<BackendSecretEnv>,
): string | undefined => {
  const hasMissingSecret = REQUIRED_AUTH_SECRET_FIELDS.some((field) => {
    const value = env[field];
    return typeof value !== 'string' || value.trim().length === 0;
  });
  return hasMissingSecret ? AUTH_RUNTIME_CONFIGURATION_ERROR : undefined;
};

export const buildConnectionCheck = (input: BuildConnectionCheckInput): ConnectionCheckDTO => {
  return connectionCheckSchema.parse({
    backend: input.backend ?? 'healthy',
    auth: input.auth,
    openaiCredential: input.openaiCredential,
    sse: input.sse ?? 'healthy',
    checkedAt: new Date().toISOString(),
    latencyMilliseconds: input.latencyMs,
    errorSummary: input.errorSummary,
    ...buildCompatibilityMetadata(input.clientAppVersion),
  });
};

export const buildUnsignedConnectionCheck = (clientAppVersion?: string): ConnectionCheckDTO => {
  return buildConnectionCheck({
    auth: 'missing',
    clientAppVersion,
    openaiCredential: 'missing',
    latencyMs: 0,
  });
};
