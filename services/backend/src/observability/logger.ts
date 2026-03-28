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
