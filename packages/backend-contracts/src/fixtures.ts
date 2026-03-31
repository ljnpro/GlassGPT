import {
  conversationSchema,
  createConversationRequestSchema,
  createMessageRequestSchema,
  messageSchema,
} from './conversation.js';
import {
  artifactDownloadSchema,
  conversationDetailSchema,
  conversationListSchema,
  syncEnvelopeSchema,
} from './envelopes.js';
import {
  appleAuthRequestSchema,
  credentialStatusSchema,
  openAiCredentialRequestSchema,
  refreshSessionRequestSchema,
  sessionSchema,
  userSchema,
} from './identity.js';
import {
  artifactSchema,
  connectionCheckSchema,
  runEventSchema,
  runSummarySchema,
  startAgentRunRequestSchema,
} from './run.js';

const timestamp = '2026-03-27T00:00:00.000Z';

export const userFixture = userSchema.parse({
  id: 'usr_01',
  appleSubject: 'apple-subject-01',
  displayName: 'Glass User',
  email: 'glass@example.com',
  createdAt: timestamp,
});

export const sessionFixture = sessionSchema.parse({
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  expiresAt: timestamp,
  deviceId: 'device_01',
  user: userFixture,
});

export const credentialStatusFixture = credentialStatusSchema.parse({
  provider: 'openai',
  state: 'valid',
  checkedAt: timestamp,
});

export const connectionCheckFixture = connectionCheckSchema.parse({
  backend: 'healthy',
  auth: 'missing',
  openaiCredential: 'missing',
  sse: 'healthy',
  checkedAt: timestamp,
  latencyMilliseconds: 18,
  backendVersion: '5.6.0',
  minimumSupportedAppVersion: '5.4.0',
  appCompatibility: 'compatible',
});

export const conversationFixture = conversationSchema.parse({
  id: 'conv_01',
  title: 'GlassGPT 5.6.0',
  mode: 'chat',
  createdAt: timestamp,
  updatedAt: timestamp,
  lastRunId: 'run_01',
  lastSyncCursor: 'cur_00000000000000000001',
  model: 'gpt-5.4-pro',
  reasoningEffort: 'xhigh',
  serviceTier: 'flex',
});

export const messageFixture = messageSchema.parse({
  id: 'msg_01',
  conversationId: 'conv_01',
  role: 'assistant',
  content: 'Hello from the backend scaffold.',
  createdAt: timestamp,
  completedAt: timestamp,
  serverCursor: 'cur_00000000000000000001',
  runId: 'run_01',
});

export const runSummaryFixture = runSummarySchema.parse({
  id: 'run_01',
  conversationId: 'conv_01',
  kind: 'chat',
  status: 'running',
  createdAt: timestamp,
  updatedAt: timestamp,
  lastEventCursor: 'cur_00000000000000000001',
  visibleSummary: 'Streaming assistant output',
});

export const runEventFixture = runEventSchema.parse({
  id: 'evt_01',
  cursor: 'cur_00000000000000000001',
  runId: 'run_01',
  conversationId: 'conv_01',
  kind: 'message_created',
  createdAt: timestamp,
  conversation: conversationFixture,
  message: {
    id: 'msg_02',
    conversationId: 'conv_01',
    role: 'user',
    content: 'Tell me something useful.',
    createdAt: timestamp,
    completedAt: timestamp,
    serverCursor: 'cur_00000000000000000001',
    runId: 'run_01',
  },
  run: {
    ...runSummaryFixture,
    status: 'queued',
    visibleSummary: 'Queued chat run',
  },
});

export const artifactFixture = artifactSchema.parse({
  id: 'art_01',
  conversationId: 'conv_01',
  runId: 'run_01',
  kind: 'document',
  filename: 'artifact.txt',
  contentType: 'text/plain',
  byteCount: 128,
  createdAt: timestamp,
  downloadUrl: 'https://example.com/artifacts/art_01',
});

export const conversationListFixture = conversationListSchema.parse({
  hasMore: false,
  items: [conversationFixture],
});

export const conversationDetailFixture = conversationDetailSchema.parse({
  conversation: conversationFixture,
  messages: [messageFixture],
  runs: [runSummaryFixture],
});

export const syncEnvelopeFixture = syncEnvelopeSchema.parse({
  nextCursor: 'cur_00000000000000000002',
  events: [runEventFixture],
});

export const artifactDownloadFixture = artifactDownloadSchema.parse({
  artifact: artifactFixture,
  url: 'https://example.com/artifacts/art_01/download',
});

export const appleAuthRequestFixture = appleAuthRequestSchema.parse({
  identityToken: 'identity-token',
  authorizationCode: 'auth-code',
  deviceId: 'device_01',
});

export const refreshSessionRequestFixture = refreshSessionRequestSchema.parse({
  refreshToken: 'refresh-token',
});

export const openAiCredentialRequestFixture = openAiCredentialRequestSchema.parse({
  apiKey: 'sk-example',
});

export const createConversationRequestFixture = createConversationRequestSchema.parse({
  title: 'New Conversation',
  mode: 'chat',
  model: 'gpt-5.4-pro',
  reasoningEffort: 'xhigh',
  serviceTier: 'flex',
});

export const createMessageRequestFixture = createMessageRequestSchema.parse({
  content: 'Tell me something useful.',
});

export const startAgentRunRequestFixture = startAgentRunRequestSchema.parse({
  prompt: 'Investigate the current codebase state.',
});
