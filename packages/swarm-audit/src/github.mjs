export function parseRepo(input) {
  const m = String(input).trim().match(/(?:github\.com[/:])?([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/);
  if (!m) throw new Error(`Cannot parse repository: ${input}. Use owner/repo or a GitHub URL.`);
  return { owner: m[1], repo: m[2] };
}

export async function fetchPrs({ owner, repo, token, limit = 500, fetchImpl = fetch }) {
  const prs = [];
  let page = 1;
  while (prs.length < limit) {
    const url = `https://api.github.com/repos/${owner}/${repo}/pulls?state=all&per_page=100&page=${page}`;
    const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'swarm-audit' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetchImpl(url, { headers });
    const limited = res.status === 429 || (res.status === 403 && res.headers.get('x-ratelimit-remaining') === '0');
    if (limited) {
      const reset = res.headers.get('x-ratelimit-reset');
      const when = reset ? new Date(Number(reset) * 1000).toISOString() : 'later';
      throw new Error(`GitHub rate limit hit. Set GITHUB_TOKEN or retry after ${when}.`);
    }
    if (res.status === 403) throw new Error('GitHub refused the request (403). Check GITHUB_TOKEN scope or your network proxy.');
    if (res.status === 404) throw new Error(`Repository ${owner}/${repo} not found (private repos need GITHUB_TOKEN).`);
    if (!res.ok) throw new Error(`GitHub API error ${res.status}`);
    const batch = await res.json();
    if (batch.length === 0) break;
    for (const p of batch) {
      prs.push({ number: p.number, title: p.title, body: p.body ?? '', html_url: p.html_url, state: p.state, merged_at: p.merged_at });
    }
    if (batch.length < 100) break;
    page += 1;
  }
  return prs.slice(0, limit);
}

async function api(path, { token, fetchImpl = fetch }) {
  const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'swarm-audit' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetchImpl(`https://api.github.com${path}`, { headers });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`GitHub API error ${res.status} on ${path}`);
  return res.json();
}

/**
 * Attach the file list to each pull request. One request per pull request, so
 * the caller decides whether that is affordable — this is what --deep costs.
 */
export async function fetchFiles({ owner, repo, prs, token, fetchImpl = fetch, onProgress }) {
  let done = 0;
  for (const pr of prs) {
    const files = await api(`/repos/${owner}/${repo}/pulls/${pr.number}/files?per_page=100`, { token, fetchImpl });
    pr.files = (files ?? []).map((f) => f.filename);
    done += 1;
    onProgress?.(done, prs.length);
  }
  return prs;
}

/**
 * Resolve referenced numbers to { isPr, merged, closed }. A number in a body is
 * just an integer: in the corpus behind this tool three quarters of them point
 * at issues, so each one is looked up rather than assumed.
 */
export async function fetchRefStates({ owner, repo, numbers, token, fetchImpl = fetch }) {
  const states = new Map();
  for (const n of numbers) {
    const pr = await api(`/repos/${owner}/${repo}/pulls/${n}`, { token, fetchImpl });
    if (!pr) { states.set(n, { isPr: false }); continue; }
    states.set(n, { isPr: true, merged: Boolean(pr.merged_at), closed: pr.state === 'closed' });
  }
  return states;
}

/** Numbers referenced in a body, as integers. */
export function referencedNumbers(pr) {
  return [...new Set([...String(pr.body ?? '').matchAll(/#(\d+)/g)].map((m) => Number(m[1])))]
    .filter((n) => n !== pr.number);
}
