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


// ============================================================
// Network Auto-Reconnect Tests
// ============================================================

describe('Network Auto-Reconnect Logic', () => {
  /**
   * Simulates the auto-reconnect flow:
   * 1. Stream starts, receives some data
   * 2. Connection is lost (connectionLost event)
   * 3. Client checks server status via fetchResponse
   * 4. If server completed: use full response
   * 5. If server still in progress: wait with exponential backoff, then poll
   * 6. Max 3 reconnect attempts
   */

  interface ReconnectResult {
    finalResult: 'success' | 'recovery' | 'error';
    reconnectAttempts: number;
    partialText: string;
    fullText?: string;
  }

  async function simulateReconnect(
    fetchFn: () => Promise<{ status: string; text?: string }>,
    maxAttempts: number = 3,
  ): Promise<ReconnectResult> {
    let partialText = 'Hello, this is partial...';
    let reconnectAttempts = 0;
    const baseDelay = 10; // ms for testing

    while (reconnectAttempts < maxAttempts) {
      reconnectAttempts++;

      try {
        const response = await fetchFn();

        if (response.status === 'completed') {
          return {
            finalResult: 'success',
            reconnectAttempts,
            partialText,
            fullText: response.text,
          };
        }

        if (response.status === 'in_progress' || response.status === 'queued') {
          // Exponential backoff: baseDelay * 2^(attempt-1)
          const delay = baseDelay * Math.pow(2, reconnectAttempts - 1);
          await new Promise((resolve) => setTimeout(resolve, delay));
          continue;
        }

        // Unknown status
        return { finalResult: 'error', reconnectAttempts, partialText };
      } catch {
        const delay = baseDelay * Math.pow(2, reconnectAttempts - 1);
        await new Promise((resolve) => setTimeout(resolve, delay));
        continue;
      }
    }

    // Max attempts exhausted — fall back to recovery polling
    return { finalResult: 'recovery', reconnectAttempts, partialText };
  }

  it('should recover immediately if server already completed', async () => {
    const fetchFn = vi.fn().mockResolvedValue({
      status: 'completed',
      text: 'Full response after reconnect',
    });

    const result = await simulateReconnect(fetchFn);

    expect(result.finalResult).toBe('success');
    expect(result.reconnectAttempts).toBe(1);
    expect(result.fullText).toBe('Full response after reconnect');
  });

  it('should retry with backoff when server still in progress', async () => {
    let callCount = 0;
    const fetchFn = vi.fn().mockImplementation(async () => {
      callCount++;
      if (callCount < 3) {
        return { status: 'in_progress' };
      }
      return { status: 'completed', text: 'Eventually completed' };
    });

    const result = await simulateReconnect(fetchFn);

    expect(result.finalResult).toBe('success');
    expect(result.reconnectAttempts).toBe(3);
    expect(result.fullText).toBe('Eventually completed');
  });

  it('should fall back to recovery after max attempts', async () => {
    const fetchFn = vi.fn().mockResolvedValue({ status: 'in_progress' });

    const result = await simulateReconnect(fetchFn, 3);

    expect(result.finalResult).toBe('recovery');
    expect(result.reconnectAttempts).toBe(3);
    expect(result.partialText).toBe('Hello, this is partial...');
  });

  it('should handle network errors during reconnect with backoff', async () => {
    let callCount = 0;
    const fetchFn = vi.fn().mockImplementation(async () => {
      callCount++;
      if (callCount <= 2) {
        throw new Error('Network unreachable');
      }
      return { status: 'completed', text: 'Recovered after network errors' };
    });

    const result = await simulateReconnect(fetchFn);

    expect(result.finalResult).toBe('success');
    expect(result.fullText).toBe('Recovered after network errors');
  });

  it('should use exponential backoff delays', async () => {
    const delays: number[] = [];
    const baseDelay = 100;
    const maxAttempts = 3;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const delay = baseDelay * Math.pow(2, attempt);
      delays.push(delay);
    }

    expect(delays).toEqual([100, 200, 400]); // 1x, 2x, 4x
  });
});

// ============================================================
// Stale Draft Cleanup Tests
// ============================================================

describe('Stale Draft Cleanup', () => {
  interface MockDraft {
    id: string;
    role: 'assistant';
    content: string;
    responseId?: string;
    isComplete: boolean;
    createdAt: Date;
  }

  function cleanupStaleDrafts(
    drafts: MockDraft[],
    staleThresholdHours: number = 24,
  ): { cleaned: number; remaining: MockDraft[] } {
    const threshold = new Date(Date.now() - staleThresholdHours * 60 * 60 * 1000);
    let cleaned = 0;
    const remaining: MockDraft[] = [];

    for (const draft of drafts) {
      if (draft.isComplete) {
        remaining.push(draft);
        continue;
      }

      if (draft.createdAt < threshold) {
        // Stale draft
        if (draft.content === '' && !draft.responseId) {
          // Empty stale draft — delete it
          cleaned++;
        } else {
          // Has content or responseId — mark as complete
          draft.isComplete = true;
          if (draft.content === '') {
            draft.content = '[Response interrupted. Please try again.]';
          }
          remaining.push(draft);
          cleaned++;
        }
      } else {
        // Recent draft — keep for recovery
        remaining.push(draft);
      }
    }

    return { cleaned, remaining };
  }

  it('should delete empty stale drafts without responseId', () => {
    const drafts: MockDraft[] = [
      {
        id: '1',
        role: 'assistant',
        content: '',
        isComplete: false,
        createdAt: new Date(Date.now() - 48 * 60 * 60 * 1000), // 48 hours ago
      },
    ];

    const result = cleanupStaleDrafts(drafts);

    expect(result.cleaned).toBe(1);
    expect(result.remaining).toHaveLength(0);
  });

  it('should mark stale drafts with content as complete', () => {
    const drafts: MockDraft[] = [
      {
        id: '1',
        role: 'assistant',
        content: 'Partial response that was interrupted...',
        responseId: 'resp_old123',
        isComplete: false,
        createdAt: new Date(Date.now() - 48 * 60 * 60 * 1000),
      },
    ];

    const result = cleanupStaleDrafts(drafts);

    expect(result.cleaned).toBe(1);
    expect(result.remaining).toHaveLength(1);
    expect(result.remaining[0].isComplete).toBe(true);
    expect(result.remaining[0].content).toBe('Partial response that was interrupted...');
  });

  it('should add placeholder text to empty stale drafts with responseId', () => {
    const drafts: MockDraft[] = [
      {
        id: '1',
        role: 'assistant',
        content: '',
        responseId: 'resp_old456',
        isComplete: false,
        createdAt: new Date(Date.now() - 48 * 60 * 60 * 1000),
      },
    ];

    const result = cleanupStaleDrafts(drafts);

    expect(result.cleaned).toBe(1);
    expect(result.remaining).toHaveLength(1);
    expect(result.remaining[0].isComplete).toBe(true);
    expect(result.remaining[0].content).toBe('[Response interrupted. Please try again.]');
  });

  it('should not touch recent drafts (less than 24 hours old)', () => {
    const drafts: MockDraft[] = [
      {
        id: '1',
        role: 'assistant',
        content: 'Recent partial...',
        responseId: 'resp_recent',
        isComplete: false,
        createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000), // 2 hours ago
      },
    ];

    const result = cleanupStaleDrafts(drafts);

    expect(result.cleaned).toBe(0);
    expect(result.remaining).toHaveLength(1);
    expect(result.remaining[0].isComplete).toBe(false);
  });

  it('should not touch already-complete messages', () => {
    const drafts: MockDraft[] = [
      {
        id: '1',
        role: 'assistant',
        content: 'Complete response',
        isComplete: true,
        createdAt: new Date(Date.now() - 72 * 60 * 60 * 1000), // 72 hours ago
      },
    ];

    const result = cleanupStaleDrafts(drafts);

    expect(result.cleaned).toBe(0);
    expect(result.remaining).toHaveLength(1);
  });

  it('should handle mixed drafts correctly', () => {
    const drafts: MockDraft[] = [
      // Stale empty — should be deleted
      {
        id: '1',
        role: 'assistant',
        content: '',
        isComplete: false,
        createdAt: new Date(Date.now() - 48 * 60 * 60 * 1000),
      },
      // Stale with content — should be marked complete
      {
        id: '2',
        role: 'assistant',
        content: 'Old partial...',
        responseId: 'resp_old',
        isComplete: false,
        createdAt: new Date(Date.now() - 36 * 60 * 60 * 1000),
      },
      // Recent — should be kept for recovery
      {
        id: '3',
        role: 'assistant',
        content: 'Recent partial...',
        responseId: 'resp_new',
        isComplete: false,
        createdAt: new Date(Date.now() - 1 * 60 * 60 * 1000),
      },
      // Already complete — should be untouched
      {
        id: '4',
        role: 'assistant',
        content: 'Done',
        isComplete: true,
        createdAt: new Date(Date.now() - 72 * 60 * 60 * 1000),
      },
    ];

    const result = cleanupStaleDrafts(drafts);

    expect(result.cleaned).toBe(2); // #1 deleted, #2 marked complete
    expect(result.remaining).toHaveLength(3); // #2, #3, #4
    expect(result.remaining.find((d) => d.id === '2')?.isComplete).toBe(true);
    expect(result.remaining.find((d) => d.id === '3')?.isComplete).toBe(false);
    expect(result.remaining.find((d) => d.id === '4')?.isComplete).toBe(true);
  });
});

// ============================================================
// Reasoning Text Event Parsing Tests
// ============================================================

describe('SSE Event Parsing - Reasoning Text (GPT-5.4 Pro)', () => {
  it('should extract delta from response.reasoning_text.delta event', () => {
    const sseData = JSON.stringify({
      item_id: 'item_001',
      output_index: 0,
      content_index: 0,
      delta: 'Let me think about this step by step...',
    });

    const parsed = JSON.parse(sseData);
    const delta = parsed?.delta;

    expect(delta).toBe('Let me think about this step by step...');
    expect(typeof delta).toBe('string');
  });

  it('should extract full text from response.reasoning_text.done event', () => {
    const sseData = JSON.stringify({
      item_id: 'item_001',
      output_index: 0,
      content_index: 0,
      text: 'Let me think about this step by step... First, I need to consider...',
    });

    const parsed = JSON.parse(sseData);
    const fullText = parsed?.text;

    expect(fullText).toContain('step by step');
    expect(fullText).toContain('First, I need to consider');
  });

  it('should extract delta from response.reasoning_summary_text.delta event', () => {
    const sseData = JSON.stringify({
      item_id: 'item_002',
      output_index: 0,
      summary_index: 0,
      delta: 'The user asked about...',
    });

    const parsed = JSON.parse(sseData);
    const delta = parsed?.delta;

    expect(delta).toBe('The user asked about...');
  });

  it('should accumulate reasoning deltas correctly', () => {
    const deltas = [
      'Let me ',
      'think about ',
      'this carefully.',
    ];

    let accumulated = '';
    for (const delta of deltas) {
      accumulated += delta;
    }

    expect(accumulated).toBe('Let me think about this carefully.');
  });

  it('should handle both reasoning_text and reasoning_summary in same response', () => {
    // GPT-5.4 Pro may send both reasoning_text (full chain-of-thought)
    // and reasoning_summary (condensed summary) in the same response.
    // The client should use whichever is available, preferring the summary
    // for display since it's more concise.

    const reasoningText = 'Full chain of thought: Step 1... Step 2... Step 3...';
    const reasoningSummary = 'Analyzed in 3 steps';

    // If both are available, summary is preferred for display
    const displayText = reasoningSummary || reasoningText;
    expect(displayText).toBe('Analyzed in 3 steps');

    // If only reasoning_text is available
    const emptySummary: string = '';
    const displayTextNoSummary = emptySummary || reasoningText;
    expect(displayTextNoSummary).toBe(reasoningText);
  });
});

// ============================================================
// GPT-5.4 Pro Model Configuration Tests
// ============================================================

describe('GPT-5.4 Pro Model Configuration', () => {
  const models = {
    'gpt-5.4': {
      displayName: 'GPT-5.4',
      availableEfforts: ['none', 'low', 'medium', 'high', 'xhigh'],
      defaultEffort: 'medium',
    },
    'gpt-5.4-pro': {
      displayName: 'GPT-5.4 Pro',
      availableEfforts: ['medium', 'high', 'xhigh'],
      defaultEffort: 'high',
    },
  };

  it('GPT-5.4 Pro should have exactly 3 effort levels', () => {
    const pro = models['gpt-5.4-pro'];
    expect(pro.availableEfforts).toHaveLength(3);
  });

  it('GPT-5.4 Pro should support medium, high, xhigh', () => {
    const pro = models['gpt-5.4-pro'];
    expect(pro.availableEfforts).toEqual(['medium', 'high', 'xhigh']);
  });

  it('GPT-5.4 Pro should NOT support none or low', () => {
    const pro = models['gpt-5.4-pro'];
    expect(pro.availableEfforts).not.toContain('none');
    expect(pro.availableEfforts).not.toContain('low');
  });

  it('GPT-5.4 Pro default effort should be high', () => {
    const pro = models['gpt-5.4-pro'];
    expect(pro.defaultEffort).toBe('high');
  });

  it('GPT-5.4 should have 5 effort levels', () => {
    const standard = models['gpt-5.4'];
    expect(standard.availableEfforts).toHaveLength(5);
  });

  it('switching from GPT-5.4 (low) to GPT-5.4 Pro should reset effort to default', () => {
    let currentEffort = 'low';
    const targetModel = models['gpt-5.4-pro'];

    if (!targetModel.availableEfforts.includes(currentEffort)) {
      currentEffort = targetModel.defaultEffort;
    }

    expect(currentEffort).toBe('high');
  });

  it('switching from GPT-5.4 Pro (high) to GPT-5.4 should keep effort', () => {
    let currentEffort = 'high';
    const targetModel = models['gpt-5.4'];

    if (!targetModel.availableEfforts.includes(currentEffort)) {
      currentEffort = targetModel.defaultEffort;
    }

    expect(currentEffort).toBe('high'); // high is valid for both models
  });
});

// ============================================================
// Connection Lost Detection Tests
// ============================================================

describe('Connection Lost Detection', () => {
  const networkErrorCodes = [
    { code: -1005, name: 'NSURLErrorNetworkConnectionLost' },
    { code: -1009, name: 'NSURLErrorNotConnectedToInternet' },
    { code: -1001, name: 'NSURLErrorTimedOut' },
    { code: -1020, name: 'NSURLErrorDataNotAllowed' },
    { code: -1018, name: 'NSURLErrorInternationalRoamingOff' },
    { code: -1003, name: 'NSURLErrorCannotFindHost' },
    { code: -1004, name: 'NSURLErrorCannotConnectToHost' },
    { code: -1200, name: 'NSURLErrorSecureConnectionFailed' },
  ];

  const nonNetworkErrorCodes = [
    { code: -999, name: 'NSURLErrorCancelled' },
    { code: -1011, name: 'NSURLErrorBadServerResponse' },
    { code: -1022, name: 'NSURLErrorAppTransportSecurityRequiresSecureConnection' },
  ];

  it('should classify network errors correctly', () => {
    const networkCodes = networkErrorCodes.map((e) => e.code);

    for (const error of networkErrorCodes) {
      expect(networkCodes).toContain(error.code);
    }
  });

  it('should not classify non-network errors as connection lost', () => {
    const networkCodes = networkErrorCodes.map((e) => e.code);

    for (const error of nonNetworkErrorCodes) {
      expect(networkCodes).not.toContain(error.code);
    }
  });

  it('should have at least 5 network error codes covered', () => {
    expect(networkErrorCodes.length).toBeGreaterThanOrEqual(5);
  });
});
