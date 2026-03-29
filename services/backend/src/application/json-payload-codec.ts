import type { ZodType } from 'zod';

export const parseOptionalJSONPayload = <Payload>(
  value: string | null | undefined,
  schema: ZodType<Payload>,
): Payload | undefined => {
  if (!value) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(value) as unknown;
    const result = schema.safeParse(parsed);
    return result.success ? result.data : undefined;
  } catch {
    return undefined;
  }
};
