export interface BackendSecretEnv {
  readonly APPLE_AUDIENCE: string;
  readonly APPLE_BUNDLE_ID: string;
  readonly CREDENTIAL_ENCRYPTION_KEY: string;
  readonly CREDENTIAL_ENCRYPTION_KEYS_JSON?: string;
  readonly CREDENTIAL_ENCRYPTION_KEY_VERSION: string;
  readonly REFRESH_TOKEN_SIGNING_KEY: string;
  readonly SESSION_SIGNING_KEY: string;
}

export interface BackendPlatformBindings {
  readonly AGENT_RUN_WORKFLOW: Workflow<unknown>;
  readonly APP_ENV: 'beta';
  readonly CHAT_RUN_WORKFLOW: Workflow<unknown>;
  readonly CONVERSATION_EVENT_HUB: DurableObjectNamespace;
  readonly GLASSGPT_ARTIFACTS: R2Bucket;
  readonly GLASSGPT_DB: D1Database;
  readonly R2_BUCKET_NAME: string;
}

export interface BackendRuntimeContext extends BackendSecretEnv, BackendPlatformBindings {}
