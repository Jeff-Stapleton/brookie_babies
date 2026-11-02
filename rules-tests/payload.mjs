// The Rules API test requests for one rules file: the repository's
// firestore.rules or storage.rules and the cases in <kind>-cases.mjs, a batch
// at a time (batches.mjs). Node only, no packages. scripts/test-rules.sh runs
// it.
//
//   node rules-tests/payload.mjs <firestore|storage> <out-prefix>
//
// writes <out-prefix>-0.json, <out-prefix>-1.json, ... and prints how many.
import {readFileSync, writeFileSync} from 'node:fs';
import {batchesOf} from './batches.mjs';

const [kind, outPrefix] = process.argv.slice(2);
if (!['firestore', 'storage'].includes(kind) || !outPrefix) {
  console.error('Usage: node rules-tests/payload.mjs <firestore|storage> <out-prefix>');
  process.exit(2);
}

const {cases} = await import(new URL(`./${kind}-cases.mjs`, import.meta.url));
const rules = readFileSync(new URL(`../${kind}.rules`, import.meta.url), 'utf8');
const batches = batchesOf(cases);
batches.forEach((batch, i) => writeFileSync(`${outPrefix}-${i}.json`, JSON.stringify({
  source: {files: [{name: `${kind}.rules`, content: rules}]},
  testSuite: {testCases: batch.map(([expectation, _name, testCase]) => ({expectation, ...testCase}))},
})));
console.log(batches.length);
