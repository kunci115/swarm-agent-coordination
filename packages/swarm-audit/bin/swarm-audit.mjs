#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { loadCodebook, audit } from '../src/classify.mjs';
import { parseRepo, fetchPrs, fetchFiles, fetchRefStates, referencedNumbers } from '../src/github.mjs';
import { migrationOverlaps, supersedeChains, mergeSignals } from '../src/deep.mjs';
import { renderHtml } from '../src/report.mjs';
import { renderBadge } from '../src/badge.mjs';

const HELP = `Usage: swarm-audit <owner/repo | github-url> [options]

Options:
  --from-file <prs.json>   Audit a local PR export instead of calling GitHub
  --out <dir>              Output directory (default: ./swarm-audit-report)
  --limit <n>              Max PRs to fetch (default: 500)
  --min-confidence <lvl>   low | medium | high (default: medium)
  --codebook <path>        Custom codebook JSON
  --deep                   Also compute structural signals: migration files open
                           in two pull requests at once, and references to work
                           closed without merging. Costs one extra API request
                           per pull request, and finds failures nobody wrote
                           about — which is most of them.
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
    deep: { type: 'boolean', default: false },
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
  let structural = new Map();
  if (values.deep) {
    if (values['from-file']) {
      structural = migrationOverlaps(prs);
    } else {
      const { owner, repo } = parseRepo(positionals[0]);
      process.stderr.write(`deep: fetching files for ${prs.length} pull requests...\n`);
      await fetchFiles({ owner, repo, prs, token: process.env.GITHUB_TOKEN });
      const refs = new Set();
      for (const pr of prs) {
        pr.referenced_prs = referencedNumbers(pr);
        for (const n of pr.referenced_prs) refs.add(n);
      }
      process.stderr.write(`deep: resolving ${refs.size} referenced numbers...\n`);
      const states = await fetchRefStates({ owner, repo, numbers: [...refs], token: process.env.GITHUB_TOKEN });
      structural = mergeSignals(migrationOverlaps(prs), supersedeChains(prs, states));
    }
  }
  const result = audit(prs, codebook, { minConfidence: values['min-confidence'], structural });
  mkdirSync(values.out, { recursive: true });
  writeFileSync(join(values.out, 'report.json'), JSON.stringify(result, null, 2));
  writeFileSync(join(values.out, 'report.html'), renderHtml(result, label));
  writeFileSync(join(values.out, 'badge.svg'), renderBadge(result.incidentRate));
  if (values.json) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }
  console.log(`${label}: ${result.incidentPrs}/${result.totalPrs} PRs (${Math.round(result.incidentRate * 100)}%) show coordination incidents`);
  if (result.structuralOnlyPrs) console.log(`  ${result.structuralOnlyPrs} found by measurement alone — nothing in their text says so`);
  for (const c of result.categories) if (c.count) console.log(`  ${c.label.padEnd(28)} ${String(c.count).padStart(4)}  → ${c.gate}`);
  console.log(`\nReport: ${join(values.out, 'report.html')}\nBadge:  ${join(values.out, 'badge.svg')}`);
}

main().catch((err) => {
  console.error(`swarm-audit: ${err.message}`);
  process.exit(1);
});
