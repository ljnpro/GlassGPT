import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

const SSE_HEARTBEAT_INTERVAL_MS = 5_000;
const MICRO_BUFFER_MAX_BYTES = 1024;
const MICRO_BUFFER_FLUSH_MS = 50;
const REALTIME_STREAM_UNAVAILABLE = 'realtime_stream_unavailable';

const sseFrame = (event: string, data: unknown): string => {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
};

const appendInitialRunFrames = (
  enqueue: (chunk: string) => void,
  run: {
    readonly id: string;
    readonly stage: string | undefined;
    readonly status: string;
    readonly visibleSummary: string | null | undefined;
    readonly processSnapshotJSON: string | null | undefined;
  },
): void => {
  enqueue(
    sseFrame('status', {
      runId: run.id,
      stage: run.stage ?? null,
      status: run.status,
      visibleSummary: run.visibleSummary ?? null,
    }),
  );

  if (run.stage) {
    enqueue(
      sseFrame('stage', {
        runId: run.id,
        stage: run.stage,
        visibleSummary: run.visibleSummary ?? null,
      }),
    );
  }

  if (!run.processSnapshotJSON) {
    return;
  }

  try {
    const processSnapshot = JSON.parse(run.processSnapshotJSON) as {
      readonly tasks?: ReadonlyArray<unknown>;
    };
    enqueue(
      sseFrame('process_update', {
        processSnapshot,
        runId: run.id,
      }),
    );

    for (const task of processSnapshot.tasks ?? []) {
      enqueue(
        sseFrame('task_update', {
          runId: run.id,
          task,
        }),
      );
    }
  } catch {
    // Ignore malformed process snapshots rather than aborting the stream.
  }
};

export const installRunStreamRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/runs/:runId/stream', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const env = asBackendRuntimeContext(context.env);
    const runId = context.req.param('runId');

    // Resolve the run and its conversation to connect to the right Durable Object
    const initialRun = await services.runService.getRun(env, session.userId, runId);
    const conversationId = initialRun.conversationId;

    let durableObjectResponse: Response | null = null;
    if (
      initialRun.status !== 'completed' &&
      initialRun.status !== 'failed' &&
      initialRun.status !== 'cancelled'
    ) {
      const durableObjectId = context.env.CONVERSATION_EVENT_HUB.idFromName(conversationId);
      const stub = context.env.CONVERSATION_EVENT_HUB.get(durableObjectId);
      durableObjectResponse = await stub.fetch(`https://conversation-event-hub/stream/${runId}`);

      if (!durableObjectResponse.ok) {
        return context.json({ error: REALTIME_STREAM_UNAVAILABLE }, 503);
      }

      if (!durableObjectResponse.body) {
        return context.json({ error: REALTIME_STREAM_UNAVAILABLE }, 503);
      }
    }

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
        let pendingMicroFlush: ReturnType<typeof setTimeout> | null = null;
        const cleanup = (): void => {
          if (heartbeatTimer !== null) {
            clearInterval(heartbeatTimer);
            heartbeatTimer = null;
          }
          if (pendingMicroFlush !== null) {
            clearTimeout(pendingMicroFlush);
            pendingMicroFlush = null;
          }
        };

        try {
          heartbeatTimer = setInterval(() => {
            enqueue(': ping\n\n');
          }, SSE_HEARTBEAT_INTERVAL_MS);

          appendInitialRunFrames(enqueue, {
            id: initialRun.id,
            processSnapshotJSON: initialRun.processSnapshotJSON,
            stage: initialRun.stage,
            status: initialRun.status,
            visibleSummary: initialRun.visibleSummary,
          });

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

          if (!durableObjectResponse?.body) {
            enqueue(sseFrame('error', { message: REALTIME_STREAM_UNAVAILABLE, runId }));
            cleanup();
            controller.close();
            return;
          }

          // Relay events from the Durable Object to the client (pre-filtered by runId at DO level)
          const reader = durableObjectResponse.body.getReader();
          const decoder = new TextDecoder();
          let parseBuffer = '';
          let microBuffer = '';
          let microFlushTimer: ReturnType<typeof setTimeout> | null = null;

          const flushMicroBuffer = (): void => {
            if (microBuffer.length > 0) {
              enqueue(microBuffer);
              microBuffer = '';
            }
            if (microFlushTimer !== null) {
              clearTimeout(microFlushTimer);
              microFlushTimer = null;
            }
          };

          const enqueueMicroBuffered = (frame: string): void => {
            microBuffer += frame;
            if (microBuffer.length >= MICRO_BUFFER_MAX_BYTES) {
              flushMicroBuffer();
            } else if (microFlushTimer === null) {
              microFlushTimer = setTimeout(flushMicroBuffer, MICRO_BUFFER_FLUSH_MS);
            }
          };

          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            parseBuffer += decoder.decode(value, { stream: true });

            // Forward complete SSE frames (ending with \n\n)
            while (parseBuffer.includes('\n\n')) {
              const frameEnd = parseBuffer.indexOf('\n\n');
              const frame = parseBuffer.slice(0, frameEnd + 2);
              parseBuffer = parseBuffer.slice(frameEnd + 2);

              // Skip comment lines (heartbeats from DO)
              if (frame.startsWith(':')) {
                continue;
              }

              // Check for done event — flush immediately and close
              if (frame.includes('event: done')) {
                flushMicroBuffer();
                enqueue(frame);
                cleanup();
                reader.releaseLock();
                controller.close();
                return;
              }

              enqueueMicroBuffered(frame);
            }
          }

          flushMicroBuffer();

          // DO stream ended without done — check terminal state and close
          const finalRun = await services.runService.getRun(env, session.userId, runId);
          enqueue(sseFrame('done', { status: finalRun.status }));
        } catch {
          enqueue(sseFrame('error', { message: REALTIME_STREAM_UNAVAILABLE, runId }));
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
