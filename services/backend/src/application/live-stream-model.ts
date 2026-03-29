export type LiveToolCallType = 'web_search' | 'code_interpreter' | 'file_search';

export type LiveToolCallStatus =
  | 'in_progress'
  | 'searching'
  | 'interpreting'
  | 'file_searching'
  | 'completed';

export interface LiveToolCall {
  readonly id: string;
  readonly type: LiveToolCallType;
  readonly status: LiveToolCallStatus;
  readonly code: string | null;
  readonly results: readonly string[] | null;
  readonly queries: readonly string[] | null;
}

export interface LiveCitation {
  readonly url: string;
  readonly title: string;
  readonly startIndex: number;
  readonly endIndex: number;
}

export interface LiveFilePathAnnotation {
  readonly fileId: string;
  readonly containerId: string | null;
  readonly sandboxPath: string;
  readonly filename: string | null;
  readonly startIndex: number;
  readonly endIndex: number;
}

export interface StreamingConversationMessage {
  readonly content: string;
  readonly role: 'assistant' | 'system' | 'user';
}

export interface StreamingConversationRequest {
  readonly input: string | readonly StreamingConversationMessage[];
}

export type LiveStreamEvent =
  | {
      readonly kind: 'citation_added';
      readonly citation: LiveCitation;
    }
  | {
      readonly kind: 'completed';
      readonly citations: readonly LiveCitation[];
      readonly filePathAnnotations: readonly LiveFilePathAnnotation[];
      readonly outputText: string;
      readonly thinkingText: string | null;
      readonly toolCalls: readonly LiveToolCall[];
    }
  | {
      readonly kind: 'failed';
      readonly errorMessage: string;
    }
  | {
      readonly kind: 'file_path_annotation_added';
      readonly annotation: LiveFilePathAnnotation;
    }
  | {
      readonly kind: 'incomplete';
      readonly citations: readonly LiveCitation[];
      readonly errorMessage: string | null;
      readonly filePathAnnotations: readonly LiveFilePathAnnotation[];
      readonly outputText: string;
      readonly thinkingText: string | null;
      readonly toolCalls: readonly LiveToolCall[];
    }
  | {
      readonly kind: 'response_created';
      readonly responseId: string;
    }
  | {
      readonly kind: 'text_delta';
      readonly textDelta: string;
    }
  | {
      readonly kind: 'thinking_delta';
      readonly thinkingDelta: string;
    }
  | {
      readonly kind: 'thinking_finished';
    }
  | {
      readonly kind: 'tool_call_updated';
      readonly toolCall: LiveToolCall;
    };
