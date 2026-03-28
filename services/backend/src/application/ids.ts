const createPrefixedId = (prefix: string): string => {
  return `${prefix}_${crypto.randomUUID()}`;
};

const CURSOR_PREFIX = 'cur_' as const;
const CURSOR_WIDTH = 20;

export const createConversationId = (): string => createPrefixedId('conv');
export const createMessageId = (): string => createPrefixedId('msg');
export const createRunId = (): string => createPrefixedId('run');
export const createRunEventId = (): string => createPrefixedId('evt');

export const formatCursorSequence = (sequence: number): string => {
  return `${CURSOR_PREFIX}${sequence.toString().padStart(CURSOR_WIDTH, '0')}`;
};

export const parseCursorSequence = (cursor: string): number => {
  if (!cursor.startsWith(CURSOR_PREFIX)) {
    throw new Error(`invalid_cursor_format:${cursor}`);
  }

  const sequence = Number.parseInt(cursor.slice(CURSOR_PREFIX.length), 10);
  if (!Number.isSafeInteger(sequence) || sequence < 1) {
    throw new Error(`invalid_cursor_sequence:${cursor}`);
  }

  return sequence;
};
