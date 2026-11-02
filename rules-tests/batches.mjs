// The cases go to the Rules API a batch at a time: it refuses a request with
// a couple of hundred or more (250 was too many in November 2026). Shared by
// payload.mjs and report.mjs.
export const BATCH_SIZE = 100;

/** [cases] in batches of at most BATCH_SIZE, in order. */
export const batchesOf = (cases) =>
  Array.from({length: Math.ceil(cases.length / BATCH_SIZE)}, (_, i) => cases.slice(i * BATCH_SIZE, (i + 1) * BATCH_SIZE));
