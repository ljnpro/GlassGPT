import type { MessageRecord } from '../domain/message-model.js';
import type { RunRecord } from '../domain/run-model.js';
import type { ProviderCredentialRecord } from './auth-records.js';
import { ApplicationError } from './errors.js';
import type { LiveCitation, LiveFilePathAnnotation } from './live-stream-model.js';

export const requireValidCredential = (
  credential: ProviderCredentialRecord | null,
): ProviderCredentialRecord => {
  if (!credential || credential.status !== 'valid') {
    throw new ApplicationError('forbidden', 'openai_credential_unavailable');
  }

  return credential;
};

export const isTerminalRun = (run: RunRecord): boolean => {
  return run.status === 'completed' || run.status === 'failed' || run.status === 'cancelled';
};

export const normalizePrompt = (prompt: string | undefined): string | null => {
  const trimmed = prompt?.trim() ?? '';
  return trimmed.length > 0 ? trimmed : null;
};

export const compareMessages = (left: MessageRecord, right: MessageRecord): number => {
  if (left.createdAt !== right.createdAt) {
    return left.createdAt.localeCompare(right.createdAt);
  }

  return left.id.localeCompare(right.id);
};

export const mergeLiveCitations = (
  citations: readonly LiveCitation[],
  nextCitation: LiveCitation,
): LiveCitation[] => {
  if (
    citations.some(
      (candidate) =>
        candidate.url === nextCitation.url &&
        candidate.title === nextCitation.title &&
        candidate.startIndex === nextCitation.startIndex &&
        candidate.endIndex === nextCitation.endIndex,
    )
  ) {
    return [...citations];
  }

  return [...citations, nextCitation];
};

export const mergeLiveFilePathAnnotations = (
  annotations: readonly LiveFilePathAnnotation[],
  nextAnnotation: LiveFilePathAnnotation,
): LiveFilePathAnnotation[] => {
  if (
    annotations.some(
      (candidate) =>
        candidate.fileId === nextAnnotation.fileId &&
        candidate.containerId === nextAnnotation.containerId &&
        candidate.sandboxPath === nextAnnotation.sandboxPath &&
        candidate.filename === nextAnnotation.filename &&
        candidate.startIndex === nextAnnotation.startIndex &&
        candidate.endIndex === nextAnnotation.endIndex,
    )
  ) {
    return [...annotations];
  }

  return [...annotations, nextAnnotation];
};
