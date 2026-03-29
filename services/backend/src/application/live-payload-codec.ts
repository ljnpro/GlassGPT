import { z } from 'zod';
import type { MessageRecord } from '../domain/message-model.js';
import { parseOptionalJSONPayload } from './json-payload-codec.js';
import type { LiveCitation, LiveFilePathAnnotation, LiveToolCall } from './live-stream-model.js';

const liveCitationSchema = z.object({
  endIndex: z.number().int().nonnegative(),
  startIndex: z.number().int().nonnegative(),
  title: z.string(),
  url: z.string().url(),
});

const liveFilePathAnnotationSchema = z.object({
  containerId: z.string().nullable(),
  endIndex: z.number().int().nonnegative(),
  fileId: z.string().min(1),
  filename: z.string().nullable(),
  sandboxPath: z.string(),
  startIndex: z.number().int().nonnegative(),
});

const liveToolCallSchema = z.object({
  code: z.string().nullable(),
  id: z.string().min(1),
  queries: z.array(z.string()).nullable(),
  results: z.array(z.string()).nullable(),
  status: z.enum(['in_progress', 'searching', 'interpreting', 'file_searching', 'completed']),
  type: z.enum(['web_search', 'code_interpreter', 'file_search']),
});

const liveCitationsSchema = z.array(liveCitationSchema);
const liveFilePathAnnotationsSchema = z.array(liveFilePathAnnotationSchema);
const liveToolCallsSchema = z.array(liveToolCallSchema);

export interface MessageLiveState {
  readonly agentTraceJSON?: string | null;
  readonly citations: readonly LiveCitation[];
  readonly content: string;
  readonly filePathAnnotations: readonly LiveFilePathAnnotation[];
  readonly thinking: string | null;
  readonly toolCalls: readonly LiveToolCall[];
}

export const encodeJSON = <T>(value: T | null | undefined): string | null => {
  if (value == null) {
    return null;
  }
  return JSON.stringify(value);
};

export const parseMessageLiveState = (message: MessageRecord): MessageLiveState => {
  return {
    agentTraceJSON: message.agentTraceJSON,
    citations:
      parseOptionalJSONPayload<LiveCitation[]>(message.annotationsJSON, liveCitationsSchema) ?? [],
    content: message.content,
    filePathAnnotations:
      parseOptionalJSONPayload<LiveFilePathAnnotation[]>(
        message.filePathAnnotationsJSON,
        liveFilePathAnnotationsSchema,
      ) ?? [],
    thinking: message.thinking,
    toolCalls:
      parseOptionalJSONPayload<LiveToolCall[]>(message.toolCallsJSON, liveToolCallsSchema) ?? [],
  };
};

export const applyLiveStateToMessage = (
  message: MessageRecord,
  state: MessageLiveState,
  input?: {
    readonly completedAt?: string | null;
    readonly serverCursor?: string | null;
  },
): MessageRecord => {
  return {
    ...message,
    agentTraceJSON: state.agentTraceJSON ?? null,
    annotationsJSON: encodeJSON(state.citations),
    completedAt: input?.completedAt ?? message.completedAt,
    content: state.content,
    filePathAnnotationsJSON: encodeJSON(state.filePathAnnotations),
    serverCursor: input?.serverCursor ?? message.serverCursor,
    thinking: state.thinking,
    toolCallsJSON: encodeJSON(state.toolCalls),
  };
};
