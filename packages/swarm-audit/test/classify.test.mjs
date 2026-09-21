import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCodebook, classifyPr, audit } from '../src/classify.mjs';
import { parseRepo } from '../src/github.mjs';

const codebook = loadCodebook();
const prs = JSON.parse(readFileSync(new URL('./fixtures/prs.json', import.meta.url), 'utf8'));

test('supersede reference is a high-confidence rework hit', () => {
  const hits = classifyPr(prs[1], codebook);
  assert.deepEqual(hits.find((h) => h.id === 'rework_supersede')?.confidence, 'high');
});

test('clean PRs produce no hits', () => {
  assert.equal(classifyPr(prs[6], codebook).length, 0);
  assert.equal(classifyPr(prs[8], codebook).length, 0);
});

test('weak body-only match is low confidence and filtered at medium', () => {
  const hits = classifyPr(prs[7], codebook);
  assert.equal(hits[0].confidence, 'low');
  const result = audit([prs[7]], codebook, { minConfidence: 'medium' });
  assert.equal(result.incidentPrs, 0);
});

test('audit counts categories and rate on fixture', () => {
  const r = audit(prs, codebook);
  const count = (id) => r.categories.find((c) => c.id === id).count;
  assert.equal(r.totalPrs, 10);
  assert.equal(count('rework_supersede'), 1);
  assert.equal(count('shared_resources'), 2);
  assert.equal(count('seam_defect'), 1);
  assert.equal(count('cross_lane_dependency'), 1);
  assert.equal(count('textual_conflict'), 1);
  assert.equal(r.incidentPrs, 6);
  assert.equal(r.incidentRate, 0.6);
});

test('empty repo does not divide by zero', () => {
  assert.equal(audit([], codebook).incidentRate, 0);
});

test('parseRepo accepts slug, https URL, and ssh URL', () => {
  assert.deepEqual(parseRepo('kunci115/swarm-agent-coordination'), { owner: 'kunci115', repo: 'swarm-agent-coordination' });
  assert.deepEqual(parseRepo('https://github.com/kunci115/swarm-agent-coordination/'), { owner: 'kunci115', repo: 'swarm-agent-coordination' });
  assert.deepEqual(parseRepo('git@github.com:kunci115/swarm-agent-coordination.git'), { owner: 'kunci115', repo: 'swarm-agent-coordination' });
});
