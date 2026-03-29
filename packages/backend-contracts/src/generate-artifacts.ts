import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

import { z } from 'zod';

import {
  appleAuthRequestFixture,
  artifactDownloadFixture,
  artifactFixture,
  connectionCheckFixture,
  conversationDetailFixture,
  conversationFixture,
  conversationListFixture,
  createConversationRequestFixture,
  createMessageRequestFixture,
  credentialStatusFixture,
  messageFixture,
  openAiCredentialRequestFixture,
  refreshSessionRequestFixture,
  runEventFixture,
  runSummaryFixture,
  sessionFixture,
  startAgentRunRequestFixture,
  syncEnvelopeFixture,
  userFixture,
} from './fixtures.js';
import {
  appleAuthRequestSchema,
  artifactDownloadSchema,
  artifactSchema,
  connectionCheckSchema,
  conversationDetailSchema,
  conversationListSchema,
  conversationSchema,
  createConversationRequestSchema,
  createMessageRequestSchema,
  credentialStatusSchema,
  errorResponseSchema,
  messageSchema,
  openAiCredentialRequestSchema,
  refreshSessionRequestSchema,
  runEventSchema,
  runSummarySchema,
  sessionSchema,
  startAgentRunRequestSchema,
  syncEnvelopeSchema,
  updateConversationConfigurationRequestSchema,
  userSchema,
} from './index.js';

const generatedDirectory = resolve(process.cwd(), 'generated');
const openApiPath = resolve(generatedDirectory, 'openapi.json');
const fixturesPath = resolve(generatedDirectory, 'fixtures.json');

const schemaMap = {
  AppleAuthRequestDTO: appleAuthRequestSchema,
  ArtifactDTO: artifactSchema,
  ArtifactDownloadDTO: artifactDownloadSchema,
  ConnectionCheckDTO: connectionCheckSchema,
  ConversationDTO: conversationSchema,
  ConversationDetailDTO: conversationDetailSchema,
  ConversationListDTO: conversationListSchema,
  CreateConversationRequestDTO: createConversationRequestSchema,
  CreateMessageRequestDTO: createMessageRequestSchema,
  UpdateConversationConfigurationRequestDTO: updateConversationConfigurationRequestSchema,
  CredentialStatusDTO: credentialStatusSchema,
  ErrorDTO: errorResponseSchema,
  MessageDTO: messageSchema,
  OpenAiCredentialRequestDTO: openAiCredentialRequestSchema,
  RefreshSessionRequestDTO: refreshSessionRequestSchema,
  RunEventDTO: runEventSchema,
  RunSummaryDTO: runSummarySchema,
  SessionDTO: sessionSchema,
  StartAgentRunRequestDTO: startAgentRunRequestSchema,
  SyncEnvelopeDTO: syncEnvelopeSchema,
  UserDTO: userSchema,
} as const;

const fixtures = {
  AppleAuthRequestDTO: appleAuthRequestFixture,
  ArtifactDTO: artifactFixture,
  ArtifactDownloadDTO: artifactDownloadFixture,
  ConnectionCheckDTO: connectionCheckFixture,
  ConversationDTO: conversationFixture,
  ConversationDetailDTO: conversationDetailFixture,
  ConversationListDTO: conversationListFixture,
  CreateConversationRequestDTO: createConversationRequestFixture,
  CreateMessageRequestDTO: createMessageRequestFixture,
  CredentialStatusDTO: credentialStatusFixture,
  MessageDTO: messageFixture,
  OpenAiCredentialRequestDTO: openAiCredentialRequestFixture,
  RefreshSessionRequestDTO: refreshSessionRequestFixture,
  RunEventDTO: runEventFixture,
  RunSummaryDTO: runSummaryFixture,
  SessionDTO: sessionFixture,
  StartAgentRunRequestDTO: startAgentRunRequestFixture,
  SyncEnvelopeDTO: syncEnvelopeFixture,
  UserDTO: userFixture,
} as const;

const openApiDocument = {
  openapi: '3.1.0',
  info: {
    title: 'GlassGPT Backend API',
    version: '5.3.0',
  },
  paths: {
    '/v1/auth/apple': {
      post: {
        operationId: 'authenticateWithApple',
        responses: {
          '501': {
            description: 'Authentication wiring is scaffolded but not implemented.',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/ErrorDTO' },
              },
            },
          },
        },
      },
    },
    '/v1/connection/check': {
      get: {
        operationId: 'checkConnection',
        responses: {
          '200': {
            description: 'Returns backend, auth, and credential health.',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/ConnectionCheckDTO' },
              },
            },
          },
        },
      },
    },
    '/v1/conversations/{conversationId}/messages': {
      post: {
        operationId: 'startChatRun',
        responses: {
          '202': {
            description: 'Queues a server-owned chat run.',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/RunSummaryDTO' },
              },
            },
          },
        },
      },
    },
    '/v1/conversations/{conversationId}/agent-runs': {
      post: {
        operationId: 'startAgentRun',
        responses: {
          '202': {
            description: 'Queues a server-owned agent workflow.',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/RunSummaryDTO' },
              },
            },
          },
        },
      },
    },
    '/v1/conversations/{conversationId}/configuration': {
      patch: {
        operationId: 'updateConversationConfiguration',
        responses: {
          '200': {
            description: 'Updates the authoritative backend configuration for a conversation.',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/ConversationDTO' },
              },
            },
          },
        },
      },
    },
    '/v1/sync/events': {
      get: {
        operationId: 'syncEvents',
        responses: {
          '200': {
            description: 'Returns append-only run events from a cursor.',
            content: {
              'application/json': {
                schema: { $ref: '#/components/schemas/SyncEnvelopeDTO' },
              },
            },
          },
        },
      },
    },
  },
  components: {
    schemas: Object.fromEntries(
      Object.entries(schemaMap).map(([name, schema]) => [name, z.toJSONSchema(schema)]),
    ),
  },
};

await mkdir(dirname(openApiPath), { recursive: true });
await writeFile(openApiPath, `${JSON.stringify(openApiDocument, null, 2)}\n`, 'utf8');
await writeFile(fixturesPath, `${JSON.stringify(fixtures, null, 2)}\n`, 'utf8');
