import { readFileSync } from 'node:fs';

export function loadCodebook(path) {
  const url = path ?? new URL('./codebook.default.json', import.meta.url);
  const raw = JSON.parse(readFileSync(url, 'utf8'));
  return {
    ...raw,
    categories: raw.categories.map((c) => ({
      ...c,
      strongRe: c.strong.map((p) => new RegExp(p, 'i')),
      weakRe: c.weak.map((p) => new RegExp(p, 'i')),
    })),
  };
}

function matchCategory(cat, title, body) {
  const text = `${title}\n${body}`;
  for (const re of cat.strongRe) {
    const m = text.match(re);
    if (m) return { id: cat.id, confidence: 'high', evidence: m[0] };
  }
  for (const re of cat.weakRe) {
    const inTitle = title.match(re);
    if (inTitle) return { id: cat.id, confidence: 'medium', evidence: inTitle[0] };
    const inBody = body.match(re);
    if (inBody) return { id: cat.id, confidence: 'low', evidence: inBody[0] };
  }
  return null;
}

export function classifyPr(pr, codebook) {
  const title = pr.title ?? '';
  const body = pr.body ?? '';
  const hits = [];
  for (const cat of codebook.categories) {
    const hit = matchCategory(cat, title, body);
    if (hit) hits.push(hit);
  }
  return hits;
}

export function audit(prs, codebook, { minConfidence = 'medium' } = {}) {
  const rank = { low: 0, medium: 1, high: 2 };
  const floor = rank[minConfidence];
  const byCategory = Object.fromEntries(codebook.categories.map((c) => [c.id, 0]));
  const flagged = [];
  for (const pr of prs) {
    const hits = classifyPr(pr, codebook).filter((h) => rank[h.confidence] >= floor);
    if (hits.length === 0) continue;
    for (const h of hits) byCategory[h.id] += 1;
    flagged.push({ number: pr.number, title: pr.title, url: pr.html_url, hits });
  }
  const total = prs.length;
  return {
    codebookVersion: codebook.version,
    minConfidence,
    totalPrs: total,
    incidentPrs: flagged.length,
    incidentRate: total === 0 ? 0 : flagged.length / total,
    categories: codebook.categories.map((c) => ({ id: c.id, label: c.label, gate: c.gate, count: byCategory[c.id] })),
    flagged,
  };
}
