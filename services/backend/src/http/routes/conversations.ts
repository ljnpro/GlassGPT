import {
  createConversationRequestSchema,
  createMessageRequestSchema,
  listConversationsQuerySchema,
  startAgentRunRequestSchema,
  updateConversationConfigurationRequestSchema,
} from '@glassgpt/backend-contracts';

import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installConversationRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/conversations', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const query = listConversationsQuerySchema.parse({
      cursor: context.req.query('cursor') ?? undefined,
      limit: context.req.query('limit') ?? undefined,
    });
    return context.json(
      await services.conversationService.listConversations(
        asBackendRuntimeContext(context.env),
        session.userId,
        query,
      ),
    );
  });

  app.get('/v1/conversations/:conversationId', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    return context.json(
      await services.conversationService.getConversationDetail(
        asBackendRuntimeContext(context.env),
        session.userId,
        context.req.param('conversationId'),
      ),
    );
  });

  app.post('/v1/conversations', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const body = createConversationRequestSchema.parse(await context.req.json());

    return context.json(
      await services.conversationService.createConversation(
        asBackendRuntimeContext(context.env),
        session.userId,
        body,
      ),
      201,
    );
  });

  app.patch('/v1/conversations/:conversationId/configuration', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const body = updateConversationConfigurationRequestSchema.parse(await context.req.json());
    return context.json(
      await services.conversationService.updateConversationConfiguration(
        asBackendRuntimeContext(context.env),
        session.userId,
        context.req.param('conversationId'),
        body,
      ),
    );
  });

  app.post('/v1/conversations/:conversationId/messages', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const body = createMessageRequestSchema.parse(await context.req.json());

    const run = await services.chatRunService.queueChatRun(
      asBackendRuntimeContext(context.env),
      context.env.CHAT_RUN_WORKFLOW,
      {
        content: body.content,
        conversationId: context.req.param('conversationId'),
        fileIds: body.fileIds,
        imageBase64: body.imageBase64,
        userId: session.userId,
      },
    );

    return context.json(run, 202);
  });

  app.post('/v1/conversations/:conversationId/agent-runs', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const body = startAgentRunRequestSchema.parse(await context.req.json());
    const conversationId = context.req.param('conversationId');

    const run = await services.agentRunService.queueAgentRun(
      asBackendRuntimeContext(context.env),
      context.env.AGENT_RUN_WORKFLOW,
      {
        conversationId,
        ...(body.prompt ? { prompt: body.prompt } : {}),
        userId: session.userId,
      },
    );

    return context.json(run, 202);
  });
};
