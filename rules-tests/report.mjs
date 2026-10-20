// How one Rules API test run went: "firestore.rules: 160 of 160 cases
// pass", then each case that didn't, with the API's debug messages. Exits 1
// if any case failed, the rules didn't compile or the API refused the
// request. Node only, no packages. scripts/test-rules.sh runs it.
//
//   node rules-tests/report.mjs <firestore|storage> <result.json> <HTTP status>
import {readFileSync} from 'node:fs';

const [kind, resultPath, status] = process.argv.slice(2);
if (!['firestore', 'storage'].includes(kind) || !resultPath) {
  console.error('Usage: node rules-tests/report.mjs <firestore|storage> <result.json> <HTTP status>');
  process.exit(2);
}

const {cases} = await import(new URL(`./${kind}-cases.mjs`, import.meta.url));
if (status === '000') {
  console.error(`${kind}.rules: couldn’t reach the Rules API. Check the connection and run it again.`);
  process.exit(1);
}
let result;
try {
  result = JSON.parse(readFileSync(resultPath, 'utf8'));
} catch {
  result = {};
}
if (result.error || (status && !status.startsWith('2'))) {
  // Error bodies carry only a code and a message.
  const {code, status: reason, message} = result.error ?? {};
  console.error(`${kind}.rules: the Rules API refused the test (HTTP ${status ?? code}${reason ? `, ${reason}` : ''}): ` +
    `${message ?? 'no message'}`);
  if (status === '401' || status === '403') console.error('Run gcloud auth login with an account on the project, then try again.');
  process.exit(1);
}

const issues = (result.issues ?? []).filter((issue) => issue.severity === 'ERROR');
for (const {description, sourcePosition: at = {}} of issues) {
  console.error(`${kind}.rules:${at.line ?? '?'}:${at.column ?? '?'}: ${description}`);
}
const results = result.testResults ?? [];
if (issues.length || results.length !== cases.length) {
  console.error(`${kind}.rules: ${issues.length ? 'doesn’t compile' : `${results.length} results for ${cases.length} cases`}.`);
  process.exit(1);
}

const failed = results.flatMap((r, i) => (r.state === 'SUCCESS' ? [] : [i]));
console.log(`${kind}.rules: ${results.length - failed.length} of ${results.length} cases pass`);
for (const i of failed) {
  const [expectation, name] = cases[i];
  console.log(`  FAIL ${expectation} ${name}  ${(results[i].debugMessages ?? []).join(' | ')}`);
}
process.exit(failed.length ? 1 : 0);
