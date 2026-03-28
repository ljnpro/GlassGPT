import { describe, expect, it } from 'vitest';
import type { RunEventRecord } from '../domain/run-event-model.js';
import type { ApplicationError } from './errors.js';
import type { BackendRuntimeContext } from './runtime-context.js';
import { createSyncService } from './sync-service.js';

const testEnv = {
  AGENT_RUN_WORKFLOW: {} as Env['AGENT_RUN_WORKFLOW'],
  APPLE_AUDIENCE: 'com.glassgpt.app',
  APPLE_BUNDLE_ID: 'com.glassgpt.app',
  APP_ENV: 'beta',
  CHAT_RUN_WORKFLOW: {} as Env['CHAT_RUN_WORKFLOW'],
  CONVERSATION_EVENT_HUB: {} as Env['CONVERSATION_EVENT_HUB'],
  CREDENTIAL_ENCRYPTION_KEY: '00',
  CREDENTIAL_ENCRYPTION_KEY_VERSION: 'v1',
  GLASSGPT_ARTIFACTS: {} as R2Bucket,
  GLASSGPT_DB: {} as D1Database,
  R2_BUCKET_NAME: 'glassgpt-beta-artifacts',
  REFRESH_TOKEN_SIGNING_KEY: '11',
  SESSION_SIGNING_KEY: '22',
} as BackendRuntimeContext;

const eventFixture = (cursor: string, kind: RunEventRecord['kind']): RunEventRecord => {
  return {
    artifact: null,
    artifactId: null,
    conversation: null,
    conversationId: 'conv_01',
    createdAt: '2026-03-27T12:00:00.000Z',
    cursor,
    id: `evt_${cursor}`,
    kind,
    message: null,
    progressLabel: null,
    run: null,
    runId: 'run_01',
    stage: null,
    textDelta: null,
  };
};

describe('createSyncService', () => {
  it('parses monotonic cursors before loading the next batch', async () => {
    const calls: Array<number | null> = [];
    const service = createSyncService({
      listRunEventsForUser: async (_env, _userId, afterCursorSequence) => {
        calls.push(afterCursorSequence);
        return [
          eventFixture('cur_00000000000000000003', 'run_progress'),
          eventFixture('cur_00000000000000000004', 'assistant_delta'),
        ];
      },
    });

    const envelope = await service.syncEvents(testEnv, 'usr_01', 'cur_00000000000000000002');

    expect(calls).toEqual([2]);
    expect(envelope.nextCursor).toBe('cur_00000000000000000004');
    expect(envelope.events).toHaveLength(2);
  });

  it('rejects invalid sync cursors as invalid_request', async () => {
    const service = createSyncService({
      listRunEventsForUser: async () => [],
    });

    await expect(service.syncEvents(testEnv, 'usr_01', 'cursor_legacy')).rejects.toMatchObject({
      code: 'invalid_request',
    } satisfies Partial<ApplicationError>);
  });
});
