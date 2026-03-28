export const backendBindings = {
  database: 'GLASSGPT_DB',
  artifactBucket: 'GLASSGPT_ARTIFACTS',
  conversationEventHub: 'CONVERSATION_EVENT_HUB',
  chatRunWorkflow: 'CHAT_RUN_WORKFLOW',
  agentRunWorkflow: 'AGENT_RUN_WORKFLOW',
} as const;

export const backendSecrets = [
  'SESSION_SIGNING_KEY',
  'REFRESH_TOKEN_SIGNING_KEY',
  'CREDENTIAL_ENCRYPTION_KEY',
  'CREDENTIAL_ENCRYPTION_KEY_VERSION',
  'APPLE_AUDIENCE',
  'APPLE_BUNDLE_ID',
] as const;

export type BackendBindingName = (typeof backendBindings)[keyof typeof backendBindings];
export type BackendSecretName = (typeof backendSecrets)[number];
