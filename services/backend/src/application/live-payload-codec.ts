import type { MessageRecord } from '../domain/message-model.js';
import type { LiveCitation, LiveFilePathAnnotation, LiveToolCall } from './live-stream-model.js';

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
    citations: message.annotationsJSON
      ? (JSON.parse(message.annotationsJSON) as LiveCitation[])
      : [],
    content: message.content,
    filePathAnnotations: message.filePathAnnotationsJSON
      ? (JSON.parse(message.filePathAnnotationsJSON) as LiveFilePathAnnotation[])
      : [],
    thinking: message.thinking,
    toolCalls: message.toolCallsJSON ? (JSON.parse(message.toolCallsJSON) as LiveToolCall[]) : [],
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
