import { z } from 'zod';

import { logError, sanitizeLogValue } from '../../observability/logger.js';
import { requireAuthenticatedSession } from '../require-authenticated-session.js';
import { asBackendRuntimeContext } from '../runtime-context.js';
import type { BackendServices } from '../services.js';
import type { BackendApp } from '../types.js';

const SSE_HEARTBEAT_INTERVAL_MS = 5_000;
const MICRO_BUFFER_MAX_BYTES = 1024;
const MICRO_BUFFER_FLUSH_MS = 50;
const REALTIME_STREAM_UNAVAILABLE = 'realtime_stream_unavailable';
const REALTIME_STREAM_RETRY_MESSAGE = 'Realtime stream became unavailable. Please retry.';
const processSnapshotTaskEnvelopeSchema = z.object({
  tasks: z.array(z.unknown()).optional(),
});

const sseFrame = (event: string, data: unknown, id?: string | null): string => {
  const idLine = id ? `id: ${id}\n` : '';
  return `${idLine}event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
};

const streamErrorFrame = (
  runId: string,
  phase: 'relay' | 'relay_connect',
  id?: string | null,
): string =>
  sseFrame(
    'error',
    {
      code: REALTIME_STREAM_UNAVAILABLE,
      message: REALTIME_STREAM_RETRY_MESSAGE,
      phase,
      runId,
    },
    id,
  );

const appendInitialRunFrames = (
  enqueue: (chunk: string) => void,
  run: {
    readonly id: string;
    readonly stage: string | undefined;
    readonly status: string;
    readonly visibleSummary: string | null | undefined;
    readonly processSnapshotJSON: string | null | undefined;
  },
  eventID?: string | null,
): void => {
  enqueue(
    sseFrame(
      'status',
      {
        runId: run.id,
        stage: run.stage ?? null,
        status: run.status,
        visibleSummary: run.visibleSummary ?? null,
      },
      eventID,
    ),
  );

  if (run.stage) {
    enqueue(
      sseFrame(
        'stage',
        {
          runId: run.id,
          stage: run.stage,
          visibleSummary: run.visibleSummary ?? null,
        },
        eventID,
      ),
    );
  }

  if (!run.processSnapshotJSON) {
    return;
  }

  try {
    const parsed = JSON.parse(run.processSnapshotJSON) as unknown;
    const result = processSnapshotTaskEnvelopeSchema.safeParse(parsed);
    if (!result.success) {
      logError('run_stream_snapshot_decode_failed', {
        errorMessage: sanitizeLogValue(result.error.message),
        runId: run.id,
        stage: run.stage ?? 'unknown',
      });
      return;
    }
    enqueue(
      sseFrame(
        'process_update',
        {
          processSnapshot: result.data,
          runId: run.id,
        },
        eventID,
      ),
    );

    for (const task of result.data.tasks ?? []) {
      enqueue(
        sseFrame(
          'task_update',
          {
            runId: run.id,
            task,
          },
          eventID,
        ),
      );
    }
  } catch (error) {
    logError('run_stream_snapshot_decode_failed', {
      errorMessage: error instanceof Error ? sanitizeLogValue(error.message) : 'unknown_error',
      runId: run.id,
      stage: run.stage ?? 'unknown',
    });
  }
};

const appendInitialAssistantFrames = (
  enqueue: (chunk: string) => void,
  input: {
    readonly annotations?: ReadonlyArray<unknown>;
    readonly content?: string;
    readonly filePathAnnotations?: ReadonlyArray<unknown>;
    readonly id?: string | null;
    readonly runId: string;
    readonly thinking?: string;
    readonly toolCalls?: ReadonlyArray<unknown>;
  },
): void => {
  if (input.thinking && input.thinking.length > 0) {
    enqueue(
      sseFrame('thinking_delta', { runId: input.runId, thinkingDelta: input.thinking }, input.id),
    );
  }

  for (const toolCall of input.toolCalls ?? []) {
    enqueue(sseFrame('tool_call_update', { runId: input.runId, toolCall }, input.id));
  }

  if ((input.annotations?.length ?? 0) > 0) {
    enqueue(
      sseFrame('citations_update', { citations: input.annotations, runId: input.runId }, input.id),
    );
  }

  if ((input.filePathAnnotations?.length ?? 0) > 0) {
    enqueue(
      sseFrame(
        'file_path_annotations_update',
        { filePathAnnotations: input.filePathAnnotations, runId: input.runId },
        input.id,
      ),
    );
  }

  if (input.content && input.content.length > 0) {
    enqueue(sseFrame('delta', { runId: input.runId, textDelta: input.content }, input.id));
  }
};

export const installRunStreamRoutes = (app: BackendApp, services: BackendServices): void => {
  app.get('/v1/runs/:runId/stream', async (context) => {
    const session = await requireAuthenticatedSession(context, services);
    const env = asBackendRuntimeContext(context.env);
    const runId = context.req.param('runId');
    const lastEventID = context.req.header('Last-Event-ID') ?? null;

    // Resolve the run and its conversation to connect to the right Durable Object
    const initialRun = await services.runService.getRun(env, session.userId, runId);
    const conversationId = initialRun.conversationId;
    const initialConversationDetail = await services.conversationService.getConversationDetail(
      env,
      session.userId,
      conversationId,
    );
    const initialAssistantMessage =
      [...initialConversationDetail.messages]
        .filter((message) => message.role === 'assistant' && message.runId === runId)
        .sort((left, right) => {
          if (left.createdAt !== right.createdAt) {
            return left.createdAt.localeCompare(right.createdAt);
          }

          return left.id.localeCompare(right.id);
        })
        .at(-1) ?? null;
    const snapshotEventID =
      initialRun.lastEventCursor ??
      initialAssistantMessage?.serverCursor ??
      initialConversationDetail.conversation.lastSyncCursor ??
      null;

    let durableObjectResponse: Response | null = null;
    if (
      initialRun.status !== 'completed' &&
      initialRun.status !== 'failed' &&
      initialRun.status !== 'cancelled'
    ) {
      const durableObjectId = context.env.CONVERSATION_EVENT_HUB.idFromName(conversationId);
      const stub = context.env.CONVERSATION_EVENT_HUB.get(durableObjectId);
      const durableObjectRequestInit = lastEventID
        ? ({ headers: { 'Last-Event-ID': lastEventID } } satisfies RequestInit)
        : ({} satisfies RequestInit);
      durableObjectResponse = await stub.fetch(
        `https://conversation-event-hub/stream/${runId}`,
        durableObjectRequestInit,
      );

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

          if (initialAssistantMessage) {
            appendInitialAssistantFrames(enqueue, {
              content: initialAssistantMessage.content,
              id: snapshotEventID,
              runId: initialRun.id,
              ...(initialAssistantMessage.annotations
                ? { annotations: initialAssistantMessage.annotations }
                : {}),
              ...(initialAssistantMessage.filePathAnnotations
                ? { filePathAnnotations: initialAssistantMessage.filePathAnnotations }
                : {}),
              ...(initialAssistantMessage.thinking
                ? { thinking: initialAssistantMessage.thinking }
                : {}),
              ...(initialAssistantMessage.toolCalls
                ? { toolCalls: initialAssistantMessage.toolCalls }
                : {}),
            });
          }

          appendInitialRunFrames(
            enqueue,
            {
              id: initialRun.id,
              processSnapshotJSON: initialRun.processSnapshotJSON,
              stage: initialRun.stage,
              status: initialRun.status,
              visibleSummary: initialRun.visibleSummary,
            },
            snapshotEventID,
          );

          // If already terminal, send done immediately
          if (
            initialRun.status === 'completed' ||
            initialRun.status === 'failed' ||
            initialRun.status === 'cancelled'
          ) {
            enqueue(sseFrame('done', { status: initialRun.status }, snapshotEventID));
            cleanup();
            controller.close();
            return;
          }

          if (!durableObjectResponse?.body) {
            enqueue(streamErrorFrame(runId, 'relay_connect', snapshotEventID));
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

              enqueue(frame);
            }
          }

          flushMicroBuffer();

          // DO stream ended without done — check terminal state and close
          const finalRun = await services.runService.getRun(env, session.userId, runId);
          enqueue(
            sseFrame(
              'done',
              { status: finalRun.status },
              finalRun.lastEventCursor ?? snapshotEventID,
            ),
          );
        } catch (error) {
          logError('run_stream_relay_failed', {
            errorMessage:
              error instanceof Error ? sanitizeLogValue(error.message) : 'unknown_error',
            runId,
          });
          enqueue(streamErrorFrame(runId, 'relay', snapshotEventID));
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
