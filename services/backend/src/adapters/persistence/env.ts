import type { BackendRuntimeContext } from '../../application/runtime-context.js';

export type BackendEnv = BackendRuntimeContext;

export const asBackendEnv = (env: Env): BackendEnv => {
  return env as unknown as BackendEnv;
};
