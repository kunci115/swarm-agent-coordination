# RESEARCH.md — The case study behind this kit

This kit is not a set of opinions. Every rule traces to a coordination incident observed and classified in a 35-day production case study, conducted as Design Science Research (Peffers et al., 2007; Hevner et al., 2004) on a single fully-instrumented case.

## The case

A real information system (workshop management for a motorcycle service business; anonymized) was built by a swarm of AI agents — LLM-based agents with planning, memory, and tool use — coordinated by one human orchestrator. **No inter-agent communication**: all coordination flowed through repository artifacts.

35 days (2026-08-13 → 2026-09-17), frozen at a data cutoff (git SHA, GitHub API snapshots):

| Metric | Value |
|---|---|
| Commits | 1,417 |
| Pull requests merged (to integration branch) | 229 |
| Issues | 275 |
| Automated test functions | 5,787 |
| DB tables | 48 |
| Agent worktrees observed | 159 |
| Issue→PR lead time | median 4.3 h, mean 9.7 h, max 73.1 h (n=140 linked pairs) |

## Coordination incident classification

85 of 229 PRs (37%) showed indications of coordination incidents, classified by programmatic keyword patterns validated on a manual sample (indications, not a census). One PR can carry multiple categories (103 category hits > 85 unique PRs).

| Category | n | Example |
|---|---|---|
| rework / supersede | 41 | a PR rewritten by its successor ("Supersedes #67") |
| shared DB resources | 40 | Alembic migration chain forks (two heads), connection pool oversubscription (16/15), DB locks |
| explicit seam defects | 16 | "no conflict for any", defects visible only at module joins |
| cross-lane dependency | 3 | lane landed behind dev/main, needed back-merge |
| runner queue | 2 | 8 lanes stalled: gate ran on exhausted GitHub runner quota |
| textual merge conflict | 1 | the only textual conflict — preempted by assigning 9 related issues to one lane |

## The six worst-case findings that shaped the rules

Each finding names the rule it produced and the tool in this kit that now enforces it. A finding with no tool is an honest gap, not an omission — finding 6 is one.

1. **Ten lanes merged together produced six seam defects, none visible from inside any lane, and git reported no conflicts.** Four of the six would have reached `dev` had the lanes merged themselves. → merge-gate rule: the combined result is the gate, not green lanes. → `scripts/merge_batch.sh`, `.github/workflows/merge-gate.yml`
2. **Connection pool: 16 demand vs ceiling 15** — each lane within its own visible ceiling; the sum was not. → shared resources register rule. → the register table in `AGENTS.md.template`
3. **Eight lanes stalled on an exhausted CI runner quota**; nine of those PRs had been green since the previous day. → "expect queueing, don't kill queued jobs" + runner register. → the same register
4. **Two gate jobs shared one Docker Compose project name**; the second attached to the first's database, and the first's `down -v` destroyed it. Latent until parallelism increased, because a workflow-level `env` block cannot see matrix values. → one Compose project name per lane per job. → `scripts/check_compose_name.sh`
5. **The only textual merge conflict was preempted**: nine issues known to touch `phrasing.py` were assigned to one lane at planning time. → coordination through artifacts works preventively, not just reactively. → no tool; this one is a planning decision, and naming it as such is the point
6. **One defect escaped to production** because its test stub mirrored the code's wrong assumption — the stub and the code were identically wrong, so they agreed. No amount of additional testing from the same assumption could catch it; only an external source of truth could. → a structural limit of instrumentation. → **no tool, and there cannot be one.** Reported here because a kit that claims to catch everything is lying about the one case that matters.

Beyond the six: **migration chain forks** were the mechanism behind the largest incident category (40 of 85 flagged PRs touched shared DB resources). Two lanes write a migration against the same parent, each lane is internally consistent, git reports no conflict because the files differ, and the fork surfaces only on upgrade. → `scripts/check_migration_chain.sh`

## Quality indicators (measured, full corpus)

- **Defect escapes**: 6 total — 5 caught in staging, 1 reached production
- **Seam defects**: 16 explicit + 6 in one incident (vs 1 textual conflict)
- **Rework**: 2 explicit supersede pairs + 41 loose indications
- **Defect finders** (narrative phrases, tightened patterns): automated tests 7, owner 3, staging 1, transcript 1, production 1, gate/CI 1
- **Feature cycle time**: median 4.3 h (n=140)
- **Rework cost**: estimated 5–20% of effort (lower bound)

## What the corpus corrected

The counts above were produced by reading pull request prose for keywords. That
method measures how often a failure was *written about*. Re-deriving the same
taxonomy from structured data (`analysis/`, reproducible with `make check`)
changed three of them, and two are corrections rather than additions.

**Runner contention was reported as 2 incidents. It was a permanent condition.**
The median pull request waited **eleven minutes** for a runner and 155 of 226
waited over five. Three attempts at a per-PR rule reached precision 0.01, 0.02,
0.02 — the threshold was never the problem. Queueing held for thirty-five days,
so no per-PR rule can separate signal from background. The number 2 counts how
often someone narrated it, not how often it happened. Contention belongs at
corpus level; a shared-resource shortage is not a property of the work queued
behind it.

**No migration chain fork was visible to the pull request gate.** The chain
forked 11 times. **Zero** of the eleven were pull request merge commits — they
occurred in integration-round merges, `dev`→lane back-merges, and one ordinary
feature commit, then were repaired before review. Every pull request opened onto
a single head. This is the strongest evidence in the corpus for the client-side
hook over CI alone: the gate was right every time and would have caught none of
them.

**Declaring ownership is not declaring it correctly.** Of 221 pull requests
carrying a `## Paths owned` block, **63 did not cover their own diff** — 540
files touched but undeclared, a 28% gap between ritual and substance. The rule
in this kit now checks the declaration against the diff, calibrated against
exactly this measurement.

## Limitations

Single case (n=1), revelatory design — no statistical generalization claims. Keyword classification validated on samples, not a manual census. Pre/post integration-model comparison is confounded (per-lane PRs did not exist on the platform before the switch). Defect-finder attribution reconstructed from PR narratives (selection bias). The researcher was the orchestrator (reflexivity); all quantitative claims rest on machine data.

## Citation

If this taxonomy or kit supports your work, cite the underlying thesis (publication pending) and this repository.
