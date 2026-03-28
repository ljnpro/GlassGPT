import {
  type ConnectionCheckDTO,
  type CredentialStatusDTO,
  connectionCheckSchema,
} from '@glassgpt/backend-contracts';

export interface BuildConnectionCheckInput {
  readonly auth: ConnectionCheckDTO['auth'];
  readonly openaiCredential: ConnectionCheckDTO['openaiCredential'];
  readonly backend?: ConnectionCheckDTO['backend'];
  readonly sse?: ConnectionCheckDTO['sse'];
  readonly latencyMs?: number;
  readonly errorSummary?: string;
}

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

export const buildConnectionCheck = (input: BuildConnectionCheckInput): ConnectionCheckDTO => {
  return connectionCheckSchema.parse({
    backend: input.backend ?? 'healthy',
    auth: input.auth,
    openaiCredential: input.openaiCredential,
    sse: input.sse ?? 'healthy',
    checkedAt: new Date().toISOString(),
    latencyMilliseconds: input.latencyMs,
    errorSummary: input.errorSummary,
  });
};

export const buildUnsignedConnectionCheck = (): ConnectionCheckDTO => {
  return buildConnectionCheck({
    auth: 'missing',
    openaiCredential: 'missing',
    latencyMs: 0,
  });
};
