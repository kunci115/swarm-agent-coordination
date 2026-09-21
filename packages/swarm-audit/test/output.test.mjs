import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderBadge, badgeColor } from '../src/badge.mjs';
import { renderHtml } from '../src/report.mjs';
import { fetchPrs } from '../src/github.mjs';
import { readFileSync } from 'node:fs';
import { loadCodebook, audit } from '../src/classify.mjs';

test('badge shows rounded percent and threshold color', () => {
  const svg = renderBadge(0.37);
  assert.match(svg, /37%/);
  assert.equal(badgeColor(0.05), '#3B6D11');
  assert.equal(badgeColor(0.37), '#A32D2D');
});

test('report escapes PR titles', () => {
  const html = renderHtml({ incidentRate: 1, incidentPrs: 1, totalPrs: 1, codebookVersion: 'x', minConfidence: 'medium', categories: [], flagged: [{ number: 1, title: '<script>x</script>', url: 'u', hits: [] }] }, 'a/b');
  assert.ok(!html.includes('<script>x'));
});

test('fetchPrs paginates and stops on short page', async () => {
  const pages = [Array.from({ length: 100 }, (_, i) => ({ number: i, title: 't', body: null, html_url: '' })), [{ number: 999, title: 'last', body: 'b', html_url: '' }]];
  let calls = 0;
  const fake = async () => ({ ok: true, status: 200, headers: new Map(), json: async () => pages[calls++] });
  const prs = await fetchPrs({ owner: 'a', repo: 'b', fetchImpl: fake });
  assert.equal(prs.length, 101);
  assert.equal(calls, 2);
});

test('fetchPrs reports rate limit clearly', async () => {
  const fake = async () => ({ ok: false, status: 403, headers: new Map([['x-ratelimit-reset', '0'], ['x-ratelimit-remaining', '0']]), json: async () => ({}) });
  await assert.rejects(fetchPrs({ owner: 'a', repo: 'b', fetchImpl: fake }), /rate limit/);
});

test('fetchPrs distinguishes plain 403 from rate limit', async () => {
  const fake = async () => ({ ok: false, status: 403, headers: new Map(), json: async () => ({}) });
  await assert.rejects(fetchPrs({ owner: 'a', repo: 'b', fetchImpl: fake }), /refused/);
});

test('a flagged category links its gate and shows the install line', () => {
  const codebook = loadCodebook();
  const prs = JSON.parse(readFileSync(new URL('./fixtures/prs.json', import.meta.url), 'utf8'));
  const html = renderHtml(audit(prs, codebook), 'owner/repo');
  // the script that refuses seam defects is linked, not merely named
  assert.match(html, /<a href="[^"]*scripts\/merge_batch\.sh"><code>scripts\/merge_batch\.sh<\/code><\/a>/);
  // and the row carries a command that installs it
  assert.match(html, /class="install"><code>cp scripts\/merge_batch\.sh/);
});

test('a category with no hits names its gate but offers no install line', () => {
  const codebook = loadCodebook();
  const html = renderHtml(audit([], codebook), 'owner/repo');
  // Nothing to fix, so nothing to install — but the reader still learns what
  // was checked, which is most of what an empty report has to give.
  assert.equal(html.includes('class="install"'), false);
  assert.match(html, /checked, nothing found/);
  assert.match(html, /merge_batch\.sh/);
});

test('a percentage is reported against measured baselines', () => {
  const html = renderHtml(audit([], loadCodebook()), 'owner/repo');
  assert.match(html, /Measured elsewhere/);
  assert.match(html, /sindresorhus\/got/);
  assert.match(html, /the case study corpus/);
  assert.match(html, /clean on every rule/);
});

test('the report does not claim what it did not measure', () => {
  const html = renderHtml(audit([], loadCodebook()), 'owner/repo');
  // It used to assert that git reported no conflicts for any of these, which
  // was never checked.
  assert.equal(/Git reports none of these as conflicts/.test(html), false);
});

test('the report states what prose cannot show', () => {
  const html = renderHtml(audit([], loadCodebook()), 'owner/repo');
  assert.match(html, /What this cannot see/);
  assert.match(html, /not one fork was a pull request merge commit/);
});

test('the report lands somewhere openable and does not become a commit', async () => {
  const { execFileSync } = await import('node:child_process');
  const { mkdtempSync, existsSync, readFileSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');

  const out = join(mkdtempSync(join(tmpdir(), 'swarm-audit-')), 'report');
  const stdout = execFileSync(process.execPath, [
    new URL('../bin/swarm-audit.mjs', import.meta.url).pathname,
    '--from-file', new URL('./fixtures/prs.json', import.meta.url).pathname,
    '--out', out, 'demo/repo',
  ], { encoding: 'utf8' });

  // A path someone has to go and find is a path that does not get opened.
  assert.match(stdout, /Report: file:\/\//);
  // The badge is the roadmap's viral loop, so the markdown is ready to paste.
  assert.match(stdout, /!\[coordination incidents\]/);
  // The output lands in whatever repository the command was run from.
  assert.equal(readFileSync(join(out, '.gitignore'), 'utf8').trim(), '*');
  for (const f of ['report.html', 'report.json', 'badge.svg']) {
    assert.ok(existsSync(join(out, f)), `${f} written`);
  }
});
