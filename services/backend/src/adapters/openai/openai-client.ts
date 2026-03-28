export interface OpenAiClient {
  readonly provider: 'openai';
  authorizationHeader(apiKey: string): string;
  validateApiKey(apiKey: string): Promise<{
    checkedAt: string;
    lastErrorSummary: string | null;
    state: 'invalid' | 'valid';
  }>;
}

export const createOpenAiClient = (): OpenAiClient => {
  return {
    provider: 'openai',
    authorizationHeader: (apiKey: string): string => {
      return `Bearer ${apiKey}`;
    },
    validateApiKey: async (apiKey: string) => {
      const checkedAt = new Date().toISOString();
      const response = await fetch('https://api.openai.com/v1/models', {
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
        method: 'GET',
      });

      if (response.ok) {
        return {
          checkedAt,
          lastErrorSummary: null,
          state: 'valid' as const,
        };
      }

      const responseText = await response.text();
      return {
        checkedAt,
        lastErrorSummary:
          responseText.length > 0 ? responseText : `openai_status_${response.status}`,
        state: 'invalid' as const,
      };
    },
  };
};

export const validateOpenAiApiKey = async (apiKey: string) => {
  return createOpenAiClient().validateApiKey(apiKey);
};
