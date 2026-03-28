import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installArtifactRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/artifacts/:artifactId/url', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const artifactId = context.req.param('artifactId');
    const env = asBackendRuntimeContext(context.env);

    const bucket = context.env.ARTIFACT_BUCKET;
    if (!bucket) {
      return context.json({ error: 'artifact_storage_unavailable' }, 503);
    }

    const objectKey = `${session.userId}/${artifactId}`;
    const object = await bucket.head(objectKey);
    if (!object) {
      return context.json({ error: 'artifact_not_found' }, 404);
    }

    const signedUrl = await bucket.createMultipartUpload(objectKey);

    return context.json({
      artifact: {
        id: artifactId,
        contentType: object.httpMetadata?.contentType ?? 'application/octet-stream',
        byteCount: object.size,
        createdAt: object.uploaded.toISOString(),
      },
      url: `${context.env.ARTIFACT_PUBLIC_URL ?? env.baseURL}/${objectKey}`,
    });
  });
};
