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

1. **Ten lanes merged together produced six seam defects, none visible from inside any lane, and git reported no conflicts.** → merge-gate rule (the combined result is the gate, not green lanes).
2. **Connection pool: 16 demand vs ceiling 15** — each lane within its own visible ceiling; the sum was not. → shared resources register rule.
3. **Eight lanes stalled on an exhausted CI runner quota.** → "expect queueing, don't kill queued jobs" + runner register.
4. **Two gate jobs shared one Docker Compose project name**; the second attached to the first's database, and the first's `down -v` destroyed it. Latent until parallelism increased. → one Compose project name per lane per job.
5. **The only textual merge conflict was preempted**: nine issues known to touch `phrasing.py` were assigned to one lane at planning time. → coordination through artifacts works preventively, not just reactively.
6. **One defect escaped to production** because its test stub mirrored the code's wrong assumption — a structural limit of instrumentation. → honest reporting of what process rules cannot catch.

## Quality indicators (measured, full corpus)

- **Defect escapes**: 6 total — 5 caught in staging, 1 reached production
- **Seam defects**: 16 explicit + 6 in one incident (vs 1 textual conflict)
- **Rework**: 2 explicit supersede pairs + 41 loose indications
- **Defect finders** (narrative phrases, tightened patterns): automated tests 7, owner 3, staging 1, transcript 1, production 1, gate/CI 1
- **Feature cycle time**: median 4.3 h (n=140)
- **Rework cost**: estimated 5–20% of effort (lower bound)

## Limitations

Single case (n=1), revelatory design — no statistical generalization claims. Keyword classification validated on samples, not a manual census. Pre/post integration-model comparison is confounded (per-lane PRs did not exist on the platform before the switch). Defect-finder attribution reconstructed from PR narratives (selection bias). The researcher was the orchestrator (reflexivity); all quantitative claims rest on machine data.

## Citation

If this taxonomy or kit supports your work, cite the underlying thesis (publication pending) and this repository.
