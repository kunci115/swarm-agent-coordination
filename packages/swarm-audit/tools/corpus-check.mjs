#!/usr/bin/env node
// corpus-check.mjs — score the codebook against the case study's labelled set.
//
//   node packages/swarm-audit/tools/corpus-check.mjs [--export ../../export]
//
// This is the acceptance test for roadmap task A1, and it cannot live in
// test/ because it needs the private corpus. It exits 0 and says so when the
// corpus is absent, so a contributor without it is never blocked.
//
// What it measures: the audit reads pull request prose, which is the same
// thing the original classification read. So the honest target is not "produces
// the published counts" — those counts came from one particular keyword list —
// but "finds the same pull requests a second, independently written rule set
// finds". analysis/classify.py recovered 80 of the 85 labelled pull requests.
// That is the bar.
//
// Precision against the labelled set is reported but is not a pass criterion.
// The labelled set is a comparison set, not ground truth: a pull request this
// codebook flags and the original missed may well be a pull request the
// original missed.

import { readFileSync, existsSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { loadCodebook, audit } from '../src/classify.mjs';

// codebook id -> label id in existing_labels.csv
const ALIAS = {
  rework_supersede: 'revert_rework',
  shared_resources: 'shared_resource_db',
  seam_defect: 'seam_explicit',
  cross_lane_dependency: 'cross_lane_dependency',
  runner_queue: 'shared_resource_runner',
  textual_conflict: 'conflict_merge',
};

const { values } = parseArgs({
  options: {
    export: { type: 'string', default: 'export' },
    'min-confidence': { type: 'string', default: 'medium' },
    codebook: { type: 'string' },
  },
});

const dir = values.export;
if (!existsSync(`${dir}/pull_requests.jsonl`) || !existsSync(`${dir}/existing_labels.csv`)) {
  console.log(`no corpus at ${dir}/ — codebook scoring skipped.`);
  console.log('See analysis/README.md: the corpus is not published with this repo.');
  process.exit(0);
}

const prs = readFileSync(`${dir}/pull_requests.jsonl`, 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l))
  .filter((p) => p.state === 'merged' && p.base_ref === 'dev')
  .map((p) => ({ number: p.number, title: p.title ?? '', body: p.body ?? '', html_url: '' }));

const truth = new Map();
for (const line of readFileSync(`${dir}/existing_labels.csv`, 'utf8').split('\n').slice(1)) {
  if (!line.trim()) continue;
  const [num, , cats] = line.split(',', 2).concat(line.slice(line.indexOf('"')).replace(/"/g, ''));
  truth.set(Number(num), new Set(cats.split(',').map((c) => c.trim()).filter(Boolean)));
}

const codebook = loadCodebook(values.codebook);
const result = audit(prs, codebook, { minConfidence: values['min-confidence'] });
const predicted = new Map(result.flagged.map((f) => [f.number, new Set(f.hits.map((h) => ALIAS[h.id] ?? h.id))]));

console.log(`codebook ${codebook.version} · ${prs.length} pull requests · `
  + `min-confidence=${values['min-confidence']}`);
console.log(`flagged ${result.incidentPrs} · labelled set flagged ${truth.size}\n`);

const head = 'category'.padEnd(24) + 'pub'.padStart(5) + 'new'.padStart(5)
  + 'tp'.padStart(5) + 'fp'.padStart(5) + 'fn'.padStart(5)
  + 'prec'.padStart(7) + 'rec'.padStart(7);
console.log(head);
console.log('-'.repeat(head.length));

for (const cat of codebook.categories) {
  const key = ALIAS[cat.id] ?? cat.id;
  let tp = 0, fp = 0, fn = 0, pub = 0;
  for (const pr of prs) {
    const t = truth.get(pr.number)?.has(key) ?? false;
    const p = predicted.get(pr.number)?.has(key) ?? false;
    if (t) pub += 1;
    if (p && t) tp += 1; else if (p) fp += 1; else if (t) fn += 1;
  }
  const prec = tp + fp ? tp / (tp + fp) : 0;
  const rec = tp + fn ? tp / (tp + fn) : 0;
  const count = result.categories.find((c) => c.id === cat.id)?.count ?? 0;
  console.log(cat.id.padEnd(24) + String(pub).padStart(5) + String(count).padStart(5)
    + String(tp).padStart(5) + String(fp).padStart(5) + String(fn).padStart(5)
    + prec.toFixed(2).padStart(7) + rec.toFixed(2).padStart(7));
}

const found = [...truth.keys()].filter((n) => predicted.has(n));
const missed = [...truth.keys()].filter((n) => !predicted.has(n));
const TARGET = 80;

console.log(`\nlabelled pull requests found again : ${found.length} of ${truth.size}`);
console.log(`flagged only by this codebook      : ${[...predicted.keys()].filter((n) => !truth.has(n)).length}`);
if (missed.length) console.log(`missed                             : ${missed.slice(0, 12).join(', ')}`);

if (found.length >= TARGET) {
  console.log(`\nPASS: ${found.length} >= ${TARGET}, the bar analysis/classify.py set.`);
  process.exit(0);
}
console.log(`\nFAIL: ${found.length} < ${TARGET}. The codebook misses pull requests a second rule set found.`);
process.exit(1);
