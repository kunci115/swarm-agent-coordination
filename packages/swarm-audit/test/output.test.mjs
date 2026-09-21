import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderBadge, badgeColor } from '../src/badge.mjs';
import { renderHtml } from '../src/report.mjs';
import { fetchPrs } from '../src/github.mjs';

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
