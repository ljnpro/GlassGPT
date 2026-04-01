import { makeErrorResponse } from '@glassgpt/backend-contracts';

import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

export const installArtifactRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/artifacts/:artifactId/url', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const artifactId = context.req.param('artifactId');
    void asBackendRuntimeContext(context.env);

    const bucket = context.env.GLASSGPT_ARTIFACTS;
    const objectKey = `${session.userId}/${artifactId}`;
    const object = await bucket.head(objectKey);
    if (!object) {
      const requestId = context.get('requestId');
      return context.json(
        makeErrorResponse('artifact_not_found', requestId, { code: 'not_found' }),
        404,
      );
    }

    const requestURL = new URL(context.req.url);
    const downloadURL = new URL(`/v1/artifacts/${artifactId}/download`, requestURL.origin);

    return context.json({
      artifact: {
        id: artifactId,
        contentType: object.httpMetadata?.contentType ?? 'application/octet-stream',
        byteCount: object.size,
        createdAt: object.uploaded.toISOString(),
      },
      url: downloadURL.toString(),
    });
  });
};
