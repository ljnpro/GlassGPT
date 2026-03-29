import type { Hono } from 'hono';
import type { AuthenticatedBackendSession } from './services.js';

export interface BackendContextVariables {
  readonly session: AuthenticatedBackendSession | undefined;
}

export interface BackendAppContext {
  readonly Bindings: Env;
  readonly Variables: BackendContextVariables;
}

export type BackendApp = Hono<BackendAppContext>;
