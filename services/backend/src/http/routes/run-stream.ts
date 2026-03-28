import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

const SSE_HEARTBEAT_INTERVAL_MS = 15_000;
const SSE_POLL_INTERVAL_MS = 500;

const sseFrame = (event: string, data: unknown): string => {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
};

export const installRunStreamRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/runs/:runId/stream', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const env = asBackendRuntimeContext(context.env);
    const runId = context.req.param('runId');
    const lastEventId = context.req.header('Last-Event-ID') ?? null;

    const initialRun = await services.runService.getRun(env, session.userId, runId);

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

        let lastKnownCursor = lastEventId;
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

          // Emit initial run status
          enqueue(sseFrame('status', { status: initialRun.status, visibleSummary: initialRun.visibleSummary }));

          // If the run is already terminal, emit catch-up events and close
          if (
            initialRun.status === 'completed' ||
            initialRun.status === 'failed' ||
            initialRun.status === 'cancelled'
          ) {
            const catchUpEvents = await services.syncService.syncEvents(
              env,
              session.userId,
              lastKnownCursor,
            );
            for (const event of catchUpEvents.events) {
              if (event.runId === runId) {
                enqueue(sseFrame('event', event));
              }
            }
            enqueue(sseFrame('done', { status: initialRun.status }));
            cleanup();
            controller.close();
            return;
          }

          // For in-progress runs, poll for new events and forward them
          let isRunning = true;
          while (isRunning) {
            try {
              const syncResult = await services.syncService.syncEvents(
                env,
                session.userId,
                lastKnownCursor,
              );

              for (const event of syncResult.events) {
                if (event.runId === runId) {
                  const eventType =
                    event.kind === 'assistant_delta'
                      ? 'delta'
                      : event.kind.startsWith('run_')
                        ? 'status'
                        : 'event';
                  enqueue(sseFrame(eventType, event));
                }
              }

              if (syncResult.cursor) {
                lastKnownCursor = syncResult.cursor;
              }

              // Check if run reached terminal state
              const currentRun = await services.runService.getRun(env, session.userId, runId);
              if (
                currentRun.status === 'completed' ||
                currentRun.status === 'failed' ||
                currentRun.status === 'cancelled'
              ) {
                enqueue(sseFrame('done', { status: currentRun.status }));
                isRunning = false;
              } else {
                await new Promise((resolve) => setTimeout(resolve, SSE_POLL_INTERVAL_MS));
              }
            } catch (error) {
              const message = error instanceof Error ? error.message : 'unknown_error';
              enqueue(sseFrame('error', { message }));
              isRunning = false;
            }
          }
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
