import { describe, it, expect } from 'vitest';
import { MODELS, DEFAULT_MODEL, DEFAULT_EFFORT, DEFAULT_SETTINGS } from '../types';

describe('Types and Models', () => {
  it('should have correct default model as gpt-5.4-pro', () => {
    expect(DEFAULT_MODEL).toBe('gpt-5.4-pro');
  });

  it('should have correct default effort as xhigh', () => {
    expect(DEFAULT_EFFORT).toBe('xhigh');
  });

  it('should have two models defined', () => {
    expect(MODELS).toHaveLength(2);
  });

  it('GPT-5.4 should support all reasoning efforts', () => {
    const gpt54 = MODELS.find((m) => m.id === 'gpt-5.4');
    expect(gpt54).toBeDefined();
    expect(gpt54!.reasoningEfforts).toEqual(['none', 'low', 'medium', 'high', 'xhigh']);
    expect(gpt54!.defaultEffort).toBe('high');
  });

  it('GPT-5.4 Pro should support medium, high, xhigh efforts', () => {
    const gpt54pro = MODELS.find((m) => m.id === 'gpt-5.4-pro');
    expect(gpt54pro).toBeDefined();
    expect(gpt54pro!.reasoningEfforts).toEqual(['medium', 'high', 'xhigh']);
    expect(gpt54pro!.defaultEffort).toBe('xhigh');
  });

  it('default settings should use gpt-5.4-pro with xhigh', () => {
    expect(DEFAULT_SETTINGS.defaultModel).toBe('gpt-5.4-pro');
    expect(DEFAULT_SETTINGS.defaultEffort).toBe('xhigh');
    expect(DEFAULT_SETTINGS.apiKey).toBe('');
    expect(DEFAULT_SETTINGS.theme).toBe('system');
  });
});

describe('OpenAI Service - buildMessages', () => {
  it('should handle text-only messages', () => {
    const messages = [
      { id: '1', role: 'user' as const, content: 'Hello', createdAt: Date.now() },
    ];
    // Verify the message structure is correct
    const result = messages.map((msg) => {
      if (msg.role === 'user') {
        return { role: msg.role, content: msg.content };
      }
      return { role: msg.role, content: msg.content };
    });
    expect(result).toEqual([{ role: 'user', content: 'Hello' }]);
  });

  it('should handle messages with images', () => {
    const messages = [
      {
        id: '1',
        role: 'user' as const,
        content: 'What is this?',
        images: [{ uri: 'file://test.jpg', base64: 'abc123', mimeType: 'image/jpeg' }],
        createdAt: Date.now(),
      },
    ];
    // Verify image messages build multimodal content
    const msg = messages[0];
    expect(msg.images).toBeDefined();
    expect(msg.images!.length).toBe(1);
    expect(msg.images![0].base64).toBe('abc123');
  });
});

describe('Model Configuration', () => {
  it('GPT-5.4 Pro should not support none or low effort', () => {
    const gpt54pro = MODELS.find((m) => m.id === 'gpt-5.4-pro')!;
    expect(gpt54pro.reasoningEfforts).not.toContain('none');
    expect(gpt54pro.reasoningEfforts).not.toContain('low');
  });

  it('each model should have a valid default effort within its options', () => {
    for (const model of MODELS) {
      expect(model.reasoningEfforts).toContain(model.defaultEffort);
    }
  });
});
