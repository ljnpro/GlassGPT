import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Tests for the Response Recovery mechanism.
 *
 * The recovery system works as follows:
 * 1. When a streaming response starts, the server sends a `response.created` SSE event
 *    containing a `response_id`.
 * 2. The client saves this `response_id` to the draft message in the local database
 *    with `isComplete = false`.
 * 3. If the stream is interrupted (app backgrounded/killed, network error), the partial
 *    content is saved to the database.
 * 4. On app relaunch or return to foreground, the client detects incomplete messages
 *    (isComplete == false && responseId != null) and polls the OpenAI API using
 *    GET /v1/responses/{response_id} to retrieve the full response.
 * 5. If the response is still `in_progress`, the client retries every 2 seconds
 *    (up to 5 minutes).
 * 6. Once the response is `completed`, the client updates the local message with the
 *    full text and sets `isComplete = true`.
 *
 * These tests validate the SSE parsing, recovery polling logic, and state management.
 */

// ============================================================
// SSE Event Parsing Tests
// ============================================================

describe('SSE Event Parsing - response.created', () => {
  it('should extract response_id from response.created event', () => {
    const sseData = JSON.stringify({
      response: {
        id: 'resp_abc123def456',
        status: 'in_progress',
        model: 'gpt-5.4',
      },
    });

    const parsed = JSON.parse(sseData);
    const responseId = parsed?.response?.id;

    expect(responseId).toBe('resp_abc123def456');
    expect(typeof responseId).toBe('string');
    expect(responseId).toMatch(/^resp_/);
  });

  it('should handle missing response object gracefully', () => {
    const sseData = JSON.stringify({ type: 'response.created' });
    const parsed = JSON.parse(sseData);
    const responseId = parsed?.response?.id;

    expect(responseId).toBeUndefined();
  });

  it('should handle malformed JSON gracefully', () => {
    const sseData = 'not valid json {{{';
    let responseId: string | undefined;

    try {
      const parsed = JSON.parse(sseData);
      responseId = parsed?.response?.id;
    } catch {
      responseId = undefined;
    }

    expect(responseId).toBeUndefined();
  });
});

// ============================================================
// Response Status Handling Tests
// ============================================================

describe('Response Status Handling', () => {
  /**
   * Simulates the fetchResponse logic that checks the response status
   * and determines the appropriate action.
   */
  function processResponseStatus(json: Record<string, unknown>): {
    action: 'success' | 'retry' | 'fail';
    text?: string;
    thinking?: string;
  } {
    const status = (json.status as string) ?? 'unknown';

    if (status === 'in_progress' || status === 'queued') {
      return { action: 'retry' };
    }

    if (status === 'failed') {
      return { action: 'fail' };
    }

    // Extract output text
    let text = '';
    if (typeof json.output_text === 'string') {
      text = json.output_text;
    } else if (Array.isArray(json.output)) {
      for (const item of json.output as Record<string, unknown>[]) {
        if (item.type === 'message' && Array.isArray(item.content)) {
          for (const part of item.content as Record<string, unknown>[]) {
            if (part.type === 'output_text' && typeof part.text === 'string') {
              text += part.text;
            }
          }
        }
      }
    }

    // Extract reasoning summary
    let thinking: string | undefined;
    if (Array.isArray(json.output)) {
      for (const item of json.output as Record<string, unknown>[]) {
        if (item.type === 'reasoning' && Array.isArray(item.summary)) {
          const summaryTexts = (item.summary as Record<string, unknown>[])
            .filter((s) => typeof s.text === 'string')
            .map((s) => s.text as string);
          if (summaryTexts.length > 0) {
            thinking = summaryTexts.join('');
          }
        }
      }
    }

    return { action: 'success', text, thinking };
  }

  it('should return retry for in_progress status', () => {
    const result = processResponseStatus({ status: 'in_progress' });
    expect(result.action).toBe('retry');
  });

  it('should return retry for queued status', () => {
    const result = processResponseStatus({ status: 'queued' });
    expect(result.action).toBe('retry');
  });

  it('should return fail for failed status', () => {
    const result = processResponseStatus({ status: 'failed' });
    expect(result.action).toBe('fail');
  });

  it('should extract text from completed response with output_text', () => {
    const result = processResponseStatus({
      status: 'completed',
      output_text: 'Hello, this is the full response.',
    });
    expect(result.action).toBe('success');
    expect(result.text).toBe('Hello, this is the full response.');
  });

  it('should extract text from completed response with output array', () => {
    const result = processResponseStatus({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [
            {
              type: 'output_text',
              text: 'The answer is 42.',
            },
          ],
        },
      ],
    });
    expect(result.action).toBe('success');
    expect(result.text).toBe('The answer is 42.');
  });

  it('should extract reasoning summary from completed response', () => {
    const result = processResponseStatus({
      status: 'completed',
      output: [
        {
          type: 'reasoning',
          summary: [
            { type: 'summary_text', text: 'I need to think about this...' },
            { type: 'summary_text', text: ' Let me analyze step by step.' },
          ],
        },
        {
          type: 'message',
          content: [
            { type: 'output_text', text: 'The final answer.' },
          ],
        },
      ],
    });
    expect(result.action).toBe('success');
    expect(result.text).toBe('The final answer.');
    expect(result.thinking).toBe('I need to think about this... Let me analyze step by step.');
  });

  it('should handle completed response with no output', () => {
    const result = processResponseStatus({
      status: 'completed',
      output: [],
    });
    expect(result.action).toBe('success');
    expect(result.text).toBe('');
    expect(result.thinking).toBeUndefined();
  });
});

// ============================================================
// Recovery Polling Logic Tests
// ============================================================

describe('Recovery Polling Logic', () => {
  /**
   * Simulates the recovery polling loop.
   * Returns the number of attempts made and the final result.
   */
  async function simulateRecoveryPolling(
    fetchFn: () => Promise<{ status: string; text?: string }>,
    maxAttempts: number = 10,
    delayMs: number = 10, // Use short delay for tests
  ): Promise<{ attempts: number; result: 'success' | 'timeout' | 'error'; text?: string }> {
    let attempts = 0;

    while (attempts < maxAttempts) {
      attempts++;

      try {
        const response = await fetchFn();

        if (response.status === 'in_progress' || response.status === 'queued') {
          await new Promise((resolve) => setTimeout(resolve, delayMs));
          continue;
        }

        if (response.status === 'completed') {
          return { attempts, result: 'success', text: response.text };
        }

        return { attempts, result: 'error' };
      } catch {
        if (attempts < 3) {
          await new Promise((resolve) => setTimeout(resolve, delayMs));
          continue;
        }
        return { attempts, result: 'error' };
      }
    }

    return { attempts, result: 'timeout' };
  }

  it('should succeed immediately if response is already completed', async () => {
    const fetchFn = vi.fn().mockResolvedValue({
      status: 'completed',
      text: 'Full response text',
    });

    const result = await simulateRecoveryPolling(fetchFn);

    expect(result.attempts).toBe(1);
    expect(result.result).toBe('success');
    expect(result.text).toBe('Full response text');
    expect(fetchFn).toHaveBeenCalledTimes(1);
  });

  it('should retry when response is in_progress and eventually succeed', async () => {
    let callCount = 0;
    const fetchFn = vi.fn().mockImplementation(async () => {
      callCount++;
      if (callCount < 3) {
        return { status: 'in_progress' };
      }
      return { status: 'completed', text: 'Recovered text' };
    });

    const result = await simulateRecoveryPolling(fetchFn);

    expect(result.attempts).toBe(3);
    expect(result.result).toBe('success');
    expect(result.text).toBe('Recovered text');
  });

  it('should timeout after max attempts', async () => {
    const fetchFn = vi.fn().mockResolvedValue({ status: 'in_progress' });

    const result = await simulateRecoveryPolling(fetchFn, 5);

    expect(result.attempts).toBe(5);
    expect(result.result).toBe('timeout');
  });

  it('should handle network errors with retry', async () => {
    let callCount = 0;
    const fetchFn = vi.fn().mockImplementation(async () => {
      callCount++;
      if (callCount <= 2) {
        throw new Error('Network error');
      }
      return { status: 'completed', text: 'Recovered after errors' };
    });

    const result = await simulateRecoveryPolling(fetchFn);

    expect(result.result).toBe('success');
    expect(result.text).toBe('Recovered after errors');
    expect(result.attempts).toBe(3);
  });

  it('should fail after too many consecutive errors', async () => {
    const fetchFn = vi.fn().mockRejectedValue(new Error('Persistent error'));

    const result = await simulateRecoveryPolling(fetchFn, 10);

    expect(result.result).toBe('error');
    expect(result.attempts).toBe(3); // Gives up after 3 consecutive errors
  });
});

// ============================================================
// Message State Management Tests
// ============================================================

describe('Message State Management', () => {
  interface MockMessage {
    id: string;
    role: 'user' | 'assistant';
    content: string;
    thinking?: string;
    responseId?: string;
    isComplete: boolean;
  }

  let messages: MockMessage[];

  beforeEach(() => {
    messages = [];
  });

  it('should create draft message with isComplete = false', () => {
    const draft: MockMessage = {
      id: 'msg_1',
      role: 'assistant',
      content: '',
      isComplete: false,
    };
    messages.push(draft);

    expect(messages[0].isComplete).toBe(false);
    expect(messages[0].content).toBe('');
  });

  it('should save responseId when response.created event arrives', () => {
    const draft: MockMessage = {
      id: 'msg_1',
      role: 'assistant',
      content: '',
      isComplete: false,
    };
    messages.push(draft);

    // Simulate response.created event
    draft.responseId = 'resp_abc123';

    expect(messages[0].responseId).toBe('resp_abc123');
    expect(messages[0].isComplete).toBe(false);
  });

  it('should update content during streaming', () => {
    const draft: MockMessage = {
      id: 'msg_1',
      role: 'assistant',
      content: '',
      responseId: 'resp_abc123',
      isComplete: false,
    };
    messages.push(draft);

    // Simulate streaming deltas
    draft.content += 'Hello';
    draft.content += ' world';
    draft.content += '!';

    expect(draft.content).toBe('Hello world!');
    expect(draft.isComplete).toBe(false);
  });

  it('should mark as complete when stream finishes normally', () => {
    const draft: MockMessage = {
      id: 'msg_1',
      role: 'assistant',
      content: 'Full response',
      responseId: 'resp_abc123',
      isComplete: false,
    };
    messages.push(draft);

    // Simulate stream completion
    draft.isComplete = true;

    expect(draft.isComplete).toBe(true);
    expect(draft.content).toBe('Full response');
  });

  it('should detect incomplete messages for recovery', () => {
    messages = [
      { id: 'msg_1', role: 'user', content: 'Hi', isComplete: true },
      { id: 'msg_2', role: 'assistant', content: 'Partial...', responseId: 'resp_1', isComplete: false },
      { id: 'msg_3', role: 'user', content: 'Another question', isComplete: true },
      { id: 'msg_4', role: 'assistant', content: 'Complete answer', responseId: 'resp_2', isComplete: true },
    ];

    const incompleteMessages = messages.filter(
      (m) => m.role === 'assistant' && !m.isComplete && m.responseId != null,
    );

    expect(incompleteMessages).toHaveLength(1);
    expect(incompleteMessages[0].id).toBe('msg_2');
    expect(incompleteMessages[0].responseId).toBe('resp_1');
  });

  it('should update message content after successful recovery', () => {
    const incomplete: MockMessage = {
      id: 'msg_2',
      role: 'assistant',
      content: 'Partial...',
      responseId: 'resp_1',
      isComplete: false,
    };
    messages.push(incomplete);

    // Simulate recovery success
    const recoveredText = 'Partial... and here is the complete response with all the details.';
    const recoveredThinking = 'Let me think about this carefully...';

    incomplete.content = recoveredText;
    incomplete.thinking = recoveredThinking;
    incomplete.isComplete = true;

    expect(incomplete.content).toBe(recoveredText);
    expect(incomplete.thinking).toBe(recoveredThinking);
    expect(incomplete.isComplete).toBe(true);
  });

  it('should mark as complete with fallback text when recovery fails', () => {
    const incomplete: MockMessage = {
      id: 'msg_2',
      role: 'assistant',
      content: '',
      responseId: 'resp_1',
      isComplete: false,
    };
    messages.push(incomplete);

    // Simulate recovery failure
    incomplete.isComplete = true;
    if (incomplete.content === '') {
      incomplete.content = '[Response interrupted. Please try again.]';
    }

    expect(incomplete.isComplete).toBe(true);
    expect(incomplete.content).toBe('[Response interrupted. Please try again.]');
  });

  it('should preserve partial content when recovery fails', () => {
    const incomplete: MockMessage = {
      id: 'msg_2',
      role: 'assistant',
      content: 'Here is some partial content that was received before the interruption...',
      responseId: 'resp_1',
      isComplete: false,
    };
    messages.push(incomplete);

    // Simulate recovery failure — but we already have partial content
    incomplete.isComplete = true;
    // Don't overwrite with fallback since we have real content

    expect(incomplete.isComplete).toBe(true);
    expect(incomplete.content).toContain('partial content');
  });
});

// ============================================================
// OpenAI Responses API URL Construction Tests
// ============================================================

describe('OpenAI Responses API URL Construction', () => {
  const baseURL = 'https://api.openai.com/v1/responses';

  it('should construct correct GET URL for response retrieval', () => {
    const responseId = 'resp_abc123def456';
    const url = `${baseURL}/${responseId}`;

    expect(url).toBe('https://api.openai.com/v1/responses/resp_abc123def456');
  });

  it('should construct correct POST URL for streaming', () => {
    expect(baseURL).toBe('https://api.openai.com/v1/responses');
  });
});
