// The Rules API test request for one rules file: the repository's
// firestore.rules or storage.rules and every case in <kind>-cases.mjs.
// Node only, no packages. scripts/test-rules.sh runs it.
//
//   node rules-tests/payload.mjs <firestore|storage> <out.json>
import {readFileSync, writeFileSync} from 'node:fs';

const [kind, outPath] = process.argv.slice(2);
if (!['firestore', 'storage'].includes(kind) || !outPath) {
  console.error('Usage: node rules-tests/payload.mjs <firestore|storage> <out.json>');
  process.exit(2);
}

const {cases} = await import(new URL(`./${kind}-cases.mjs`, import.meta.url));
const rules = readFileSync(new URL(`../${kind}.rules`, import.meta.url), 'utf8');
writeFileSync(outPath, JSON.stringify({
  source: {files: [{name: `${kind}.rules`, content: rules}]},
  testSuite: {testCases: cases.map(([expectation, _name, testCase]) => ({expectation, ...testCase}))},
}));
