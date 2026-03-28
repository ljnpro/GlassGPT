import { describe, expect, it } from 'vitest';

import { ApplicationError } from '../application/errors.js';
import { createApp } from './app.js';
import type {
  AgentRunService,
  AuthService,
  BackendServices,
  ChatRunService,
  ConversationService,
  CredentialService,
  RunService,
  SyncService,
} from './services.js';

const unexpectedBindingAccess = (bindingName: string): never => {
  throw new Error(`${bindingName}_binding_accessed_in_scaffold_test`);
};

const createWorkflowStub = (): Env['CHAT_RUN_WORKFLOW'] => {
  return {
    async create(options: { id: string }) {
      return { id: options.id };
    },
  } as Env['CHAT_RUN_WORKFLOW'];
};

const createDatabaseStub = (): D1Database => {
  return {
    prepare: () => ({
      bind: () => ({
        first: async () => unexpectedBindingAccess('d1'),
        run: async () => unexpectedBindingAccess('d1'),
      }),
    }),
  } as D1Database;
};

const createArtifactBucketStub = (): R2Bucket => {
  return {
    get: async () => unexpectedBindingAccess('r2'),
    put: async () => unexpectedBindingAccess('r2'),
    delete: async () => unexpectedBindingAccess('r2'),
  } as R2Bucket;
};

const createConversationEventHubStub = (): Env['CONVERSATION_EVENT_HUB'] => {
  return {
    idFromName: () => ({ toString: () => 'conversation-event-hub-id' }) as DurableObjectId,
    get: () =>
      ({
        fetch: async () => unexpectedBindingAccess('durable_object'),
      }) as DurableObjectStub,
  } as Env['CONVERSATION_EVENT_HUB'];
};

const sessionFixture = {
  accessToken: 'access-token',
  deviceId: 'device_01',
  expiresAt: '2026-03-27T12:00:00.000Z',
  refreshToken: 'refresh-token',
  user: {
    appleSubject: 'apple_subject_01',
    createdAt: '2026-03-27T00:00:00.000Z',
    displayName: 'Glass User',
    email: 'glass@example.com',
    id: 'usr_01',
  },
} as const;

const credentialStatusFixture = {
  checkedAt: '2026-03-27T12:00:00.000Z',
  lastErrorSummary: undefined,
  provider: 'openai',
  state: 'valid',
} as const;

const testEnv: Env = {
  APP_ENV: 'beta',
  R2_BUCKET_NAME: 'glassgpt-beta-artifacts',
  CHAT_RUN_WORKFLOW: createWorkflowStub(),
  AGENT_RUN_WORKFLOW: createWorkflowStub(),
  CONVERSATION_EVENT_HUB: createConversationEventHubStub(),
  GLASSGPT_ARTIFACTS: createArtifactBucketStub(),
  GLASSGPT_DB: createDatabaseStub(),
};

const createAuthServiceStub = (): AuthService => {
  return {
    authenticateWithApple: async () => sessionFixture,
    fetchCurrentUser: async (_env, accessToken) => {
      if (accessToken !== 'access-token') {
        throw new ApplicationError('unauthorized', 'invalid_access_token');
      }

      return sessionFixture.user;
    },
    logout: async (_env, accessToken) => {
      if (accessToken !== 'access-token') {
        throw new ApplicationError('unauthorized', 'invalid_access_token');
      }
    },
    refreshSession: async () => ({
      ...sessionFixture,
      accessToken: 'refreshed-access-token',
      refreshToken: 'refreshed-refresh-token',
    }),
    resolveSession: async (_env, accessToken) => {
      if (accessToken !== 'access-token') {
        throw new ApplicationError('unauthorized', 'invalid_access_token');
      }

      return {
        deviceId: sessionFixture.deviceId,
        sessionId: 'ses_01',
        user: sessionFixture.user,
        userId: sessionFixture.user.id,
      };
    },
  };
};

const createCredentialServiceStub = (): CredentialService => {
  return {
    deleteOpenAiKey: async () => {},
    readOpenAiKeyStatus: async () => credentialStatusFixture,
    storeOpenAiKey: async () => credentialStatusFixture,
  };
};

const chatConversationFixture = {
  createdAt: '2026-03-27T12:00:00.000Z',
  id: 'conv_chat_01',
  lastRunId: 'run_chat_01',
  lastSyncCursor: 'cur_00000000000000000001',
  mode: 'chat',
  title: 'Glass Chat Conversation',
  updatedAt: '2026-03-27T12:00:00.000Z',
} as const;

const agentConversationFixture = {
  createdAt: '2026-03-27T12:00:00.000Z',
  id: 'conv_agent_01',
  lastRunId: 'run_agent_01',
  lastSyncCursor: 'cur_00000000000000000002',
  mode: 'agent',
  title: 'Glass Agent Conversation',
  updatedAt: '2026-03-27T12:00:00.000Z',
} as const;

const chatRunFixture = {
  conversationId: chatConversationFixture.id,
  createdAt: '2026-03-27T12:00:00.000Z',
  id: 'run_chat_01',
  kind: 'chat',
  lastEventCursor: 'cur_00000000000000000001',
  status: 'queued',
  updatedAt: '2026-03-27T12:00:00.000Z',
  visibleSummary: 'Queued chat run',
} as const;

const agentRunFixture = {
  conversationId: agentConversationFixture.id,
  createdAt: '2026-03-27T12:00:00.000Z',
  id: 'run_agent_01',
  kind: 'agent',
  lastEventCursor: 'cur_00000000000000000002',
  stage: 'leader_planning',
  status: 'queued',
  updatedAt: '2026-03-27T12:00:00.000Z',
  visibleSummary: 'Queued agent run',
} as const;

const createConversationServiceStub = (): ConversationService => {
  return {
    createConversation: async (_env, _userId, input) => ({
      ...(input.mode === 'chat' ? chatConversationFixture : agentConversationFixture),
      mode: input.mode,
      title: input.title,
    }),
    getConversationDetail: async (_env, _userId, conversationId) => ({
      conversation:
        conversationId === agentConversationFixture.id
          ? agentConversationFixture
          : chatConversationFixture,
      messages: [],
      runs: conversationId === agentConversationFixture.id ? [agentRunFixture] : [chatRunFixture],
    }),
    listConversations: async () => [chatConversationFixture, agentConversationFixture],
  };
};

const createChatRunServiceStub = (): ChatRunService => {
  return {
    cancelRun: async () => ({
      ...chatRunFixture,
      status: 'cancelled',
      visibleSummary: 'Run cancelled',
    }),
    executeQueuedRun: async () => {},
    getRun: async () => chatRunFixture,
    queueChatRun: async () => chatRunFixture,
    retryRun: async (_env, _workflow, _userId, _runId) => ({
      ...chatRunFixture,
      id: 'run_chat_retry_01',
    }),
  };
};

const createAgentRunServiceStub = (): AgentRunService => {
  return {
    cancelRun: async () => ({
      ...agentRunFixture,
      status: 'cancelled',
      visibleSummary: 'Agent run cancelled',
    }),
    completeRun: async () => {},
    executeFinalSynthesis: async () => 'Final synthesis',
    executeLeaderPlanning: async () => 'Leader plan',
    executeLeaderReview: async () => 'Leader review',
    executeWorkerWave: async () => 'Worker report',
    failRun: async () => {},
    getRun: async () => agentRunFixture,
    queueAgentRun: async () => agentRunFixture,
    retryRun: async (_env, _workflow, _userId, _runId) => ({
      ...agentRunFixture,
      id: 'run_agent_retry_01',
    }),
    startQueuedRun: async () => true,
  };
};

const createRunServiceStub = (): RunService => {
  return {
    cancelRun: async (_env, _userId, runId) => {
      return runId.startsWith('run_agent')
        ? { ...agentRunFixture, status: 'cancelled', visibleSummary: 'Agent run cancelled' }
        : { ...chatRunFixture, status: 'cancelled', visibleSummary: 'Run cancelled' };
    },
    getRun: async (_env, _userId, runId) => {
      return runId.startsWith('run_agent') ? agentRunFixture : chatRunFixture;
    },
    retryRun: async (_env, _workflows, _userId, runId) => {
      return runId.startsWith('run_agent')
        ? { ...agentRunFixture, id: 'run_agent_retry_01' }
        : {
            ...chatRunFixture,
            id: 'run_chat_retry_01',
          };
    },
  };
};

const createSyncServiceStub = (): SyncService => {
  return {
    syncEvents: async () => ({
      events: [],
      nextCursor: null,
    }),
  };
};

const createTestServices = (): BackendServices => {
  return {
    agentRunService: createAgentRunServiceStub(),
    authService: createAuthServiceStub(),
    chatRunService: createChatRunServiceStub(),
    conversationService: createConversationServiceStub(),
    credentialService: createCredentialServiceStub(),
    runService: createRunServiceStub(),
    syncService: createSyncServiceStub(),
  };
};

const testExecutionContext = {
  waitUntil: (_promise: Promise<unknown>): void => {},
  passThroughOnException: (): void => {},
} as ExecutionContext;

describe('backend worker scaffold', () => {
  it('serves the health route', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/healthz'),
      testEnv,
      testExecutionContext,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      ok: true,
    });
  });

  it('serves the unsigned connection check route', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/connection/check'),
      testEnv,
      testExecutionContext,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      backend: 'healthy',
      auth: 'missing',
      openaiCredential: 'missing',
      sse: 'healthy',
    });
  });

  it('exposes scaffolded conversation and run routes', async () => {
    const app = createApp(createTestServices());

    const listResponse = await app.fetch(
      new Request('https://example.com/v1/conversations', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(listResponse.status).toBe(200);
    await expect(listResponse.json()).resolves.toEqual([
      chatConversationFixture,
      agentConversationFixture,
    ]);

    const createResponse = await app.fetch(
      new Request('https://example.com/v1/conversations', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer access-token',
          'content-type': 'application/json',
        },
        body: JSON.stringify({ title: 'Scaffold', mode: 'chat' }),
      }),
      testEnv,
      testExecutionContext,
    );
    expect(createResponse.status).toBe(201);
    await expect(createResponse.json()).resolves.toMatchObject({
      title: 'Scaffold',
      mode: 'chat',
    });

    const chatRunResponse = await app.fetch(
      new Request(`https://example.com/v1/conversations/${chatConversationFixture.id}/messages`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer access-token',
          'content-type': 'application/json',
        },
        body: JSON.stringify({ content: 'Hello' }),
      }),
      testEnv,
      testExecutionContext,
    );
    expect(chatRunResponse.status).toBe(202);
    await expect(chatRunResponse.json()).resolves.toMatchObject({
      conversationId: chatConversationFixture.id,
      kind: 'chat',
      status: 'queued',
    });

    const runDetailResponse = await app.fetch(
      new Request(`https://example.com/v1/runs/${chatRunFixture.id}`, {
        headers: { Authorization: 'Bearer access-token' },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(runDetailResponse.status).toBe(200);
    await expect(runDetailResponse.json()).resolves.toMatchObject({
      id: chatRunFixture.id,
      kind: 'chat',
    });

    const chatRetryResponse = await app.fetch(
      new Request(`https://example.com/v1/runs/${chatRunFixture.id}/retry`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer access-token',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(chatRetryResponse.status).toBe(202);
    await expect(chatRetryResponse.json()).resolves.toMatchObject({
      id: 'run_chat_retry_01',
      kind: 'chat',
      status: 'queued',
    });

    const agentRunResponse = await app.fetch(
      new Request(
        `https://example.com/v1/conversations/${agentConversationFixture.id}/agent-runs`,
        {
          method: 'POST',
          headers: {
            Authorization: 'Bearer access-token',
            'content-type': 'application/json',
          },
          body: JSON.stringify({ prompt: 'Investigate' }),
        },
      ),
      testEnv,
      testExecutionContext,
    );
    expect(agentRunResponse.status).toBe(202);
    await expect(agentRunResponse.json()).resolves.toMatchObject({
      conversationId: agentConversationFixture.id,
      kind: 'agent',
      status: 'queued',
      stage: 'leader_planning',
    });

    const agentCancelResponse = await app.fetch(
      new Request(`https://example.com/v1/runs/${agentRunFixture.id}/cancel`, {
        method: 'POST',
        headers: { Authorization: 'Bearer access-token' },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(agentCancelResponse.status).toBe(200);
    await expect(agentCancelResponse.json()).resolves.toMatchObject({
      id: agentRunFixture.id,
      kind: 'agent',
      status: 'cancelled',
    });
  });

  it('exposes scaffolded auth, credential, sync, and error routes', async () => {
    const app = createApp(createTestServices());

    const meResponse = await app.fetch(
      new Request('https://example.com/v1/me'),
      testEnv,
      testExecutionContext,
    );
    expect(meResponse.status).toBe(401);

    const appleAuthResponse = await app.fetch(
      new Request('https://example.com/v1/auth/apple', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          identityToken: 'identity-token',
          deviceId: 'device_01',
          email: 'glass@example.com',
          givenName: 'Glass',
          familyName: 'User',
        }),
      }),
      testEnv,
      testExecutionContext,
    );
    expect(appleAuthResponse.status).toBe(200);
    await expect(appleAuthResponse.json()).resolves.toMatchObject({
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    });

    const currentUserResponse = await app.fetch(
      new Request('https://example.com/v1/me', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(currentUserResponse.status).toBe(200);
    await expect(currentUserResponse.json()).resolves.toMatchObject({
      id: 'usr_01',
    });

    const refreshResponse = await app.fetch(
      new Request('https://example.com/v1/auth/refresh', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ refreshToken: 'refresh-token' }),
      }),
      testEnv,
      testExecutionContext,
    );
    expect(refreshResponse.status).toBe(200);
    await expect(refreshResponse.json()).resolves.toMatchObject({
      accessToken: 'refreshed-access-token',
      refreshToken: 'refreshed-refresh-token',
    });

    const credentialResponse = await app.fetch(
      new Request('https://example.com/v1/credentials/openai', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer access-token',
          'content-type': 'application/json',
        },
        body: JSON.stringify({ apiKey: 'sk-example' }),
      }),
      testEnv,
      testExecutionContext,
    );
    expect(credentialResponse.status).toBe(200);
    await expect(credentialResponse.json()).resolves.toMatchObject({
      provider: 'openai',
      state: 'valid',
    });

    const syncResponse = await app.fetch(
      new Request('https://example.com/v1/sync/events?cursor=cur_00000000000000000001', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(syncResponse.status).toBe(200);
    await expect(syncResponse.json()).resolves.toEqual({
      nextCursor: null,
      events: [],
    });

    const notFoundResponse = await app.fetch(
      new Request('https://example.com/does-not-exist'),
      testEnv,
      testExecutionContext,
    );
    expect(notFoundResponse.status).toBe(404);
    await expect(notFoundResponse.json()).resolves.toEqual({
      error: 'not_found',
    });

    const logoutResponse = await app.fetch(
      new Request('https://example.com/v1/auth/logout', {
        method: 'POST',
        headers: { Authorization: 'Bearer access-token' },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(logoutResponse.status).toBe(204);

    const signedInConnectionResponse = await app.fetch(
      new Request('https://example.com/v1/connection/check', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(signedInConnectionResponse.status).toBe(200);
    await expect(signedInConnectionResponse.json()).resolves.toMatchObject({
      auth: 'healthy',
      openaiCredential: 'healthy',
    });
  });

  it('maps schema validation failures to invalid_request', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/auth/refresh', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({}),
      }),
      testEnv,
      testExecutionContext,
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: 'invalid_request',
    });
  });
});
