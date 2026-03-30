export interface StreamDeltaDispatcher<Delta> {
  enqueue(delta: Delta): void;
  flush(): Promise<void>;
}

export const createStreamDeltaDispatcher = <Delta>(input: {
  readonly dispatch: (delta: Delta) => Promise<void>;
  readonly onError: (error: unknown, delta: Delta) => void;
}): StreamDeltaDispatcher<Delta> => {
  let tail: Promise<void> = Promise.resolve();

  return {
    enqueue(delta) {
      tail = tail.then(async () => {
        try {
          await input.dispatch(delta);
        } catch (error) {
          input.onError(error, delta);
        }
      });
    },
    async flush() {
      await tail;
    },
  };
};
