import { createBackendServices } from './adapters/create-backend-services.js';
import { ConversationEventHub } from './adapters/realtime/conversation-event-hub.js';
import { createApp } from './http/app.js';
import { AgentRunWorkflow } from './workflows/agent-run-workflow.js';
import { ChatRunWorkflow } from './workflows/chat-run-workflow.js';

const app = createApp(createBackendServices());

export { AgentRunWorkflow, ChatRunWorkflow, ConversationEventHub };
export default app;
