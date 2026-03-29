export interface LogFields {
  [key: string]: string | number | boolean | null | undefined;
}

export function logInfo(message: string, fields: LogFields = {}): void {
  console.info(
    JSON.stringify({
      level: 'info',
      message,
      ...fields,
    }),
  );
}

export function logError(message: string, fields: LogFields = {}): void {
  console.error(
    JSON.stringify({
      level: 'error',
      message,
      ...fields,
    }),
  );
}

/**
 * Strips sensitive patterns from log values to prevent credential leakage.
 * Truncates to 200 characters and masks API keys and bearer tokens.
 */
export function sanitizeLogValue(value: string): string {
  let result = value.length > 200 ? `${value.slice(0, 200)}...` : value;
  result = result.replace(/sk-[a-zA-Z0-9]{10,}/g, 'sk-***');
  result = result.replace(/Bearer\s+[^\s]+/gi, 'Bearer ***');
  return result;
}
