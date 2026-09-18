#!/usr/bin/env python3
"""reproduce.py — recompute every published number from the exported corpus.

    python3 analysis/reproduce.py [--export DIR]

Prints one row per metric: what was published, what the data says now, and
whether they agree. A mismatch is a finding, not a bug to be smoothed over —
the point of keeping events rather than conclusions is that anyone can rerun
this and disagree with the classification without asking for the raw system.

Metrics marked NEW were not in the original analysis. They come from data that
existed all along but was read narratively rather than mechanically.

Standard library only, on purpose: a reproduction script that needs a
dependency resolved four years from now does not reproduce anything.
"""

import argparse
import json
import re
import statistics
from collections import Counter
from datetime import datetime
from pathlib import Path

# Published values, from the case study. Kept in one place so the comparison
# is explicit rather than buried in prose.
PUBLISHED = {
    "commits": 1417,
    "prs_merged_to_dev": 229,
    "issues": 275,
    "lead_pairs": 140,
    "lead_median_h": 4.3,
    "lead_mean_h": 9.7,
    "lead_max_h": 73.1,
    "paths_owned_last100": 99,
    "labeled_prs": 85,
}

# The export carries no linked_issues field — the platform's own link graph did
# not survive extraction — so links are recovered from the closing keyword.
# Anchored to the start of a line, which is GitHub's canonical linking form;
# the unanchored variant also matches issue numbers quoted inside prose and
# tables, which inflates the pair count without adding real links.
CLOSES = re.compile(r"^\s*(?:close[sd]?|fixe?[sd]?|resolve[sd]?)\s+#(\d+)", re.I | re.M)
OWNED_LINE = re.compile(r"^\s*[-*]\s+`?([^\s`(]+)")


def load(path):
    with open(path, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def ts(value):
    """Parse an ISO timestamp, tolerating the Z suffix."""
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def declared_paths(raw):
    """Paths a PR claimed, parsed from its verbatim '## Paths owned' block."""
    if not raw:
        return set()
    out = set()
    for line in raw.splitlines():
        if line.strip().lower().startswith("## "):
            continue
        m = OWNED_LINE.match(line)
        if m:
            out.add(m.group(1).rstrip(",;"))
    return out


class Report:
    def __init__(self):
        self.rows = []

    def check(self, name, published, actual, tol=0.0):
        if published is None:
            verdict = "NEW"
        elif isinstance(published, float):
            verdict = "ok" if abs(published - actual) <= tol else "DIFF"
        else:
            verdict = "ok" if published == actual else "DIFF"
        self.rows.append((name, published, actual, verdict))

    def render(self):
        w = max(len(r[0]) for r in self.rows) + 2
        print(f"{'metric'.ljust(w)}{'published':>12}{'computed':>12}   verdict")
        print("-" * (w + 36))
        for name, pub, act, verdict in self.rows:
            p = "—" if pub is None else (f"{pub:g}" if isinstance(pub, float) else str(pub))
            a = f"{act:g}" if isinstance(act, float) else str(act)
            print(f"{name.ljust(w)}{p:>12}{a:>12}   {verdict}")
        diffs = [r for r in self.rows if r[3] == "DIFF"]
        print()
        print(f"{len(self.rows)} metrics · {len(diffs)} disagree with the published value")
        return diffs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--export", default="export", type=Path)
    args = ap.parse_args()
    d = args.export

    commits = load(d / "commits.jsonl")
    prs = load(d / "pull_requests.jsonl")
    issues = load(d / "issues.jsonl")
    jobs = load(d / "ci_jobs.jsonl")
    r = Report()

    # ---- corpus size ------------------------------------------------------
    r.check("commits", PUBLISHED["commits"], len(commits))
    merged = [p for p in prs if p.get("state") == "merged" and p.get("base_ref") == "dev"]
    r.check("prs merged to dev", PUBLISHED["prs_merged_to_dev"], len(merged))
    r.check("issues", PUBLISHED["issues"], len(issues))

    # ---- feature cycle time ----------------------------------------------
    # The export carries no linked_issues field, so the links are recovered the
    # way a reader would: the closing keyword in the pull request body.
    by_number = {i["number"]: i for i in issues}
    leads = []
    lead_pairs = []
    for p in merged:
        merged_at = ts(p.get("merged_at"))
        if not merged_at:
            continue
        text = f"{p.get('title') or ''}\n{p.get('body') or ''}"
        for num in {int(n) for n in CLOSES.findall(text)}:
            issue = by_number.get(num)
            if not issue:
                continue
            opened = ts(issue.get("created_at"))
            if opened and merged_at > opened:
                leads.append((merged_at - opened).total_seconds() / 3600)
                lead_pairs.append((p["number"], num))

    linking_prs = len({p for p, _ in lead_pairs})
    r.check("PRs closing an issue", PUBLISHED["lead_pairs"], linking_prs)
    r.check("issue→PR pairs recovered (NEW)", None, len(leads))
    if leads:
        r.check("lead median (h)", PUBLISHED["lead_median_h"], round(statistics.median(leads), 1), tol=0.5)
        r.check("lead mean (h)", PUBLISHED["lead_mean_h"], round(statistics.mean(leads), 1), tol=1.0)
        r.check("lead max (h)", PUBLISHED["lead_max_h"], round(max(leads), 1), tol=1.0)

    # ---- merge governance (NEW) ------------------------------------------
    # Rule 2 says a lane never merges its own pull request. Narrative reported
    # this as a policy; here it is a count.
    mergers = {p.get("merged_by_key") for p in merged if p.get("merged_by_key")}
    self_merged = sum(
        1 for p in merged
        if p.get("merged_by_key") and p.get("merged_by_key") == p.get("author_key")
    )
    r.check("distinct mergers (NEW)", None, len(mergers))
    r.check("self-merged PRs (NEW)", None, self_merged)

    # ---- path ownership: declared vs actually touched (NEW) --------------
    # The original analysis audited this on a 30-PR pilot. The export makes the
    # audit total.
    last100 = sorted(merged, key=lambda p: p["number"])[-100:]
    r.check("paths owned, last 100", PUBLISHED["paths_owned_last100"],
            sum(1 for p in last100 if p.get("paths_owned_raw")))

    exact, superset, understated = 0, 0, 0
    undeclared_files = 0
    audited = 0
    for p in merged:
        raw = p.get("paths_owned_raw")
        files = {f["path"] for f in (p.get("files") or []) if isinstance(f, dict) and f.get("path")}
        if not raw or not files:
            continue
        audited += 1
        claimed = declared_paths(raw)
        missed = files - claimed
        if not missed:
            exact += 1
            if claimed - files:
                superset += 1
        else:
            understated += 1
            undeclared_files += len(missed)

    r.check("PRs audited for ownership (NEW)", None, audited)
    r.check("  declaration covered the diff (NEW)", None, exact)
    r.check("  declaration missed files (NEW)", None, understated)
    r.check("  files touched undeclared (NEW)", None, undeclared_files)

    # ---- CI runner contention (NEW) --------------------------------------
    # Reported as 2 incidents, because only 2 pull requests narrated it.
    q = sorted(j["queued_seconds"] for j in jobs if j.get("queued_seconds") is not None)
    concl = Counter(j.get("conclusion") for j in jobs)
    r.check("CI jobs (NEW)", None, len(jobs))
    if q:
        r.check("  queued >5 min (NEW)", None, sum(1 for v in q if v > 300))
        r.check("  queue p95 (min) (NEW)", None, round(q[int(len(q) * 0.95)] / 60, 1))
        r.check("  queue max (min) (NEW)", None, round(q[-1] / 60, 1))
    r.check("  cancelled jobs (NEW)", None, concl.get("cancelled", 0))
    r.check("  failed jobs (NEW)", None, concl.get("failure", 0))

    # ---- migration chain (NEW) -------------------------------------------
    summary_path = d / "migration_summary.json"
    if summary_path.exists():
        mig = json.loads(summary_path.read_text(encoding="utf-8"))
        r.check("migration fork events (NEW)", None, mig.get("fork_events_count"))
        r.check("  migrations at cutoff (NEW)", None, mig.get("total_migration_files_at_cutoff"))
        r.check("  forked at cutoff (NEW)", None, str(mig.get("final_fork")))

    # ---- landings per merge commit (NEW) ---------------------------------
    per_merge = Counter(p["merge_commit_sha"] for p in merged if p.get("merge_commit_sha"))
    batched = sum(1 for n in per_merge.values() if n > 1)
    r.check("merge commits carrying >1 PR (NEW)", None, batched)
    r.check("  largest single landing (NEW)", None, max(per_merge.values()) if per_merge else 0)

    diffs = r.render()
    if diffs:
        print("\nDisagreements:")
        for name, pub, act, _ in diffs:
            print(f"  {name}: published {pub}, computed {act}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
