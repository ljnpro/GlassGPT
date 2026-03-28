export type ArtifactKind = 'image' | 'document' | 'code' | 'data';

export interface ArtifactRecord {
  readonly id: string;
  readonly conversationId: string;
  readonly runId: string;
  readonly kind: ArtifactKind;
  readonly filename: string;
  readonly contentType: string;
  readonly byteCount: number;
  readonly createdAt: string;
}
