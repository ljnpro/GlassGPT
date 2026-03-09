import { Message, ModelId, ReasoningEffort, ImageAttachment } from './types';

interface StreamCallbacks {
  onToken: (text: string) => void;
  onReasoning?: (text: string) => void;
  onDone: () => void;
  onError: (error: string) => void;
}

function buildMessages(messages: Message[]): any[] {
  return messages.map((msg) => {
    if (msg.role === 'user' && msg.images && msg.images.length > 0) {
      const content: any[] = [];
      if (msg.content) {
        content.push({ type: 'text', text: msg.content });
      }
      for (const img of msg.images) {
        const url = img.base64
          ? `data:${img.mimeType || 'image/jpeg'};base64,${img.base64}`
          : img.uri;
        content.push({
          type: 'image_url',
          image_url: { url, detail: 'auto' },
        });
      }
      return { role: msg.role, content };
    }
    return { role: msg.role, content: msg.content };
  });
}

export async function streamChatCompletion(
  apiKey: string,
  messages: Message[],
  model: ModelId,
  effort: ReasoningEffort,
  callbacks: StreamCallbacks,
  abortSignal?: AbortSignal
): Promise<void> {
  const apiMessages = buildMessages(messages);

  const body: any = {
    model,
    messages: apiMessages,
    stream: true,
  };

  // Add reasoning effort if not 'none'
  if (effort !== 'none') {
    body.reasoning = { effort };
  }

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
      signal: abortSignal,
    });

    if (!response.ok) {
      const errBody = await response.text();
      let errMsg = `API Error ${response.status}`;
      try {
        const parsed = JSON.parse(errBody);
        errMsg = parsed.error?.message || errMsg;
      } catch {}
      callbacks.onError(errMsg);
      return;
    }

    const reader = response.body?.getReader();
    if (!reader) {
      callbacks.onError('No response body');
      return;
    }

    const decoder = new TextDecoder();
    let buffer = '';
    let fullText = '';
    let fullReasoning = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || !trimmed.startsWith('data: ')) continue;
        const data = trimmed.slice(6);
        if (data === '[DONE]') {
          callbacks.onDone();
          return;
        }

        try {
          const parsed = JSON.parse(data);
          const delta = parsed.choices?.[0]?.delta;
          if (!delta) continue;

          // Handle reasoning content (thinking tokens)
          if (delta.reasoning_content) {
            fullReasoning += delta.reasoning_content;
            callbacks.onReasoning?.(fullReasoning);
          }

          // Handle regular content
          if (delta.content) {
            fullText += delta.content;
            callbacks.onToken(fullText);
          }
        } catch {
          // Skip malformed JSON
        }
      }
    }

    callbacks.onDone();
  } catch (error: any) {
    if (error.name === 'AbortError') {
      callbacks.onDone();
      return;
    }
    callbacks.onError(error.message || 'Unknown error');
  }
}

export async function validateApiKey(apiKey: string): Promise<{ valid: boolean; error?: string }> {
  try {
    const response = await fetch('https://api.openai.com/v1/models', {
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (response.ok) return { valid: true };
    if (response.status === 401) return { valid: false, error: 'Invalid API key' };
    return { valid: false, error: `Error: ${response.status}` };
  } catch (error: any) {
    return { valid: false, error: error.message || 'Network error' };
  }
}

export async function generateTitle(apiKey: string, firstMessage: string): Promise<string> {
  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: 'Generate a very short title (max 6 words) for a conversation that starts with the following message. Return only the title, no quotes.',
          },
          { role: 'user', content: firstMessage },
        ],
        max_tokens: 20,
      }),
    });
    if (!response.ok) return 'New Chat';
    const data = await response.json();
    return data.choices?.[0]?.message?.content?.trim() || 'New Chat';
  } catch {
    return 'New Chat';
  }
}
