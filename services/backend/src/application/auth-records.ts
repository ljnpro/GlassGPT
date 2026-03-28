export interface UserRecord {
  readonly appleSubject: string;
  readonly createdAt: string;
  readonly displayName: string | null;
  readonly email: string | null;
  readonly id: string;
}

export interface SessionRecord {
  readonly accessExpiresAt: string;
  readonly createdAt: string;
  readonly deviceId: string;
  readonly id: string;
  readonly refreshExpiresAt: string;
  readonly refreshTokenHash: string;
  readonly revokedAt: string | null;
  readonly userId: string;
}

export interface ProviderCredentialRecord {
  readonly checkedAt: string | null;
  readonly ciphertext: string;
  readonly createdAt: string;
  readonly id: string;
  readonly keyVersion: string;
  readonly lastErrorSummary: string | null;
  readonly nonce: string;
  readonly provider: 'openai';
  readonly status: 'invalid' | 'missing' | 'valid';
  readonly updatedAt: string;
  readonly userId: string;
}
