# Swarm Agent Coordination

[![kit-selftest](https://github.com/kunci115/swarm-agent-coordination/actions/workflows/kit-selftest.yml/badge.svg)](https://github.com/kunci115/swarm-agent-coordination/actions/workflows/kit-selftest.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**A classified record of what actually breaks when a swarm of AI agents builds real software in one repository — and the rules of engagement that caught it.**

Over 35 days, a fleet of AI agents built a production information system: 1,417 commits, 229 pull requests, 275 issues, 5,787 automated test functions, 48 database tables, 159 agent worktrees. One human orchestrator. **No inter-agent communication of any kind** — every agent coordinated with every other agent only through artifacts in the repository.

Every coordination incident in that corpus was classified. 85 of the 229 pull requests (37%) carried one. This repository is that classification, plus the rules that now refuse each failure mechanically.

> Methodology, the full 85-incident classification, quality indicators, and limitations: [`docs/RESEARCH.md`](docs/RESEARCH.md)

## What actually broke

| Category | Pull requests | What it looked like |
|---|---|---|
| Rework / supersede | 41 | a PR rewritten by its successor ("Supersedes #67") |
| Shared database resources | 40 | migration chain forked into two heads; connection pool at 16 against a ceiling of 15; lock contention |
| Explicit seam defects | 16 | defects visible only where two modules join |
| Cross-lane dependency | 3 | a lane landed behind the integration branch, needed a back-merge |
| Runner queue | 2 | 8 lanes stalled on an exhausted CI runner quota |
| Textual merge conflict | **1** | the only one — and it was preempted, not resolved |

Read the last two rows against each other, because that contrast is the whole finding:

**Sixteen seam defects. One textual conflict.** The failure git is built to catch was the rarest thing that happened. Everything else was semantic — two agents editing different files in ways that contradicted each other, and every tool in the pipeline reporting green.

The worst single incident: ten lanes merged together produced **six defects, not one of them visible from inside any lane**, and git reported no conflict on any of them. Four of the six would have reached the integration branch had each lane merged itself.

And the one textual conflict never happened by luck. Nine issues known to touch the same file were assigned to a single lane at planning time. Coordination through artifacts works *before* the fact, not only after it.

## The principle

**Coordination through artifacts, not conversation.**

Agents in this case never talked to each other. They wrote rules to each other through shared artifacts — ownership declarations, branch conventions, quality gates, resource registers, merge policies — and behaved correctly for as long as those artifacts were explicit and mechanically enforced.

That framing is not new. Malone & Crowston defined coordination as *the management of dependencies between activities*, and named four dependency types: shared resources, producer/consumer, simultaneity, and task/subtask. The finding here is that all four survive the substitution of the actor. Replace human developers with AI agents and the dependencies do not go away — but the informal human channels that used to absorb them do. What is left has to be written down, or it becomes an incident.

Every incident in the table above is one of those four dependencies going unmanaged.

## What refuses it now

| What went wrong | What refuses it |
|---|---|
| Ten lanes merged, six seam defects, no git conflict | `merge_batch.sh` + `merge-gate.yml` — test the combined tree, not the lanes |
| Migration chain forked into two heads | `check_migration_chain.sh` — one head, and no migration cut from a stale parent |
| Two CI jobs sharing one Compose project name; one job's `down -v` destroying the other's database | `check_compose_name.sh` — a per-run, per-matrix identity or the gate fails |
| Pool demand 16 against a ceiling of 15; runner quota exhausted | the shared resources register in `AGENTS.md` — ceilings written down and owned |
| Undeclared file ownership, collisions found at merge time | `check_paths_owned.sh` — the declaration must cover the diff, not merely exist (63 of 221 did not) |
| Branch names that said nothing about their base | `check_branch_base.sh` — a name is a claim, and CI tests the claim |

One finding has no tool and cannot have one. A defect reached production because its test stub was built from the same wrong assumption as the code it tested — the two agreed with each other about something false. No quantity of additional tests written from that assumption could have caught it; only an external source of truth could. That limit is reported in `docs/RESEARCH.md` rather than papered over, because a kit claiming to catch everything is lying about the case that matters most.

## Prior art, stated plainly

**The merge gate here is a merge queue, and merge queues are old.** Speculative merging — test the queued changes as the group that would land, merge what passed together — has been running in the open in [Zuul](https://zuul-ci.org/docs/zuul/latest/gating.html) since OpenStack, and in Bors, Prow/Tide, [Mergify](https://mergify.com/blog/the-origin-story-of-merge-queues), Graphite, Aviator, and GitHub's own Merge Queue since. `merge_batch.sh` is that idea in a hundred lines of POSIX `sh`, for repositories that have none of them. **If you already run one, run it** — the finding holds either way: green lanes are not a green merge.

The same honesty applies to the rest. Alembic ships `alembic heads`. A unique `COMPOSE_PROJECT_NAME` per CI job is standard Docker advice. None of these mechanisms are inventions here.

What is not standard is the evidence: a production system built end-to-end by agents, with every coordination incident classified against a written codebook and the counts published. The multi-agent software-engineering literature is dominated by literature reviews and synthetic benchmarks, and says so itself — field evidence from real production systems is named as the open gap.

Independent work reaches a compatible conclusion from the opposite direction. [Destefanis & Aste (arXiv:2608.16801, August 2026)](https://arxiv.org/abs/2608.16801) instrument 1,902 benchmark runs of agent teams and find that shared files substitute for repeated one-to-one messaging, cutting output tokens by about 42% at eight agents, and that naming one agent as coordinator yields no reliable improvement. That is this case's claim — coordination can run through artifacts instead of dialogue — established experimentally where this repository establishes it in production.

## Who this is for

- **Solo developer-owners and small teams running agent swarms.** You have the most agents per human and the least platform infrastructure. This costs one `cp` and gives you the register, the vocabulary, and the gates.
- **Platform and DevOps engineers** whose repositories just started receiving agent-volume pull requests. Your merge queue already exists; the part it does not give you is the **shared resources register** — the largest incident category here.
- **Engineering managers and tech leads** deciding how far to delegate merge authority to a machine. The quality indicators in `docs/RESEARCH.md` are the quantitative basis for that decision: six defect escapes, five caught in staging, one reaching production.
- **QA engineers**, for the defect-finder classification and the structural limit above.

## What's in the kit

```
AGENTS.md.template          Rules of engagement for agents — paste into your repo root
.github/workflows/
  lane-gate.yml             Workflow: enforce the rules on every pull request
  merge-gate.yml            Workflow: test the combined result before anything lands
  kit-selftest.yml          Workflow: the kit checking itself (Linux + macOS)
scripts/
  merge_batch.sh            Build a batch of PRs and test them TOGETHER
  check_migration_chain.sh  One migration head; no migration cut from a stale parent
  check_compose_name.sh     Every CI job gets its own Docker Compose identity
  check_paths_owned.sh      PRs declare their paths — and the declaration must cover the diff
  check_branch_base.sh      Branch names must declare their base (feature/ fix/ hotfix/)
  strip_ai_trailers.sh      Strip "Co-Authored-By: <AI model>" traces (opt-in policy)
  pre-push-example          Client-side hook: ask the gate's questions before the push
  commit-msg-example        Client-side hook: strip AI trailers at write time (opt-in)
verify-kit.sh               Run every script against throwaway repos — 48 checks
experiments/                Reproduce the failures on demand — see experiments/README.md
examples/mini-repo/         A minimal repository with the kit already installed
docs/RESEARCH.md            The case study: methodology, 85-incident classification, limitations
```

Every script is POSIX `sh` — git, grep, sed, nothing else. Verify your copy before you trust it:

```bash
make verify             # 48 checks, exits non-zero on any failure
```

The numbers in this README are not asserted, they are recomputed. [`analysis/`](analysis/README.md) holds two standard-library scripts that regenerate every published figure from the corpus and re-derive the incident taxonomy independently of the original keyword list — including the three figures that come out **different**, and why. The corpus itself stays private; what it produces does not.

The checks that pay most are the ones that run *before* a merge, not after:

```bash
# does this lane's migration still hang off the current head of dev?
scripts/check_migration_chain.sh --changed origin/dev

# do these three PRs survive being merged together?
scripts/merge_batch.sh --base dev --test "pytest -q" 12 15 19
```

## Installation (5 minutes, level 1)

```bash
# from your repository root
cp -r path/to/swarm-agent-coordination/scripts scripts/
cp AGENTS.md.template AGENTS.md          # edit: change integration branch name if needed
mkdir -p .github/workflows
cp .github/workflows/lane-gate.yml .github/workflows/
cp .github/workflows/merge-gate.yml .github/workflows/   # edit: set TEST_COMMAND
```

Done. From this commit on, every pull request is mechanically checked for path ownership, branch-name honesty, migration parentage, and Compose identity.

Then install the hook. This is not optional polish, and the corpus is specific about why:

```bash
ln -sf ../../scripts/pre-push-example .git/hooks/pre-push
```

The migration chain forked **11 times** over the 35 days. **Not one of the eleven was a pull request merge commit.** They happened in integration-round merges, in `dev`→lane back-merges, and in one ordinary feature commit — moments when no pull request existed to gate. By the time each pull request opened, the chain had been repaired, so the gate saw a healthy chain every time, was right every time, and would have missed all eleven.

A gate that only runs on pull requests is a gate on the one moment the damage is already over. The hook runs at the moment it happens.

Then fill in the shared resources register in your new `AGENTS.md`. It ships with the case study's real ceilings as a worked example, and it is the section that repays maintenance most.

## Installation for AGENTS (level 2)

Agents don't read READMEs — they read `AGENTS.md` in the repo root. Copy `AGENTS.md.template` there (or merge it into an existing one). Every agent opened in that repository — Claude Code, Cursor, Hermes, Codex, Gemini CLI, or any other context-file-reading agent — finds its rules of engagement with no verbal briefing.

This is what makes the approach self-propagating: a repo that adopts the kit **carries its own rules**, so any agent — today's model or next year's — complies on arrival.

## Extending the kit (contributions welcome)

- **New incident categories** — found a coordination failure mode your swarm hit that the six categories don't cover? That is the most valuable contribution there is. It grows the part of this repository that cannot be written from opinion.
- **Data** — ran an agent swarm and classified its incidents with this codebook? A sanitized distribution enriches the taxonomy. One case is one case, and only more cases fix that.
- **Other platforms** — GitHub Actions today; GitLab CI, Jenkins, Buildkite ports welcome.
- **Other migration tools** — `check_migration_chain.sh` reads Alembic's parent pointers; Django, Rails and Flyway need two functions changed.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the branch model and what a new check has to do.

## Citation

The case study behind this repository is a master's thesis in Information Systems Management at Universitas Gunadarma (Rino Alfian, 2026), *Coordination Analysis of Multiple Artificial Intelligence Agents in Information System Development and the Quality of Their Work*. Publication pending; until then, cite this repository and `docs/RESEARCH.md`.

## License

MIT. Use, modify, and adopt freely.
