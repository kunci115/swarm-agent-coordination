#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { loadCodebook, audit } from '../src/classify.mjs';
import { parseRepo, fetchPrs } from '../src/github.mjs';
import { renderHtml } from '../src/report.mjs';
import { renderBadge } from '../src/badge.mjs';

const HELP = `Usage: swarm-audit <owner/repo | github-url> [options]

Options:
  --from-file <prs.json>   Audit a local PR export instead of calling GitHub
  --out <dir>              Output directory (default: ./swarm-audit-report)
  --limit <n>              Max PRs to fetch (default: 500)
  --min-confidence <lvl>   low | medium | high (default: medium)
  --codebook <path>        Custom codebook JSON
  --json                   Print JSON result to stdout
  -h, --help               Show help

Env: GITHUB_TOKEN for private repos and higher rate limits.`;

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    'from-file': { type: 'string' },
    out: { type: 'string', default: 'swarm-audit-report' },
    limit: { type: 'string', default: '500' },
    'min-confidence': { type: 'string', default: 'medium' },
    codebook: { type: 'string' },
    json: { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
});

async function main() {
  if (values.help || (!positionals[0] && !values['from-file'])) {
    console.log(HELP);
    return;
  }
  if (!['low', 'medium', 'high'].includes(values['min-confidence'])) throw new Error('--min-confidence must be low, medium, or high');
  const codebook = loadCodebook(values.codebook);
  let prs;
  let label;
  if (values['from-file']) {
    prs = JSON.parse(readFileSync(values['from-file'], 'utf8'));
    label = positionals[0] ?? values['from-file'];
  } else {
    const { owner, repo } = parseRepo(positionals[0]);
    label = `${owner}/${repo}`;
    prs = await fetchPrs({ owner, repo, token: process.env.GITHUB_TOKEN, limit: Number(values.limit) });
  }
  const result = audit(prs, codebook, { minConfidence: values['min-confidence'] });
  mkdirSync(values.out, { recursive: true });
  writeFileSync(join(values.out, 'report.json'), JSON.stringify(result, null, 2));
  writeFileSync(join(values.out, 'report.html'), renderHtml(result, label));
  writeFileSync(join(values.out, 'badge.svg'), renderBadge(result.incidentRate));
  if (values.json) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }
  console.log(`${label}: ${result.incidentPrs}/${result.totalPrs} PRs (${Math.round(result.incidentRate * 100)}%) show coordination incidents`);
  for (const c of result.categories) if (c.count) console.log(`  ${c.label.padEnd(28)} ${String(c.count).padStart(4)}  → ${c.gate}`);
  console.log(`\nReport: ${join(values.out, 'report.html')}\nBadge:  ${join(values.out, 'badge.svg')}`);
}

main().catch((err) => {
  console.error(`swarm-audit: ${err.message}`);
  process.exit(1);
});
