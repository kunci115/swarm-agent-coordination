const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const KIT = 'https://github.com/kunci115/swarm-agent-coordination/blob/main/';

// A gate string names the files that refuse the category. Turn each one into a
// link, so a row is something a reader can act on rather than a sentence they
// have to go and search for.
const linkScripts = (gate) => esc(gate).replace(
  /((?:scripts|\.github\/workflows)\/[\w.\/-]+|AGENTS\.md(?:\.template)?)/g,
  (m) => `<a href="${KIT}${m}"><code>${m}</code></a>`,
);

export function renderHtml(result, repoLabel) {
  const pct = Math.round(result.incidentRate * 100);
  const rows = result.categories
    .map((c) => {
      if (!c.count) return `<tr><td>${esc(c.label)}</td><td class="num">0</td><td><span class="muted">No incidents found</span></td></tr>`;
      const install = c.install ? `<div class="install"><code>${esc(c.install)}</code></div>` : '';
      return `<tr><td>${esc(c.label)}</td><td class="num">${c.count}</td><td>${linkScripts(c.gate)}${install}</td></tr>`;
    })
    .join('');
  const flagged = result.flagged
    .map((f) => `<li><a href="${esc(f.url)}">#${f.number}</a> ${esc(f.title)}<div class="muted">${f.hits.map((h) => `${esc(h.id)} (${h.confidence}: "${esc(h.evidence)}")`).join(', ')}</div></li>`)
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
<p>${result.incidentPrs} of ${result.totalPrs} pull requests show a coordination incident. Git reports none of these as conflicts.</p>
<div class="wrap"><table><thead><tr><th>Category</th><th class="num">PRs</th><th>Gate that refuses it</th></tr></thead><tbody>${rows}</tbody></table></div>
<h2>Flagged pull requests</h2><ol>${flagged || '<li class="muted">None</li>'}</ol>
<h2>What this cannot see</h2>
<p class="muted">The audit reads pull request prose, so it counts how often a failure was <em>written about</em>. Two categories under-report for structural reasons. Runner contention belongs to the CI system rather than to any pull request: in the corpus behind this codebook the median pull request waited eleven minutes for a runner and 155 of 226 waited over five, while two narrated it. Migration chain forks usually happen between pushes and are repaired before review, so no pull request mentions them — that chain forked eleven times and not one fork was a pull request merge commit. Both need the gates above, installed, rather than a better report.</p>
<p class="muted">Keyword-based classification. Treat low-confidence hits as leads, not verdicts.</p>
</main></body></html>`;
}
