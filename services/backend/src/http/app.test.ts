import { describe, expect, it, vi } from 'vitest';
import { ApplicationError } from '../application/errors.js';
import * as logger from '../observability/logger.js';
import { createApp } from './app.js';
import {
  ANONYMOUS_MAX_REQUESTS_PER_WINDOW,
  AUTHENTICATED_MAX_REQUESTS_PER_WINDOW,
} from './middleware/rate-limiter.js';
import type {
  AgentRunService,
  AuthService,
  BackendServices,
  ChatRunService,
  ConversationService,
  CredentialService,
  RateLimitService,
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
  const rateLimitWindows = new Map<
    string,
    {
      readonly requestCount: number;
      readonly updatedAtMs: number;
      readonly windowStartMs: number;
    }
  >();

  return {
    prepare: (query: string) => ({
      bind: (...params: unknown[]) => ({
        first: async () => {
          if (query.includes('FROM rate_limit_windows')) {
            const bucketKey = String(params[0]);
            const entry = rateLimitWindows.get(bucketKey);
            if (!entry) {
              return null;
            }

            return {
              bucketKey,
              requestCount: entry.requestCount,
              updatedAtMs: entry.updatedAtMs,
              windowStartMs: entry.windowStartMs,
            };
          }

          return unexpectedBindingAccess('d1');
        },
        run: async () => {
          if (query.includes('INSERT INTO rate_limit_windows')) {
            rateLimitWindows.set(String(params[0]), {
              requestCount: Number(params[2]),
              updatedAtMs: Number(params[3]),
              windowStartMs: Number(params[1]),
            });
            return { success: true };
          }

          if (query.includes('DELETE FROM rate_limit_windows')) {
            const olderThanMs = Number(params[0]);
            for (const [bucketKey, entry] of rateLimitWindows.entries()) {
              if (entry.updatedAtMs < olderThanMs) {
                rateLimitWindows.delete(bucketKey);
              }
            }
            return { success: true };
          }

          return unexpectedBindingAccess('d1');
        },
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

const createConversationEventHubStub = (
  fetchImpl?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>,
): Env['CONVERSATION_EVENT_HUB'] => {
  return {
    idFromName: () => ({ toString: () => 'conversation-event-hub-id' }) as DurableObjectId,
    get: () =>
      ({
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          if (fetchImpl) {
            return fetchImpl(input, init);
          }
          return unexpectedBindingAccess('durable_object');
        },
      }) as DurableObjectStub,
  } as Env['CONVERSATION_EVENT_HUB'];
};

const createSSEStreamResponse = (frames: readonly string[]): Response => {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const frame of frames) {
        controller.enqueue(encoder.encode(frame));
      }
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream' },
    status: 200,
  });
};

const createFailingSSEStreamResponse = (
  frames: readonly string[],
  errorMessage = 'conversation_event_hub_stream_failed',
): Response => {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const frame of frames) {
        controller.enqueue(encoder.encode(frame));
      }
      controller.error(new Error(errorMessage));
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream' },
    status: 200,
  });
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

const createTestEnv = (overrides: Partial<Env> = {}): Env => ({
  APP_ENV: 'beta',
  APPLE_AUDIENCE: 'space.manus.liquid.glass.chat.t20260308214621',
  APPLE_BUNDLE_ID: 'space.manus.liquid.glass.chat.t20260308214621',
  CREDENTIAL_ENCRYPTION_KEY: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  CREDENTIAL_ENCRYPTION_KEY_VERSION: 'v1',
  CORS_ALLOWED_ORIGINS:
    'https://glassgpt.com,https://beta.glassgpt.com,https://staging.glassgpt.com,http://localhost:3000,http://127.0.0.1:3000,http://localhost:5173,http://127.0.0.1:5173',
  REFRESH_TOKEN_SIGNING_KEY: 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
  R2_BUCKET_NAME: 'glassgpt-beta-artifacts',
  SESSION_SIGNING_KEY: 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
  CHAT_RUN_WORKFLOW: createWorkflowStub(),
  AGENT_RUN_WORKFLOW: createWorkflowStub(),
  CONVERSATION_EVENT_HUB: createConversationEventHubStub(),
  GLASSGPT_ARTIFACTS: createArtifactBucketStub(),
  GLASSGPT_DB: createDatabaseStub(),
  ...overrides,
});

const testEnv: Env = createTestEnv();

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
  processSnapshotJSON: JSON.stringify({
    activity: 'delegation',
    activeTaskIDs: ['task_01'],
    leaderLiveStatus: 'Workers running',
    leaderLiveSummary: 'Workers running',
    recentUpdateItems: [],
    tasks: [
      {
        id: 'task_01',
        status: 'running',
        title: 'Inspect evidence',
      },
    ],
  }),
  stage: 'leader_planning',
  status: 'queued',
  updatedAt: '2026-03-27T12:00:00.000Z',
  visibleSummary: 'Queued agent run',
} as const;

const createConversationServiceStub = (): ConversationService => {
  return {
    createConversation: async (_env, _userId, input) => ({
      ...(input.mode === 'chat' ? chatConversationFixture : agentConversationFixture),
      agentWorkerReasoningEffort: input.agentWorkerReasoningEffort,
      model: input.model,
      mode: input.mode,
      reasoningEffort: input.reasoningEffort,
      serviceTier: input.serviceTier,
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
    listConversations: async () => ({
      hasMore: false,
      items: [chatConversationFixture, agentConversationFixture],
      nextCursor: undefined,
    }),
    updateConversationConfiguration: async (_env, _userId, conversationId, input) => ({
      ...(conversationId === agentConversationFixture.id
        ? agentConversationFixture
        : chatConversationFixture),
      agentWorkerReasoningEffort: input.agentWorkerReasoningEffort,
      id: conversationId,
      model: input.model,
      reasoningEffort: input.reasoningEffort,
      serviceTier: input.serviceTier,
    }),
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

const createRunServiceStub = (overrides: Partial<RunService> = {}): RunService => {
  const base: RunService = {
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

  return {
    ...base,
    ...overrides,
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

const createRateLimitServiceStub = (): RateLimitService => {
  const windows = new Map<
    string,
    {
      readonly requestCount: number;
      readonly updatedAtMs: number;
      readonly windowStartMs: number;
    }
  >();

  return {
    consumeRequest: async (_env, input) => {
      for (const [bucketKey, entry] of windows.entries()) {
        if (entry.updatedAtMs < input.nowMs - input.staleWindowRetentionMs) {
          windows.delete(bucketKey);
        }
      }

      const entry = windows.get(input.bucketKey);
      const windowExpired =
        entry === undefined || input.nowMs - entry.windowStartMs >= input.windowMs;
      const windowStartMs = windowExpired ? input.nowMs : entry.windowStartMs;
      const nextRequestCount = windowExpired ? 1 : entry.requestCount + 1;
      const resetAtMs = windowStartMs + input.windowMs;

      if (!windowExpired && entry.requestCount >= input.maxRequests) {
        return {
          allowed: false,
          remaining: 0,
          resetAtMs,
          retryAfterSeconds: Math.ceil((resetAtMs - input.nowMs) / 1000),
        };
      }

      windows.set(input.bucketKey, {
        requestCount: nextRequestCount,
        updatedAtMs: input.nowMs,
        windowStartMs,
      });

      return {
        allowed: true,
        remaining: Math.max(input.maxRequests - nextRequestCount, 0),
        resetAtMs,
        retryAfterSeconds: null,
      };
    },
  };
};

const createTestServices = (overrides: Partial<BackendServices> = {}): BackendServices => {
  return {
    agentRunService: createAgentRunServiceStub(),
    authService: createAuthServiceStub(),
    chatRunService: createChatRunServiceStub(),
    conversationService: createConversationServiceStub(),
    credentialService: createCredentialServiceStub(),
    fileProxySupport: {
      loadApiKey: async () => 'sk-user-key',
    },
    rateLimitService: createRateLimitServiceStub(),
    runService: createRunServiceStub(),
    syncService: createSyncServiceStub(),
    ...overrides,
  };
};

const testExecutionContext = {
  waitUntil: (_promise: Promise<unknown>): void => {},
  passThroughOnException: (): void => {},
} as ExecutionContext;

describe('backend worker scaffold', () => {
  it('allows only parsed origins from the configured allowlist', async () => {
    const app = createApp(createTestServices());

    const allowedResponse = await app.fetch(
      new Request('https://example.com/healthz', {
        headers: {
          Origin: 'https://staging.glassgpt.com',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(allowedResponse.status).toBe(200);
    expect(allowedResponse.headers.get('Access-Control-Allow-Origin')).toBe(
      'https://staging.glassgpt.com',
    );

    const rejectedResponse = await app.fetch(
      new Request('https://example.com/healthz', {
        headers: {
          Origin: 'https://evil-glassgpt.com',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(rejectedResponse.status).toBe(200);
    expect(rejectedResponse.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });

  it('accepts preflight requests for the PATCH configuration route', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/conversations/conv_chat_01/configuration', {
        method: 'OPTIONS',
        headers: {
          'Access-Control-Request-Headers': 'Authorization,Content-Type',
          'Access-Control-Request-Method': 'PATCH',
          Origin: 'https://glassgpt.com',
        },
      }),
      testEnv,
      testExecutionContext,
    );

    expect(response.status).toBe(204);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe('https://glassgpt.com');
    expect(response.headers.get('Access-Control-Allow-Methods')).toContain('PATCH');
  });

  it('rate limits anonymous traffic on authenticated-free routes', async () => {
    const app = createApp(createTestServices());
    const env = createTestEnv();

    let response: Response | null = null;
    for (let index = 0; index <= ANONYMOUS_MAX_REQUESTS_PER_WINDOW; index += 1) {
      response = await app.fetch(
        new Request('https://example.com/v1/auth/refresh', {
          method: 'POST',
          headers: {
            'CF-Connecting-IP': '203.0.113.10',
            'content-type': 'application/json',
          },
          body: JSON.stringify({ refreshToken: 'refresh-token' }),
        }),
        env,
        testExecutionContext,
      );
    }

    expect(response).not.toBeNull();
    expect(response?.status).toBe(429);
    await expect(response?.json()).resolves.toEqual({
      error: 'rate_limited',
    });
  });

  it('rate limits authenticated traffic by resolved user identity', async () => {
    const app = createApp(createTestServices());
    const env = createTestEnv();

    let response: Response | null = null;
    for (let index = 0; index <= AUTHENTICATED_MAX_REQUESTS_PER_WINDOW; index += 1) {
      response = await app.fetch(
        new Request('https://example.com/v1/conversations', {
          headers: {
            Authorization: 'Bearer access-token',
            'CF-Connecting-IP': '203.0.113.11',
          },
        }),
        env,
        testExecutionContext,
      );
    }

    expect(response).not.toBeNull();
    expect(response?.status).toBe(429);
    await expect(response?.json()).resolves.toEqual({
      error: 'rate_limited',
    });
  });

  it('serves the health route', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/healthz', {
        headers: {
          'X-GlassGPT-App-Version': '5.3.0',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      appEnv: 'beta',
      backendVersion: '5.3.2',
      minimumSupportedAppVersion: '5.3.0',
      appCompatibility: 'compatible',
      ok: true,
    });
  });

  it('marks the health route unhealthy when required auth runtime secrets are missing', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/healthz', {
        headers: {
          'X-GlassGPT-App-Version': '5.3.0',
        },
      }),
      createTestEnv({
        SESSION_SIGNING_KEY: '',
      }),
      testExecutionContext,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      appEnv: 'beta',
      backendVersion: '5.3.2',
      minimumSupportedAppVersion: '5.3.0',
      appCompatibility: 'compatible',
      errorSummary: 'auth_runtime_configuration_missing',
      ok: false,
    });
  });

  it('marks unsigned connection checks as update_required when app version metadata is missing', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/connection/check'),
      testEnv,
      testExecutionContext,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      appCompatibility: 'update_required',
      backend: 'healthy',
      auth: 'missing',
      openaiCredential: 'missing',
      sse: 'healthy',
    });
  });

  it('marks connection checks compatible when the supported app version header is provided', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/connection/check', {
        headers: {
          'X-GlassGPT-App-Version': '5.3.0',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      appCompatibility: 'compatible',
      backendVersion: '5.3.2',
      minimumSupportedAppVersion: '5.3.0',
    });
  });

  it('surfaces auth runtime misconfiguration in unsigned connection checks', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/connection/check', {
        headers: {
          'X-GlassGPT-App-Version': '5.3.0',
        },
      }),
      createTestEnv({
        APPLE_AUDIENCE: '',
      }),
      testExecutionContext,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      auth: 'unavailable',
      errorSummary: 'auth_runtime_configuration_missing',
      backendVersion: '5.3.2',
      minimumSupportedAppVersion: '5.3.0',
    });
  });

  it('fails closed for apple auth when auth runtime secrets are missing', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/auth/apple', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          identityToken: 'identity-token',
          authorizationCode: 'auth-code',
          deviceId: 'device-01',
        }),
      }),
      createTestEnv({
        SESSION_SIGNING_KEY: '',
      }),
      testExecutionContext,
    );

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: 'service_unavailable',
    });
  });

  it('fails closed for credential writes when auth runtime secrets are missing', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/credentials/openai', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer access-token',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          apiKey: 'sk-test-key',
        }),
      }),
      createTestEnv({
        REFRESH_TOKEN_SIGNING_KEY: '',
      }),
      testExecutionContext,
    );

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: 'service_unavailable',
    });
  });

  it('returns service_unavailable for Apple auth when required runtime secrets are missing', async () => {
    const response = await createApp(createTestServices()).fetch(
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
      createTestEnv({
        SESSION_SIGNING_KEY: '',
      }),
      testExecutionContext,
    );

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: 'service_unavailable',
    });
  });

  it('fails closed for me refresh and logout when auth runtime secrets are missing', async () => {
    const app = createApp(createTestServices());
    const env = createTestEnv({
      SESSION_SIGNING_KEY: '',
    });

    const meResponse = await app.fetch(
      new Request('https://example.com/v1/me', {
        headers: {
          Authorization: 'Bearer access-token',
        },
      }),
      env,
      testExecutionContext,
    );
    expect(meResponse.status).toBe(503);
    await expect(meResponse.json()).resolves.toEqual({
      error: 'service_unavailable',
    });

    const refreshResponse = await app.fetch(
      new Request('https://example.com/v1/auth/refresh', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          refreshToken: 'refresh-token',
        }),
      }),
      env,
      testExecutionContext,
    );
    expect(refreshResponse.status).toBe(503);
    await expect(refreshResponse.json()).resolves.toEqual({
      error: 'service_unavailable',
    });

    const logoutResponse = await app.fetch(
      new Request('https://example.com/v1/auth/logout', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer access-token',
        },
      }),
      env,
      testExecutionContext,
    );
    expect(logoutResponse.status).toBe(503);
    await expect(logoutResponse.json()).resolves.toEqual({
      error: 'service_unavailable',
    });
  });

  it('supports credential deletion and rejects unauthenticated credential mutations', async () => {
    const app = createApp(createTestServices());

    const unauthenticatedWriteResponse = await app.fetch(
      new Request('https://example.com/v1/credentials/openai', {
        method: 'PUT',
        headers: {
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          apiKey: 'sk-example',
        }),
      }),
      testEnv,
      testExecutionContext,
    );
    expect(unauthenticatedWriteResponse.status).toBe(401);
    await expect(unauthenticatedWriteResponse.json()).resolves.toEqual({
      error: 'unauthorized',
    });

    const unauthenticatedDeleteResponse = await app.fetch(
      new Request('https://example.com/v1/credentials/openai', {
        method: 'DELETE',
      }),
      testEnv,
      testExecutionContext,
    );
    expect(unauthenticatedDeleteResponse.status).toBe(401);
    await expect(unauthenticatedDeleteResponse.json()).resolves.toEqual({
      error: 'unauthorized',
    });

    const authenticatedDeleteResponse = await app.fetch(
      new Request('https://example.com/v1/credentials/openai', {
        method: 'DELETE',
        headers: {
          Authorization: 'Bearer access-token',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(authenticatedDeleteResponse.status).toBe(204);
  });

  it('surfaces signed connection-check auth misconfiguration and unauthorized sessions', async () => {
    const runtimeMisconfigurationResponse = await createApp(createTestServices()).fetch(
      new Request('https://example.com/v1/connection/check', {
        headers: {
          Authorization: 'Bearer access-token',
          'X-GlassGPT-App-Version': '5.3.2',
        },
      }),
      createTestEnv({
        APPLE_BUNDLE_ID: '',
      }),
      testExecutionContext,
    );
    expect(runtimeMisconfigurationResponse.status).toBe(200);
    await expect(runtimeMisconfigurationResponse.json()).resolves.toMatchObject({
      appCompatibility: 'compatible',
      auth: 'unavailable',
      errorSummary: 'auth_runtime_configuration_missing',
      openaiCredential: 'missing',
    });

    const unauthorizedApp = createApp(
      createTestServices({
        authService: {
          ...createAuthServiceStub(),
          resolveSession: async () => {
            throw new ApplicationError('unauthorized', 'invalid_access_token');
          },
        },
      }),
    );
    const unauthorizedResponse = await unauthorizedApp.fetch(
      new Request('https://example.com/v1/connection/check', {
        headers: {
          Authorization: 'Bearer access-token',
          'X-GlassGPT-App-Version': '5.3.2',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(unauthorizedResponse.status).toBe(200);
    await expect(unauthorizedResponse.json()).resolves.toMatchObject({
      appCompatibility: 'compatible',
      auth: 'unauthorized',
      errorSummary: 'authentication_failed',
      openaiCredential: 'missing',
    });
  });

  it('maps forbidden conflict and server_error application failures to the expected HTTP statuses', async () => {
    const forbiddenApp = createApp(
      createTestServices({
        authService: {
          ...createAuthServiceStub(),
          fetchCurrentUser: async () => {
            throw new ApplicationError('forbidden', 'user_blocked');
          },
        },
      }),
    );
    const forbiddenResponse = await forbiddenApp.fetch(
      new Request('https://example.com/v1/me', {
        headers: {
          Authorization: 'Bearer access-token',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(forbiddenResponse.status).toBe(403);
    await expect(forbiddenResponse.json()).resolves.toEqual({
      error: 'forbidden',
    });

    const conflictApp = createApp(
      createTestServices({
        authService: {
          ...createAuthServiceStub(),
          refreshSession: async () => {
            throw new ApplicationError('conflict', 'session_conflict');
          },
        },
      }),
    );
    const conflictResponse = await conflictApp.fetch(
      new Request('https://example.com/v1/auth/refresh', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          refreshToken: 'refresh-token',
        }),
      }),
      testEnv,
      testExecutionContext,
    );
    expect(conflictResponse.status).toBe(409);
    await expect(conflictResponse.json()).resolves.toEqual({
      error: 'conflict',
    });

    const serverErrorApp = createApp(
      createTestServices({
        authService: {
          ...createAuthServiceStub(),
          logout: async () => {
            throw new ApplicationError('server_error', 'unexpected_state');
          },
        },
      }),
    );
    const serverErrorResponse = await serverErrorApp.fetch(
      new Request('https://example.com/v1/auth/logout', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer access-token',
        },
      }),
      testEnv,
      testExecutionContext,
    );
    expect(serverErrorResponse.status).toBe(500);
    await expect(serverErrorResponse.json()).resolves.toEqual({
      error: 'server_error',
    });
  });

  it('maps unexpected failures to internal_server_error and logs the request failure', async () => {
    const logErrorSpy = vi.spyOn(logger, 'logError').mockImplementation(() => {});
    const app = createApp(
      createTestServices({
        authService: {
          ...createAuthServiceStub(),
          refreshSession: async () => {
            throw new Error('refresh_pipeline_failed');
          },
        },
      }),
    );

    const response = await app.fetch(
      new Request('https://example.com/v1/auth/refresh', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          refreshToken: 'refresh-token',
        }),
      }),
      testEnv,
      testExecutionContext,
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: 'internal_server_error',
    });
    expect(logErrorSpy).toHaveBeenCalledWith(
      'backend_request_failed',
      expect.objectContaining({
        errorMessage: 'refresh_pipeline_failed',
        errorName: 'Error',
      }),
    );

    logErrorSpy.mockRestore();
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
    await expect(listResponse.json()).resolves.toEqual({
      hasMore: false,
      items: [chatConversationFixture, agentConversationFixture],
    });

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

  it('accepts oversized image-bearing message bodies on the conversation message route', async () => {
    const app = createApp(createTestServices());
    const response = await app.fetch(
      new Request(`https://example.com/v1/conversations/${chatConversationFixture.id}/messages`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer access-token',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          content: 'Describe this image',
          imageBase64: 'a'.repeat(1_400_000),
        }),
      }),
      testEnv,
      testExecutionContext,
    );

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toMatchObject({
      conversationId: chatConversationFixture.id,
      kind: 'chat',
      status: 'queued',
    });
  });

  it('accepts oversized multipart uploads on the file proxy route', async () => {
    const app = createApp(createTestServices());
    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ bytes: 1_200_000, filename: 'large.pdf', id: 'file_large_01' }), {
        headers: { 'Content-Type': 'application/json' },
        status: 200,
      }),
    ) as typeof fetch;

    try {
      const formData = new FormData();
      formData.append(
        'file',
        new File([new Uint8Array(1_200_000)], 'large.pdf', {
          type: 'application/pdf',
        }),
      );
      formData.append('purpose', 'user_data');

      const response = await app.fetch(
        new Request('https://example.com/v1/files/upload', {
          method: 'POST',
          headers: {
            Authorization: 'Bearer access-token',
          },
          body: formData,
        }),
        testEnv,
        testExecutionContext,
      );

      expect(response.status).toBe(201);
      await expect(response.json()).resolves.toEqual({
        bytes: 1_200_000,
        fileId: 'file_large_01',
        filename: 'large.pdf',
      });
    } finally {
      globalThis.fetch = originalFetch;
    }
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

  it('requires authentication for run streaming', async () => {
    const response = await createApp(createTestServices()).fetch(
      new Request(`https://example.com/v1/runs/${chatRunFixture.id}/stream`),
      testEnv,
      testExecutionContext,
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({
      error: 'unauthorized',
    });
  });

  it('streams immediate done for terminal runs without touching durable objects', async () => {
    const app = createApp(
      createTestServices({
        runService: createRunServiceStub({
          getRun: async () => ({
            ...agentRunFixture,
            id: 'run_agent_terminal_01',
            stage: 'final_synthesis',
            status: 'completed',
            visibleSummary: 'Completed agent run',
          }),
        }),
      }),
    );

    const env = createTestEnv({
      CONVERSATION_EVENT_HUB: createConversationEventHubStub(async () => {
        throw new Error('durable_object_should_not_be_used_for_terminal_run');
      }),
    });

    const response = await app.fetch(
      new Request('https://example.com/v1/runs/run_agent_terminal_01/stream', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      env,
      testExecutionContext,
    );

    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toContain('event: done');
  });

  it('relays initial stage and process payloads and filters unrelated stream frames', async () => {
    const app = createApp(
      createTestServices({
        runService: createRunServiceStub({
          getRun: async () => ({
            ...agentRunFixture,
            id: 'run_agent_stream_01',
            stage: 'worker_wave',
            status: 'running',
            visibleSummary: 'Workers running live',
          }),
        }),
      }),
    );

    const env = createTestEnv({
      CONVERSATION_EVENT_HUB: createConversationEventHubStub(async () =>
        createSSEStreamResponse([
          ': connected\n\n',
          'event: delta\ndata: {"runId":"run_agent_stream_01","textDelta":"hello"}\n\n',
          'event: done\ndata: {"runId":"run_agent_stream_01","status":"completed"}\n\n',
        ]),
      ),
    });

    const response = await app.fetch(
      new Request('https://example.com/v1/runs/run_agent_stream_01/stream', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      env,
      testExecutionContext,
    );

    expect(response.status).toBe(200);
    const body = await response.text();
    expect(body).toContain('event: status');
    expect(body).toContain('event: stage');
    expect(body).toContain('event: process_update');
    expect(body).toContain('event: task_update');
    expect(body).toContain('Workers running live');
    expect(body).toContain('"textDelta":"hello"');
  });

  it('replays the current assistant snapshot with stable ids and forwards last-event-id to realtime relay', async () => {
    let forwardedLastEventID: string | null = null;
    const app = createApp(
      createTestServices({
        conversationService: {
          ...createConversationServiceStub(),
          getConversationDetail: async () => ({
            conversation: {
              ...chatConversationFixture,
              lastSyncCursor: 'cur_00000000000000000007',
            },
            messages: [
              {
                annotations: [
                  {
                    endIndex: 9,
                    startIndex: 0,
                    title: 'Plan',
                    url: 'https://example.com/plan',
                  },
                ],
                completedAt: undefined,
                content: 'Recovered output',
                conversationId: chatConversationFixture.id,
                createdAt: '2026-03-27T12:00:01.000Z',
                filePathAnnotations: [
                  {
                    containerId: 'sandbox_1',
                    endIndex: 15,
                    fileId: 'file_1',
                    filename: 'report.md',
                    sandboxPath: '/tmp/report.md',
                    startIndex: 0,
                  },
                ],
                id: 'msg_resume_01',
                role: 'assistant',
                runId: 'run_chat_stream_01',
                serverCursor: 'cur_00000000000000000007',
                thinking: 'Recovered thinking',
                toolCalls: [
                  {
                    code: null,
                    id: 'tool_1',
                    queries: ['GlassGPT 5.3.0'],
                    results: ['ok'],
                    status: 'completed',
                    type: 'web_search',
                  },
                ],
              },
            ],
            runs: [
              {
                ...chatRunFixture,
                id: 'run_chat_stream_01',
                lastEventCursor: 'cur_00000000000000000007',
                status: 'running',
                visibleSummary: 'Recovered summary',
              },
            ],
          }),
        },
        runService: createRunServiceStub({
          getRun: async () => ({
            ...chatRunFixture,
            id: 'run_chat_stream_01',
            lastEventCursor: 'cur_00000000000000000007',
            status: 'running',
            visibleSummary: 'Recovered summary',
          }),
        }),
      }),
    );

    const env = createTestEnv({
      CONVERSATION_EVENT_HUB: createConversationEventHubStub(async (input, init) => {
        const request = new Request(input, init);
        forwardedLastEventID = request.headers.get('Last-Event-ID');
        return createSSEStreamResponse([
          'id: cur_00000000000000000007\nevent: done\ndata: {"runId":"run_chat_stream_01","status":"completed"}\n\n',
        ]);
      }),
    });

    const response = await app.fetch(
      new Request('https://example.com/v1/runs/run_chat_stream_01/stream', {
        headers: {
          Authorization: 'Bearer access-token',
          'Last-Event-ID': 'cur_00000000000000000006',
        },
      }),
      env,
      testExecutionContext,
    );

    expect(response.status).toBe(200);
    expect(forwardedLastEventID).toBe('cur_00000000000000000006');
    const body = await response.text();
    expect(body).toContain('id: cur_00000000000000000007');
    expect(body).toContain('event: thinking_delta');
    expect(body).toContain('event: tool_call_update');
    expect(body).toContain('event: citations_update');
    expect(body).toContain('event: file_path_annotations_update');
    expect(body).toContain('event: delta');
    expect(body).toContain('Recovered output');
  });

  it('logs malformed initial process snapshots without aborting the stream', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
    const app = createApp(
      createTestServices({
        runService: createRunServiceStub({
          getRun: async () => ({
            ...agentRunFixture,
            id: 'run_agent_stream_invalid_snapshot',
            processSnapshotJSON: '{"tasks": ',
            stage: 'worker_wave',
            status: 'running',
            visibleSummary: 'Workers running live',
          }),
        }),
      }),
    );

    const env = createTestEnv({
      CONVERSATION_EVENT_HUB: createConversationEventHubStub(async () =>
        createSSEStreamResponse([
          'event: done\ndata: {"runId":"run_agent_stream_invalid_snapshot","status":"completed"}\n\n',
        ]),
      ),
    });

    const response = await app.fetch(
      new Request('https://example.com/v1/runs/run_agent_stream_invalid_snapshot/stream', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      env,
      testExecutionContext,
    );

    expect(response.status).toBe(200);
    const body = await response.text();
    expect(body).toContain('event: status');
    expect(body).toContain('event: stage');
    expect(body).not.toContain('event: process_update');
    expect(consoleError).toHaveBeenCalledWith(
      expect.stringContaining('"message":"run_stream_snapshot_decode_failed"'),
    );
    consoleError.mockRestore();
  });

  it('fails closed when realtime relay setup is unavailable', async () => {
    const app = createApp(
      createTestServices({
        runService: createRunServiceStub({
          getRun: async () => ({
            ...chatRunFixture,
            id: 'run_chat_stream_01',
            status: 'running',
            visibleSummary: 'Streaming',
          }),
        }),
      }),
    );

    const env = createTestEnv({
      CONVERSATION_EVENT_HUB: createConversationEventHubStub(
        async () =>
          new Response(JSON.stringify({ error: 'offline' }), {
            headers: { 'Content-Type': 'application/json' },
            status: 503,
          }),
      ),
    });

    const response = await app.fetch(
      new Request('https://example.com/v1/runs/run_chat_stream_01/stream', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      env,
      testExecutionContext,
    );

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: 'realtime_stream_unavailable',
    });
  });

  it('logs relay failures and emits structured stream errors for the client', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
    const app = createApp(
      createTestServices({
        runService: createRunServiceStub({
          getRun: async () => ({
            ...chatRunFixture,
            id: 'run_chat_stream_error',
            status: 'running',
            visibleSummary: 'Streaming',
          }),
        }),
      }),
    );

    const env = createTestEnv({
      CONVERSATION_EVENT_HUB: createConversationEventHubStub(async () =>
        createFailingSSEStreamResponse(
          ['event: delta\ndata: {"runId":"run_chat_stream_error","textDelta":"Alpha"}\n\n'],
          'durable_object_relay_read_failed',
        ),
      ),
    });

    const response = await app.fetch(
      new Request('https://example.com/v1/runs/run_chat_stream_error/stream', {
        headers: { Authorization: 'Bearer access-token' },
      }),
      env,
      testExecutionContext,
    );

    expect(response.status).toBe(200);
    const body = await response.text();
    expect(body).toContain('event: status');
    expect(body).toContain('event: error');
    expect(body).toContain('"code":"realtime_stream_unavailable"');
    expect(body).toContain('"message":"Realtime stream became unavailable. Please retry."');
    expect(body).toContain('"phase":"relay"');
    expect(consoleError).toHaveBeenCalledWith(
      expect.stringContaining('"message":"run_stream_relay_failed"'),
    );
    consoleError.mockRestore();
  });
});
