// How one Rules API test run went, over every batch: "firestore.rules: 160 of
// 160 cases pass", then each case that didn't, with the API's debug messages.
// Exits 1 if any case failed, the rules didn't compile or the API refused a
// request. Node only, no packages. scripts/test-rules.sh runs it.
//
//   node rules-tests/report.mjs <firestore|storage> <prefix>
//
// reads each batch's <prefix>-<i>-result.json and its HTTP status,
// <prefix>-<i>-status (batches.mjs; payload.mjs wrote <prefix>-<i>.json).
import {readFileSync} from 'node:fs';
import {batchesOf} from './batches.mjs';

const [kind, prefix] = process.argv.slice(2);
if (!['firestore', 'storage'].includes(kind) || !prefix) {
  console.error('Usage: node rules-tests/report.mjs <firestore|storage> <prefix>');
  process.exit(2);
}

const {cases} = await import(new URL(`./${kind}-cases.mjs`, import.meta.url));
const readOr = (path, fallback) => {
  try {
    return readFileSync(path, 'utf8');
  } catch {
    return fallback;
  }
};

const failed = [];
let first = 0;
for (const [i, batch] of batchesOf(cases).entries()) {
  const status = readOr(`${prefix}-${i}-status`, '000').trim();
  if (status === '000') {
    console.error(`${kind}.rules: couldn’t reach the Rules API. Check the connection and run it again.`);
    process.exit(1);
  }
  let result;
  try {
    result = JSON.parse(readOr(`${prefix}-${i}-result.json`, '{}'));
  } catch {
    result = {};
  }
  if (result.error || !status.startsWith('2')) {
    // Error bodies carry only a code and a message.
    const {code, status: reason, message} = result.error ?? {};
    console.error(`${kind}.rules: the Rules API refused the test (HTTP ${status || code}${reason ? `, ${reason}` : ''}): ` +
      `${message ?? 'no message'}`);
    if (status === '401' || status === '403') console.error('Run gcloud auth login with an account on the project, then try again.');
    process.exit(1);
  }
  // Every batch compiles the same rules, so the first reports any error.
  const issues = (result.issues ?? []).filter((issue) => issue.severity === 'ERROR');
  for (const {description, sourcePosition: at = {}} of issues) {
    console.error(`${kind}.rules:${at.line ?? '?'}:${at.column ?? '?'}: ${description}`);
  }
  const results = result.testResults ?? [];
  if (issues.length || results.length !== batch.length) {
    console.error(`${kind}.rules: ${issues.length ? 'doesn’t compile' : `${results.length} results for ${batch.length} cases`}.`);
    process.exit(1);
  }
  results.forEach((r, j) => {
    if (r.state !== 'SUCCESS') failed.push({index: first + j, debugMessages: r.debugMessages ?? []});
  });
  first += batch.length;
}

console.log(`${kind}.rules: ${cases.length - failed.length} of ${cases.length} cases pass`);
for (const {index, debugMessages} of failed) {
  const [expectation, name] = cases[index];
  console.log(`  FAIL ${expectation} ${name}  ${debugMessages.join(' | ')}`);
}
process.exit(failed.length ? 1 : 0);
