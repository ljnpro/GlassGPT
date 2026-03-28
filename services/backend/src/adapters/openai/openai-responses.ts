const DEFAULT_CHAT_MODEL = 'gpt-5.4';

interface ResponsesApiBody {
  readonly output?: ReadonlyArray<{
    readonly content?: ReadonlyArray<{
      readonly text?: string;
      readonly type?: string;
    }>;
    readonly type?: string;
  }>;
  readonly output_text?: string;
}

const extractOutputText = (body: ResponsesApiBody): string | null => {
  if (typeof body.output_text === 'string' && body.output_text.length > 0) {
    return body.output_text;
  }

  const parts =
    body.output?.flatMap((item) => {
      return (
        item.content?.flatMap((contentPart) => {
          return typeof contentPart.text === 'string' && contentPart.text.length > 0
            ? [contentPart.text]
            : [];
        }) ?? []
      );
    }) ?? [];

  return parts.length > 0 ? parts.join('') : null;
};

export const createChatCompletion = async (apiKey: string, input: string): Promise<string> => {
  const response = await fetch('https://api.openai.com/v1/responses', {
    body: JSON.stringify({
      input,
      model: DEFAULT_CHAT_MODEL,
    }),
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    method: 'POST',
  });

  if (!response.ok) {
    const responseText = await response.text();
    throw new Error(responseText.length > 0 ? responseText : `openai_status_${response.status}`);
  }

  const responseBody = (await response.json()) as ResponsesApiBody;
  const outputText = extractOutputText(responseBody);
  if (!outputText) {
    throw new Error('openai_response_missing_output_text');
  }

  return outputText;
};
