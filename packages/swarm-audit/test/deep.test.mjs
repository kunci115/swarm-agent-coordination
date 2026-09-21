import { test } from 'node:test';
import assert from 'node:assert/strict';
import { migrationOverlaps, supersedeChains, mergeSignals } from '../src/deep.mjs';
import { loadCodebook, audit } from '../src/classify.mjs';
import { referencedNumbers } from '../src/github.mjs';

const pr = (number, files, opened, closed, body = '') => ({
  number, files, body,
  created_at: opened,
  merged_at: closed,
});

test('two migrations open at the same time flag each other', () => {
  const hits = migrationOverlaps([
    pr(1, ['app/db/migrations/versions/0003_a.py'], '2026-08-01T10:00:00Z', '2026-08-01T16:00:00Z'),
    pr(2, ['app/db/migrations/versions/0003_b.py'], '2026-08-01T12:00:00Z', '2026-08-01T18:00:00Z'),
  ]);
  assert.deepEqual([...hits.keys()].sort(), [1, 2]);
  assert.equal(hits.get(1)[0].id, 'shared_resources');
  assert.equal(hits.get(1)[0].kind, 'structural');
  assert.match(hits.get(1)[0].evidence, /#2/);
});

test('migrations that never overlap are not flagged', () => {
  const hits = migrationOverlaps([
    pr(1, ['migrations/0003_a.py'], '2026-08-01T10:00:00Z', '2026-08-01T11:00:00Z'),
    pr(2, ['migrations/0004_b.py'], '2026-08-01T12:00:00Z', '2026-08-01T13:00:00Z'),
  ]);
  assert.equal(hits.size, 0);
});

test('overlapping pull requests that touch no migration are not flagged', () => {
  const hits = migrationOverlaps([
    pr(1, ['app/api/routes.py'], '2026-08-01T10:00:00Z', '2026-08-01T16:00:00Z'),
    pr(2, ['app/ui/page.html'], '2026-08-01T12:00:00Z', '2026-08-01T18:00:00Z'),
  ]);
  assert.equal(hits.size, 0);
});

test('a reference to work closed without merging is a supersede chain', () => {
  const prs = [{ number: 20, referenced_prs: [11], body: 'Carries the rest of #11.' }];
  const states = new Map([[11, { isPr: true, merged: false, closed: true }]]);
  const hits = supersedeChains(prs, states);
  assert.equal(hits.get(20)[0].id, 'rework_supersede');
  assert.match(hits.get(20)[0].evidence, /closed without merging/);
});

test('references to issues and to merged work are left alone', () => {
  const prs = [{ number: 20, referenced_prs: [11, 12, 13] }];
  const states = new Map([
    [11, { isPr: false }],                                   // an issue
    [12, { isPr: true, merged: true, closed: true }],        // landed
    [13, { isPr: true, merged: false, closed: false }],      // still open
  ]);
  assert.equal(supersedeChains(prs, states).size, 0);
});

test('referencedNumbers reads a body and skips self-reference', () => {
  assert.deepEqual(referencedNumbers({ number: 7, body: 'Closes #3, follows #5, not #7.' }), [3, 5]);
});

test('structural hits survive a confidence floor that filters text', () => {
  // A pull request whose prose says nothing. Only the measurement speaks, and a
  // measurement is not a reading of a word, so the floor must not filter it.
  const prs = [{ number: 1, title: 'Add a column', body: 'Nothing unusual here.' }];
  const structural = new Map([[1, [{ id: 'shared_resources', confidence: 'high', evidence: 'x', kind: 'structural' }]]]);
  const result = audit(prs, loadCodebook(), { minConfidence: 'high', structural });
  assert.equal(result.incidentPrs, 1);
  assert.equal(result.structuralOnlyPrs, 1);
});

test('mergeSignals keeps hits from every source', () => {
  const a = new Map([[1, [{ id: 'x' }]]]);
  const b = new Map([[1, [{ id: 'y' }]], [2, [{ id: 'z' }]]]);
  const merged = mergeSignals(a, b);
  assert.equal(merged.get(1).length, 2);
  assert.equal(merged.get(2).length, 1);
});
