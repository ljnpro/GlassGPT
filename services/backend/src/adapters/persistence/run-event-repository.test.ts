import { describe, expect, it, vi } from 'vitest';

import type { RunEventRecord } from '../../domain/run-event-model.js';
import type { BackendEnv } from './env.js';
import { listRunEventsForUser, updateRunEventSnapshots } from './run-event-repository.js';

interface FakeDatabaseOptions {
  readonly allResults?: unknown[];
}

const createFakeEnv = (options?: FakeDatabaseOptions) => {
  const prepare = vi.fn((_sql: string) => {
    return {
      bind: (..._args: unknown[]) => {
        return {
          all: async () => ({ results: options?.allResults ?? [] }),
          first: async () => null,
          run: async () => ({ success: true }),
        };
      },
    };
  });

  const env = {
    AGENT_RUN_WORKFLOW: {} as Env['AGENT_RUN_WORKFLOW'],
    APPLE_AUDIENCE: 'com.glassgpt.app',
    APPLE_BUNDLE_ID: 'com.glassgpt.app',
    APP_ENV: 'beta',
    CHAT_RUN_WORKFLOW: {} as Env['CHAT_RUN_WORKFLOW'],
    CONVERSATION_EVENT_HUB: {} as Env['CONVERSATION_EVENT_HUB'],
    CREDENTIAL_ENCRYPTION_KEY: '00',
    CREDENTIAL_ENCRYPTION_KEY_VERSION: 'v1',
    GLASSGPT_ARTIFACTS: {} as R2Bucket,
    GLASSGPT_DB: {
      prepare,
    } as D1Database,
    R2_BUCKET_NAME: 'glassgpt-beta-artifacts',
    REFRESH_TOKEN_SIGNING_KEY: '11',
    SESSION_SIGNING_KEY: '22',
  } as BackendEnv;

  return {
    env,
    prepare,
  };
};

describe('run-event-repository', () => {
  it('marks a run event as committed when snapshots are written', async () => {
    const { env, prepare } = createFakeEnv();

    await updateRunEventSnapshots(env, {
      artifact: null,
      artifactId: null,
      conversation: null,
      conversationId: 'conv_01',
      createdAt: '2026-03-27T12:00:00.000Z',
      cursor: 'cur_00000000000000000001',
      id: 'evt_01',
      kind: 'run_queued',
      message: null,
      progressLabel: null,
      run: {
        conversationId: 'conv_01',
        createdAt: '2026-03-27T12:00:00.000Z',
        id: 'run_01',
        kind: 'agent',
        lastEventCursor: 'cur_00000000000000000001',
        stage: 'leader_planning',
        status: 'queued',
        updatedAt: '2026-03-27T12:00:00.000Z',
        userId: 'usr_01',
        visibleSummary: 'Queued agent workflow',
      },
      runId: 'run_01',
      stage: 'leader_planning',
      textDelta: null,
    } satisfies RunEventRecord);

    expect(prepare).toHaveBeenCalledTimes(1);
    expect(prepare.mock.calls[0]?.[0]).toContain('committed = 1');
  });

  it('only lists committed run events for sync replay', async () => {
    const { env, prepare } = createFakeEnv({
      allResults: [
        {
          artifactId: null,
          artifactSnapshotJSON: null,
          conversationId: 'conv_01',
          conversationSnapshotJSON: JSON.stringify({
            createdAt: '2026-03-27T12:00:00.000Z',
            id: 'conv_01',
            lastRunId: 'run_01',
            lastSyncCursor: 'cur_00000000000000000005',
            mode: 'agent',
            title: 'Agent Conversation',
            updatedAt: '2026-03-27T12:00:00.000Z',
            userId: 'usr_01',
          }),
          createdAt: '2026-03-27T12:00:00.000Z',
          cursorSequence: 5,
          id: 'evt_05',
          kind: 'run_completed',
          messageSnapshotJSON: null,
          progressLabel: null,
          runId: 'run_01',
          runSnapshotJSON: JSON.stringify({
            conversationId: 'conv_01',
            createdAt: '2026-03-27T12:00:00.000Z',
            id: 'run_01',
            kind: 'agent',
            lastEventCursor: 'cur_00000000000000000005',
            stage: 'final_synthesis',
            status: 'completed',
            updatedAt: '2026-03-27T12:00:00.000Z',
            userId: 'usr_01',
            visibleSummary: 'Done',
          }),
          stage: 'final_synthesis',
          textDelta: null,
        },
      ],
    });

    const events = await listRunEventsForUser(env, 'usr_01', null, 50);

    expect(prepare).toHaveBeenCalledTimes(1);
    expect(prepare.mock.calls[0]?.[0]).toContain('run_events.committed = 1');
    expect(events).toHaveLength(1);
    expect(events[0]?.cursor).toBe('cur_00000000000000000005');
    expect(events[0]?.run?.status).toBe('completed');
  });
});
