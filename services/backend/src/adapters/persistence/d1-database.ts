import type { BackendEnv } from './env.js';

const DATABASE_BINDING = 'GLASSGPT_DB' as const;

export interface BackendDatabase {
  readonly bindingName: typeof DATABASE_BINDING;
  readonly raw: BackendEnv['GLASSGPT_DB'];
}

export const createBackendDatabase = (env: BackendEnv): BackendDatabase => {
  return {
    bindingName: DATABASE_BINDING,
    raw: env.GLASSGPT_DB,
  };
};
