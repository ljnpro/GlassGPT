import type { SyncEnvelopeDTO } from '@glassgpt/backend-contracts';

import type { RunEventRecord } from '../domain/run-event-model.js';
import { buildSyncEnvelopeDTO } from './dto-mappers.js';
import { ApplicationError } from './errors.js';
import { parseCursorSequence } from './ids.js';
import type { BackendRuntimeContext } from './runtime-context.js';

const DEFAULT_SYNC_LIMIT = 200;

export interface SyncServiceDependencies {
  readonly listRunEventsForUser: (
    env: BackendRuntimeContext,
    userId: string,
    afterCursorSequence: number | null,
    limit: number,
  ) => Promise<RunEventRecord[]>;
}

export interface SyncService {
  syncEvents(
    env: BackendRuntimeContext,
    userId: string,
    afterCursor: string | null,
  ): Promise<SyncEnvelopeDTO>;
}

export const createSyncService = (deps: SyncServiceDependencies): SyncService => {
  return {
    syncEvents: async (env, userId, afterCursor) => {
      const afterCursorSequence = (() => {
        if (!afterCursor) {
          return null;
        }

        try {
          return parseCursorSequence(afterCursor);
        } catch {
          throw new ApplicationError('invalid_request', 'invalid_sync_cursor');
        }
      })();
      const events = await deps.listRunEventsForUser(
        env,
        userId,
        afterCursorSequence,
        DEFAULT_SYNC_LIMIT,
      );
      const nextCursor = events.length > 0 ? (events[events.length - 1]?.cursor ?? null) : null;
      return buildSyncEnvelopeDTO(events, nextCursor);
    },
  };
};
