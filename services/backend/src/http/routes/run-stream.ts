import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

const SSE_HEARTBEAT_INTERVAL_MS = 15_000;

const sseFrame = (event: string, data: unknown): string => {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
};

export const installRunStreamRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/runs/:runId/stream', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const env = asBackendRuntimeContext(context.env);
    const runId = context.req.param('runId');

    // Resolve the run and its conversation to connect to the right Durable Object
    const initialRun = await services.runService.getRun(env, session.userId, runId);
    const conversationId = initialRun.conversationID;

    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      async start(controller) {
        const enqueue = (chunk: string): void => {
          try {
            controller.enqueue(encoder.encode(chunk));
          } catch {
            // Controller may be closed
          }
        };

        let heartbeatTimer: ReturnType<typeof setInterval> | null = null;
        const cleanup = (): void => {
          if (heartbeatTimer !== null) {
            clearInterval(heartbeatTimer);
            heartbeatTimer = null;
          }
        };

        try {
          heartbeatTimer = setInterval(() => {
            enqueue(': ping\n\n');
          }, SSE_HEARTBEAT_INTERVAL_MS);

          // Emit initial status
          enqueue(sseFrame('status', { status: initialRun.status, visibleSummary: initialRun.visibleSummary }));

          // If already terminal, send done immediately
          if (
            initialRun.status === 'completed' ||
            initialRun.status === 'failed' ||
            initialRun.status === 'cancelled'
          ) {
            enqueue(sseFrame('done', { status: initialRun.status }));
            cleanup();
            controller.close();
            return;
          }

          // Connect to the Durable Object's SSE stream for real-time deltas
          const durableObjectId = context.env.CONVERSATION_EVENT_HUB.idFromName(conversationId);
          const stub = context.env.CONVERSATION_EVENT_HUB.get(durableObjectId);
          const doResponse = await stub.fetch('https://conversation-event-hub/stream');

          if (!doResponse.body) {
            enqueue(sseFrame('error', { message: 'realtime_stream_unavailable' }));
            cleanup();
            controller.close();
            return;
          }

          // Relay events from the Durable Object to the client, filtering by runId
          const reader = doResponse.body.getReader();
          const decoder = new TextDecoder();
          let buffer = '';

          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });

            // Forward complete SSE frames (ending with \n\n)
            while (buffer.includes('\n\n')) {
              const frameEnd = buffer.indexOf('\n\n');
              const frame = buffer.slice(0, frameEnd + 2);
              buffer = buffer.slice(frameEnd + 2);

              // Parse the frame to check runId and detect done events
              const dataMatch = frame.match(/^data: (.+)$/m);
              if (dataMatch) {
                try {
                  const parsed = JSON.parse(dataMatch[1]) as { runId?: string; status?: string };
                  // Only forward events for this specific run
                  if (parsed.runId && parsed.runId !== runId) {
                    continue;
                  }
                } catch {
                  // Forward unparseable frames as-is
                }
              }

              // Skip comment lines (heartbeats from DO)
              if (frame.startsWith(':')) {
                continue;
              }

              enqueue(frame);

              // Check for done event
              if (frame.includes('event: done')) {
                cleanup();
                reader.releaseLock();
                controller.close();
                return;
              }
            }
          }

          // DO stream ended without done — check terminal state and close
          const finalRun = await services.runService.getRun(env, session.userId, runId);
          enqueue(sseFrame('done', { status: finalRun.status }));
        } finally {
          cleanup();
        }

        controller.close();
      },
    });

    return new Response(stream, {
      headers: {
        'Cache-Control': 'no-cache',
        Connection: 'keep-alive',
        'Content-Type': 'text/event-stream',
      },
    });
  });
};
