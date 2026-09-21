const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const KIT = 'https://github.com/kunci115/swarm-agent-coordination/blob/main/';

// A percentage with nothing to compare it against is not a reading. These were
// measured with this codebook, unauthenticated, on 2026-09-21.
const BENCHMARKS = [
  ['sindresorhus/got', 0, 60, 'human-maintained library'],
  ['vercel/swr', 2, 60, 'human-maintained library'],
  ['browser-use/jev-ultrafast', 2, 83, 'human-maintained, AI tooling'],
  ['the case study corpus', 37, 229, 'built by an agent swarm'],
];

function compare(pct) {
  if (pct >= 25) return ['reads like an agent-heavy repository', 'The case study corpus, built by a swarm with no inter-agent communication, sat at 37%.'];
  if (pct >= 10) return ['above the human-maintained repositories measured', 'Worth reading the flagged list rather than the number.'];
  if (pct > 0) return ['in the same range as human-maintained repositories', 'Nothing here suggests a coordination problem. The gates below are what keeps it that way as agent volume grows.'];
  return ['clean on every rule in the codebook', 'That is the expected result for a repository without parallel agents. It is also what this tool looks like when it has nothing to tell you.'];
}

// A gate string names the files that refuse the category. Turn each one into a
// link, so a row is something a reader can act on rather than a sentence they
// have to go and search for.
const linkScripts = (gate) => esc(gate).replace(
  /((?:scripts|\.github\/workflows)\/[\w.\/-]+|AGENTS\.md(?:\.template)?)/g,
  (m) => `<a href="${KIT}${m}"><code>${m}</code></a>`,
);

export function renderHtml(result, repoLabel) {
  const pct = Math.round(result.incidentRate * 100);
  const [verdict, note] = compare(pct);
  const bench = BENCHMARKS
    .map(([name, rate, n, what]) => `<tr><td><code>${esc(name)}</code></td><td class="num">${rate}%</td><td class="muted">${esc(what)}, ${n} PRs</td></tr>`)
    .join('');
  const rows = result.categories
    .map((c) => {
      if (!c.count) return `<tr><td class="muted">${esc(c.label)}</td><td class="num">0</td><td class="muted">checked, nothing found — ${linkScripts(c.gate)}</td></tr>`;
      const install = c.install ? `<div class="install"><code>${esc(c.install)}</code></div>` : '';
      return `<tr><td>${esc(c.label)}</td><td class="num">${c.count}</td><td>${linkScripts(c.gate)}${install}</td></tr>`;
    })
    .join('');
  const flagged = result.flagged
    .map((f) => `<li><a href="${esc(f.url)}">#${f.number}</a> ${esc(f.title)}<div class="muted">${f.hits.map((h) => (h.kind === 'structural' ? `${esc(h.id)} <b>measured</b>: ${esc(h.evidence)}` : `${esc(h.id)} (${h.confidence}: "${esc(h.evidence)}")`)).join(', ')}</div></li>`)
    .join('');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>swarm-audit: ${esc(repoLabel)}</title><style>
:root{--bg:#fff;--fg:#1f1e1d;--muted:#6b6a65;--line:#e4e2da;--accent:#A32D2D}
@media (prefers-color-scheme:dark){:root{--bg:#1f1e1d;--fg:#ecebe4;--muted:#a3a19a;--line:#3a3935;--accent:#F09595}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,sans-serif}
main{max-width:760px;margin:0 auto;padding:2rem 1rem}
.big{font-size:3rem;font-weight:600;color:var(--accent);margin:0}
.muted{color:var(--muted);font-size:.875rem}
.wrap{overflow-x:auto}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid var(--line);padding:.5rem;text-align:left;vertical-align:top}
.num{text-align:right}a{color:inherit}li{margin-bottom:.75rem}
code{font-family:ui-monospace,monospace;font-size:.85em}
.install{margin-top:.4rem}.install code{display:block;padding:.4rem .5rem;background:var(--line);border-radius:4px;overflow-x:auto;white-space:pre}
</style></head><body><main>
<p class="muted">swarm-audit · ${esc(repoLabel)} · codebook ${esc(result.codebookVersion)} · min confidence ${esc(result.minConfidence)}</p>
<p class="big">${pct}%</p>
<p>${result.incidentPrs} of ${result.totalPrs} pull requests carry language or structure this codebook associates with a coordination incident.</p>
<p><b>${esc(verdict)}.</b> ${esc(note)}</p>
<div class="wrap"><table><thead><tr><th>Measured elsewhere</th><th class="num">rate</th><th></th></tr></thead><tbody>${bench}</tbody></table></div>
<p class="muted">Benchmarks measured with this codebook on 2026-09-21. Your number means little without them: a repository whose subject matter is testing, merging or migrations reads high because its pull requests discuss the vocabulary, not because it has the problem.</p>
<div class="wrap"><table><thead><tr><th>Category</th><th class="num">PRs</th><th>Gate that refuses it</th></tr></thead><tbody>${rows}</tbody></table></div>
<h2>Flagged pull requests</h2><ol>${flagged || '<li class="muted">None</li>'}</ol>
${result.structuralOnlyPrs ? `<p><b>${result.structuralOnlyPrs}</b> of these were found by measurement alone — nothing in their text says anything went wrong.</p>` : ''}
<h2>What this cannot see</h2>
<p class="muted">The audit reads pull request prose, so it counts how often a failure was <em>written about</em>. Two categories under-report for structural reasons. Runner contention belongs to the CI system rather than to any pull request: in the corpus behind this codebook the median pull request waited eleven minutes for a runner and 155 of 226 waited over five, while two narrated it. Migration chain forks usually happen between pushes and are repaired before review, so no pull request mentions them — that chain forked eleven times and not one fork was a pull request merge commit. Both need the gates above, installed, rather than a better report.</p>
<p class="muted">Keyword-based classification. Treat low-confidence hits as leads, not verdicts.</p>
</main></body></html>`;
}
