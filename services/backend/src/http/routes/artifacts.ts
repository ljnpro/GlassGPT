import { artifactDownloadSchema } from '@glassgpt/backend-contracts';

import type { BackendApp } from '../types.js';

export const installArtifactRoutes = (app: BackendApp): void => {
  app.get('/v1/artifacts/:artifactId/url', (context) => {
    const artifactId = context.req.param('artifactId');
    const now = new Date().toISOString();

    return context.json(
      artifactDownloadSchema.parse({
        artifact: {
          id: artifactId,
          conversationId: 'conversation-placeholder',
          runId: 'run-placeholder',
          kind: 'document',
          filename: `${artifactId}.txt`,
          contentType: 'text/plain',
          byteCount: 0,
          createdAt: now,
        },
        url: `https://example.com/artifacts/${artifactId}`,
      }),
    );
  });
};
