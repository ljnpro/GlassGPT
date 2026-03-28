import type { BackendEnv } from '../persistence/env.js';

const ARTIFACT_BUCKET_BINDING = 'GLASSGPT_ARTIFACTS' as const;

export interface ArtifactStore {
  readonly bindingName: typeof ARTIFACT_BUCKET_BINDING;
  readonly bucketName: string;
  readonly raw: BackendEnv['GLASSGPT_ARTIFACTS'];
}

export const createArtifactStore = (env: BackendEnv): ArtifactStore => {
  return {
    bindingName: ARTIFACT_BUCKET_BINDING,
    bucketName: env.R2_BUCKET_NAME,
    raw: env.GLASSGPT_ARTIFACTS,
  };
};
