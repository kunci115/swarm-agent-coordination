const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export function renderHtml(result, repoLabel) {
  const pct = Math.round(result.incidentRate * 100);
  const rows = result.categories
    .map((c) => `<tr><td>${esc(c.label)}</td><td class="num">${c.count}</td><td>${c.count ? esc(c.gate) : '<span class="muted">No incidents</span>'}</td></tr>`)
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
</style></head><body><main>
<p class="muted">swarm-audit · ${esc(repoLabel)} · codebook ${esc(result.codebookVersion)} · min confidence ${esc(result.minConfidence)}</p>
<p class="big">${pct}%</p>
<p>${result.incidentPrs} of ${result.totalPrs} pull requests show a coordination incident. Git reports none of these as conflicts.</p>
<div class="wrap"><table><thead><tr><th>Category</th><th class="num">PRs</th><th>Gate that refuses it</th></tr></thead><tbody>${rows}</tbody></table></div>
<h2>Flagged pull requests</h2><ol>${flagged || '<li class="muted">None</li>'}</ol>
<p class="muted">Keyword-based classification. Treat low-confidence hits as leads, not verdicts.</p>
</main></body></html>`;
}
