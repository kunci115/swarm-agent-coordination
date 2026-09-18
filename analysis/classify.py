#!/usr/bin/env python3
"""classify.py — derive coordination incidents from the corpus, not from notes.

    python3 analysis/classify.py [--export DIR] [--out data/incidents.json]

The original classification read pull request prose for keywords. That is a
defensible method and it is what produced the published counts, but it measures
how often a failure was *written about*. This classifier keeps those text rules
and adds a second kind of rule: signals computed from structured data, which
fire whether or not anyone narrated the problem.

Each incident records which rules fired and of which kind, so a disagreement
with the published labels can be traced to a rule rather than to a judgement.

The labelled set in existing_labels.csv covers 85 pull requests. It is treated
here as a comparison set, not as ground truth — it was produced by one method,
and the point of this script is to see what a second method does with the same
corpus.
"""

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

TAXONOMY_VERSION = 2

# Text rules: what a human wrote about the failure.
TEXT_RULES = {
    "shared_resource_db": [
        r"\bmigration chain\b", r"\bdown_revision\b", r"\balembic\b",
        r"\b(two|multiple|second) heads?\b", r"\bconnection pool\b",
        r"\bpool (size|ceiling|exhaust)", r"\bdead ?lock\b",
        r"\badvisory lock\b", r"\bschema (drift|conflict)\b",
    ],
    # "runner" and "self-hosted" alone match most of this corpus, which is about
    # CI infrastructure throughout. The rule needs contention language, not
    # infrastructure language.
    "shared_resource_runner": [
        r"\brunner[s]?\b.{0,40}\b(queue|quota|exhaust|stall|starv|busy|out of)\b",
        r"\b(queue|quota|exhaust|stall|starv|busy|out of)\b.{0,40}\brunner[s]?\b",
        r"\bwaiting for a runner\b", r"\bno runner\b", r"\brunner quota\b",
        r"\bconcurrency limit\b",
    ],
    "seam_explicit": [
        r"\bseam\b", r"\bno conflict\b", r"\bboundary between\b",
        r"\binterface between\b", r"\bintegration (point|defect|failure)\b",
        r"\bcontract (mismatch|between)\b", r"\bwhere .{0,20}(meet|join)\b",
        r"\bonly (visible|appears) when combined\b",
    ],
    "revert_rework": [
        r"\brevert(s|ed|ing)?\b", r"\bsupersede[sd]?\b", r"\breplaces #\d+",
        r"\brewritten\b", r"\bredo(ne|ing)?\b", r"\brework(ed|ing)?\b",
        r"\binstead of #\d+", r"\bobsoletes #\d+",
    ],
    "cross_lane_dependency": [
        r"\bbehind (dev|main|the integration branch)\b", r"\bback[- ]?merge\b",
        r"\brebase[sd]? onto (dev|main)\b", r"\bblocked by #\d+",
        r"\bdepends on #\d+", r"\bwaiting (on|for) #\d+",
        r"\blanded behind\b",
    ],
    "conflict_merge": [
        r"\bmerge conflict\b", r"\bconflicted?\b.{0,20}\bmerg",
        r"\bresolve[sd]? (the )?conflict", r"\bboth modified\b",
        r"<<<<<<<",
    ],
}

COMPILED = {k: [re.compile(p, re.I) for p in v] for k, v in TEXT_RULES.items()}

MIGRATION_PATH = re.compile(r"(migrations?/versions?/|/alembic/|migration)", re.I)

# Queue thresholds are calibrated against this corpus rather than fixed, because
# the corpus itself settles what "queued" means here: the median pull request
# waited about eleven minutes for a runner. A five-minute rule would flag two
# thirds of the corpus, and a condition that holds two thirds of the time is a
# background condition, not an incident. The rule fires on the tail instead.
QUEUE_PERCENTILE = 0.90

# Not every rule detects the same kind of thing, and collapsing them hides the
# difference that matters most when reading a count.
#   exposure  the pull request touched a shared resource. Nothing went wrong;
#             it was in a position where something could.
#   failure   the resource actually broke: the chain forked, the work was undone.
#   narrated  a human wrote that something went wrong. This is what the original
#             keyword method could see, and all it could see.
SIGNAL_KIND = {
    "touches-migration-file": "exposure",
    "merge-commit-forked-the-chain": "failure",
    "title-is-a-revert": "failure",
}


def load(path):
    with open(path, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def build_context(d):
    """Structured signals, keyed so a rule can ask about one pull request."""
    ctx = {}

    # migration chain forks, by the commit that introduced them
    forks = set()
    summary = d / "migration_summary.json"
    if summary.exists():
        mig = json.loads(summary.read_text(encoding="utf-8"))
        forks = {e["sha"][:12] for e in mig.get("fork_events", [])}
    ctx["fork_shas"] = forks

    # CI jobs, reachable from a pull request through its merge commit
    runs_by_sha = defaultdict(list)
    for r in load(d / "ci_runs.jsonl"):
        runs_by_sha[r["head_sha"][:12]].append(r["run_id"])
    jobs_by_run = defaultdict(list)
    for j in load(d / "ci_jobs.jsonl"):
        jobs_by_run[j["run_id"]].append(j)
    ctx["runs_by_sha"] = runs_by_sha
    ctx["jobs_by_run"] = jobs_by_run
    ctx["queue_threshold_s"] = 0  # filled by calibrate(), once the PRs are known
    return ctx


def calibrate(prs, ctx):
    """Set the queue threshold from this corpus's own tail."""
    waits = sorted(
        max((j.get("queued_seconds") or 0) for j in jobs_for(p, ctx))
        for p in prs if jobs_for(p, ctx)
    )
    if waits:
        ctx["queue_threshold_s"] = waits[min(len(waits) - 1, int(len(waits) * QUEUE_PERCENTILE))]
    return ctx["queue_threshold_s"]


def jobs_for(pr, ctx):
    sha = (pr.get("merge_commit_sha") or "")[:12]
    out = []
    for run_id in ctx["runs_by_sha"].get(sha, []):
        out.extend(ctx["jobs_by_run"].get(run_id, []))
    return out


def signals_for(pr, ctx):
    """Rules that fire on measured state rather than on prose."""
    fired = defaultdict(list)
    paths = [f["path"] for f in (pr.get("files") or []) if isinstance(f, dict)]

    if any(MIGRATION_PATH.search(p) for p in paths):
        fired["shared_resource_db"].append("touches-migration-file")
    if (pr.get("merge_commit_sha") or "")[:12] in ctx["fork_shas"]:
        fired["shared_resource_db"].append("merge-commit-forked-the-chain")

    # Deliberately no runner signal here. Queueing turned out to be a property
    # of the system over the whole period, not of any pull request: the median
    # pull request waited eleven minutes, so a per-PR rule either fires on two
    # thirds of the corpus or degenerates into an arbitrary cut through a smooth
    # distribution. Runner contention is reported as a corpus-level measurement
    # instead, which is what it is. Attributing a shared-resource shortage to
    # the individual work that happened to be queued behind it is the same
    # mistake the shortage itself is made of.

    if (pr.get("title") or "").lower().startswith(("revert", "re-revert")):
        fired["revert_rework"].append("title-is-a-revert")

    return fired


def classify(pr, ctx):
    text = f"{pr.get('title') or ''}\n{pr.get('body') or ''}"
    fired = defaultdict(list)
    for cat, patterns in COMPILED.items():
        for pat in patterns:
            if pat.search(text):
                fired[cat].append(f"text[narrated]:{pat.pattern}")
                break
    for cat, reasons in signals_for(pr, ctx).items():
        for r in reasons:
            base = r.split("-", 2)[0] if r.startswith("gate-") else r
            fired[cat].append(f"signal[{SIGNAL_KIND.get(base, 'exposure')}]:{r}")
    return dict(fired)


def score(predicted, truth, categories, universe):
    """Confusion over every pull request, not only the labelled ones."""
    rows = []
    for cat in categories:
        tp = sum(1 for n in universe if cat in predicted.get(n, {}) and cat in truth.get(n, set()))
        fp = sum(1 for n in universe if cat in predicted.get(n, {}) and cat not in truth.get(n, set()))
        fn = sum(1 for n in universe if cat not in predicted.get(n, {}) and cat in truth.get(n, set()))
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        rows.append((cat, tp, fp, fn, prec, rec, f1))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--export", default="export", type=Path)
    ap.add_argument("--out", default="data/incidents.json", type=Path)
    args = ap.parse_args()
    d = args.export

    prs = [p for p in load(d / "pull_requests.jsonl")
           if p.get("state") == "merged" and p.get("base_ref") == "dev"]
    ctx = build_context(d)
    threshold = calibrate(prs, ctx)

    predicted = {}
    for p in prs:
        fired = classify(p, ctx)
        if fired:
            predicted[p["number"]] = fired

    # published labels, for comparison only
    truth = {}
    with open(d / "existing_labels.csv", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            truth[int(row["pr"])] = {c.strip() for c in row["categories"].split(",") if c.strip()}

    universe = [p["number"] for p in prs]
    categories = list(TEXT_RULES)

    print(f"taxonomy v{TAXONOMY_VERSION} · {len(prs)} pull requests · "
          f"{len(predicted)} flagged · published set flagged {len(truth)}")
    print(f"queue threshold calibrated at p{QUEUE_PERCENTILE:.0%} = {threshold/60:.0f} min\n")

    hdr = f"{'category':<24}{'pub':>5}{'new':>5}{'tp':>5}{'fp':>5}{'fn':>5}{'prec':>7}{'rec':>7}{'f1':>7}"
    print(hdr)
    print("-" * len(hdr))
    pub_counts = Counter(c for cats in truth.values() for c in cats)
    new_counts = Counter(c for cats in predicted.values() for c in cats)
    for cat, tp, fp, fn, prec, rec, f1 in score(predicted, truth, categories, universe):
        print(f"{cat:<24}{pub_counts.get(cat, 0):>5}{new_counts.get(cat, 0):>5}"
              f"{tp:>5}{fp:>5}{fn:>5}{prec:>7.2f}{rec:>7.2f}{f1:>7.2f}")

    # Runner contention, measured over the corpus rather than attributed per PR.
    waits, cancelled_total = [], 0
    for pr in prs:
        js = jobs_for(pr, ctx)
        if js:
            waits.append(max((j.get("queued_seconds") or 0) for j in js))
        cancelled_total += sum(1 for j in js if j.get("conclusion") == "cancelled")
    if waits:
        waits.sort()
        print(f"\nrunner contention (corpus-level, not a per-PR label)")
        print(f"  median wait for a runner : {waits[len(waits)//2]/60:.0f} min")
        print(f"  p90 / max                : {threshold/60:.0f} / {waits[-1]/60:.0f} min")
        print(f"  PRs waiting over 5 min   : {sum(1 for w in waits if w > 300)} of {len(waits)}")
        print(f"  cancelled gate jobs      : {cancelled_total}")

    both = set(predicted) & set(truth)
    print(f"\nflagged by both methods : {len(both)}")
    print(f"only the published set  : {len(set(truth) - set(predicted))}")
    print(f"only this classifier    : {len(set(predicted) - set(truth))}")

    def kinds_of(f):
        return {r[r.index("[") + 1:r.index("]")] for rs in f.values() for r in rs}

    narrated = sum(1 for f in predicted.values() if "narrated" in kinds_of(f))
    failure = sum(1 for f in predicted.values() if "failure" in kinds_of(f))
    exposure_only = sum(1 for f in predicted.values() if kinds_of(f) == {"exposure"})
    print(f"\nby what the rule detected")
    print(f"  narrated by a human      : {narrated}")
    print(f"  measured failure         : {failure}")
    print(f"  exposure only, no failure: {exposure_only}")
    print("  (exposure is where a lane could have collided, not where it did —")
    print("   counting it as an incident is what inflates a shared-resource category)")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "taxonomy_version": TAXONOMY_VERSION,
        "queue_threshold_seconds": ctx["queue_threshold_s"],
        "queue_percentile": QUEUE_PERCENTILE,
        "pull_requests_considered": len(prs),
        "incidents": [
            {"pr": n, "categories": sorted(f), "evidence": {k: v for k, v in sorted(f.items())}}
            for n, f in sorted(predicted.items())
        ],
    }
    args.out.write_text(json.dumps(payload, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"\nwrote {args.out} ({len(predicted)} incidents)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
