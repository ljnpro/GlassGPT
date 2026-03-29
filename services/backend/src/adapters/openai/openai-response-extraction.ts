import type {
  LiveCitation,
  LiveFilePathAnnotation,
  LiveToolCall,
  LiveToolCallStatus,
  LiveToolCallType,
} from '../../application/live-stream-model.js';

interface ResponsesTextFragment {
  readonly text?: string;
}

interface ResponsesAnnotation {
  readonly container_id?: string;
  readonly end_index?: number;
  readonly file_id?: string;
  readonly filename?: string;
  readonly start_index?: number;
  readonly title?: string;
  readonly type: string;
  readonly url?: string;
}

interface ResponsesCodeInterpreterOutput {
  readonly logs?: string;
  readonly output?: string;
  readonly text?: string;
}

interface ResponsesContentPart {
  readonly annotations?: readonly ResponsesAnnotation[];
  readonly text?: string;
  readonly type?: string;
}

interface ResponsesAction {
  readonly queries?: readonly string[];
  readonly query?: string;
}

interface ResponsesOutputItem {
  readonly action?: ResponsesAction;
  readonly code?: string;
  readonly content?: readonly ResponsesContentPart[];
  readonly id?: string;
  readonly outputs?: readonly ResponsesCodeInterpreterOutput[];
  readonly phase?: string;
  readonly queries?: readonly string[];
  readonly query?: string;
  readonly results?: readonly ResponsesCodeInterpreterOutput[];
  readonly role?: string;
  readonly status?: string;
  readonly summary?: readonly ResponsesTextFragment[];
  readonly text?: string;
  readonly type: string;
}

export interface ResponsesResponse {
  readonly error?: {
    readonly message?: string;
  };
  readonly id?: string;
  readonly message?: string;
  readonly output?: readonly ResponsesOutputItem[];
  readonly output_text?: string;
  readonly reasoning?: {
    readonly summary?: readonly ResponsesTextFragment[];
    readonly text?: string;
  };
}

const collectTextOutputs = (
  outputs: readonly ResponsesCodeInterpreterOutput[] | undefined,
): string[] => {
  return (
    outputs?.flatMap((output) => {
      if (typeof output.output === 'string' && output.output.length > 0) {
        return [output.output];
      }
      if (typeof output.text === 'string' && output.text.length > 0) {
        return [output.text];
      }
      if (typeof output.logs === 'string' && output.logs.length > 0) {
        return [output.logs];
      }
      return [];
    }) ?? []
  );
};

const substringByCharacterRange = (text: string, startIndex: number, endIndex: number): string => {
  if (text.length === 0 || startIndex < 0 || endIndex <= startIndex) {
    return '';
  }

  const characters = [...text];
  if (startIndex >= characters.length) {
    return '';
  }

  const safeEndIndex = Math.min(endIndex, characters.length);
  if (safeEndIndex <= startIndex) {
    return '';
  }

  return characters.slice(startIndex, safeEndIndex).join('');
};

const normalizeToolQueries = (
  item: Pick<ResponsesOutputItem, 'action' | 'queries' | 'query'>,
): readonly string[] | null => {
  if (item.action?.query) {
    return [item.action.query];
  }
  if (item.action?.queries && item.action.queries.length > 0) {
    return [...item.action.queries];
  }
  if (item.query) {
    return [item.query];
  }
  if (item.queries && item.queries.length > 0) {
    return [...item.queries];
  }
  return null;
};

const buildToolCall = (
  id: string,
  type: LiveToolCallType,
  status: LiveToolCallStatus,
  input?: Partial<Omit<LiveToolCall, 'id' | 'status' | 'type'>>,
): LiveToolCall => {
  return {
    code: input?.code ?? null,
    id,
    queries: input?.queries ?? null,
    results: input?.results ?? null,
    status,
    type,
  };
};

export const extractOutputText = (response: ResponsesResponse): string => {
  if (typeof response.output_text === 'string' && response.output_text.length > 0) {
    return response.output_text;
  }

  const parts =
    response.output?.flatMap((item) => {
      return (
        item.content?.flatMap((contentPart) => {
          return typeof contentPart.text === 'string' && contentPart.text.length > 0
            ? [contentPart.text]
            : [];
        }) ?? []
      );
    }) ?? [];

  return parts.join('');
};

export const extractReasoningText = (response: ResponsesResponse): string | null => {
  const fragments: string[] = [];

  if (typeof response.reasoning?.text === 'string' && response.reasoning.text.length > 0) {
    fragments.push(response.reasoning.text);
  }

  if (response.reasoning?.summary) {
    fragments.push(
      ...response.reasoning.summary.flatMap((fragment) =>
        typeof fragment.text === 'string' && fragment.text.length > 0 ? [fragment.text] : [],
      ),
    );
  }

  if (response.output) {
    for (const item of response.output) {
      if (item.type !== 'reasoning') {
        continue;
      }

      if (typeof item.text === 'string' && item.text.length > 0) {
        fragments.push(item.text);
      }

      if (item.summary) {
        fragments.push(
          ...item.summary.flatMap((fragment) =>
            typeof fragment.text === 'string' && fragment.text.length > 0 ? [fragment.text] : [],
          ),
        );
      }

      if (item.content) {
        fragments.push(
          ...item.content.flatMap((contentPart) =>
            typeof contentPart.text === 'string' && contentPart.text.length > 0
              ? [contentPart.text]
              : [],
          ),
        );
      }
    }
  }

  if (fragments.length === 0) {
    return null;
  }

  return fragments.join('');
};

export const extractCitations = (response: ResponsesResponse): LiveCitation[] => {
  const citations: LiveCitation[] = [];

  for (const item of response.output ?? []) {
    for (const contentPart of item.content ?? []) {
      for (const annotation of contentPart.annotations ?? []) {
        if (
          annotation.type === 'url_citation' &&
          typeof annotation.url === 'string' &&
          typeof annotation.title === 'string'
        ) {
          citations.push({
            endIndex: annotation.end_index ?? 0,
            startIndex: annotation.start_index ?? 0,
            title: annotation.title,
            url: annotation.url,
          });
        }
      }
    }
  }

  return citations;
};

export const extractFilePathAnnotations = (
  response: ResponsesResponse,
): LiveFilePathAnnotation[] => {
  const outputText = extractOutputText(response);
  const annotations: LiveFilePathAnnotation[] = [];

  for (const item of response.output ?? []) {
    for (const contentPart of item.content ?? []) {
      for (const annotation of contentPart.annotations ?? []) {
        if (
          (annotation.type === 'file_path' || annotation.type === 'container_file_citation') &&
          typeof annotation.file_id === 'string' &&
          annotation.file_id.length > 0
        ) {
          const startIndex = annotation.start_index ?? 0;
          const endIndex = annotation.end_index ?? 0;
          annotations.push({
            containerId: annotation.container_id ?? null,
            endIndex,
            fileId: annotation.file_id,
            filename: annotation.filename ?? null,
            sandboxPath: substringByCharacterRange(outputText, startIndex, endIndex),
            startIndex,
          });
        }
      }
    }
  }

  return annotations;
};

export const extractToolCalls = (response: ResponsesResponse): LiveToolCall[] => {
  const toolCalls: LiveToolCall[] = [];

  for (const item of response.output ?? []) {
    const id = item.id ?? crypto.randomUUID();

    switch (item.type) {
      case 'web_search_call':
        toolCalls.push(
          buildToolCall(id, 'web_search', 'completed', {
            queries: normalizeToolQueries(item),
          }),
        );
        break;

      case 'code_interpreter_call':
        toolCalls.push(
          buildToolCall(id, 'code_interpreter', 'completed', {
            code: item.code ?? null,
            results: [...collectTextOutputs(item.results), ...collectTextOutputs(item.outputs)],
          }),
        );
        break;

      case 'file_search_call':
        toolCalls.push(
          buildToolCall(id, 'file_search', 'completed', {
            queries: normalizeToolQueries(item),
          }),
        );
        break;

      default:
        break;
    }
  }

  return toolCalls;
};

export const extractErrorMessage = (response: ResponsesResponse): string | null => {
  if (typeof response.error?.message === 'string' && response.error.message.length > 0) {
    return response.error.message;
  }

  if (typeof response.message === 'string' && response.message.length > 0) {
    return response.message;
  }

  return null;
};

export const mergeToolCalls = (
  existing: readonly LiveToolCall[],
  incoming: readonly LiveToolCall[],
): LiveToolCall[] => {
  const toolCallsById = new Map(existing.map((toolCall) => [toolCall.id, toolCall] as const));
  for (const toolCall of incoming) {
    toolCallsById.set(toolCall.id, toolCall);
  }
  return [...toolCallsById.values()];
};

export const mergeCitations = (
  existing: readonly LiveCitation[],
  incoming: readonly LiveCitation[],
): LiveCitation[] => {
  const merged = new Map<string, LiveCitation>();
  for (const citation of [...existing, ...incoming]) {
    const key = `${citation.url}:${citation.startIndex}:${citation.endIndex}`;
    merged.set(key, citation);
  }
  return [...merged.values()];
};

export const mergeFilePathAnnotations = (
  existing: readonly LiveFilePathAnnotation[],
  incoming: readonly LiveFilePathAnnotation[],
): LiveFilePathAnnotation[] => {
  const merged = new Map<string, LiveFilePathAnnotation>();
  for (const annotation of [...existing, ...incoming]) {
    const key = `${annotation.fileId}:${annotation.startIndex}:${annotation.endIndex}`;
    merged.set(key, annotation);
  }
  return [...merged.values()];
};
