const DEFAULT_CORS_ALLOWED_ORIGINS: Record<string, readonly string[]> = {
  beta: [
    'https://glassgpt.com',
    'https://beta.glassgpt.com',
    'https://staging.glassgpt.com',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://localhost:5173',
    'http://127.0.0.1:5173',
  ],
  development: [
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://localhost:5173',
    'http://127.0.0.1:5173',
  ],
  production: ['https://glassgpt.com'],
  staging: [
    'https://staging.glassgpt.com',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://localhost:5173',
    'http://127.0.0.1:5173',
  ],
};

const normalizeOrigin = (value: string): string | null => {
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }

    return parsed.origin;
  } catch {
    return null;
  }
};

const parseConfiguredOrigins = (value: string | undefined): readonly string[] => {
  if (!value) {
    return [];
  }

  return value
    .split(',')
    .map((entry) => normalizeOrigin(entry.trim()))
    .filter((entry): entry is string => entry !== null);
};

export const resolveAllowedCorsOrigins = (
  env: Pick<Env, 'APP_ENV'> & Partial<Pick<Env, 'CORS_ALLOWED_ORIGINS'>>,
): readonly string[] => {
  const defaults = DEFAULT_CORS_ALLOWED_ORIGINS[env.APP_ENV] ?? [];
  const configured = parseConfiguredOrigins(env.CORS_ALLOWED_ORIGINS);
  return Array.from(new Set([...defaults, ...configured]));
};

export const resolveCorsOrigin = (
  origin: string,
  env: Pick<Env, 'APP_ENV'> & Partial<Pick<Env, 'CORS_ALLOWED_ORIGINS'>>,
): string | null => {
  const normalizedOrigin = normalizeOrigin(origin);
  if (!normalizedOrigin) {
    return null;
  }

  return resolveAllowedCorsOrigins(env).includes(normalizedOrigin) ? normalizedOrigin : null;
};
