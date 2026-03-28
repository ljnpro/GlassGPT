import type { BackendRuntimeContext } from '../application/runtime-context.js';

export const asBackendRuntimeContext = (env: Env): BackendRuntimeContext => {
  return env as unknown as BackendRuntimeContext;
};
