# Swarm Agent Coordination

[![kit-selftest](https://github.com/kunci115/swarm-agent-coordination/actions/workflows/kit-selftest.yml/badge.svg)](https://github.com/kunci115/swarm-agent-coordination/actions/workflows/kit-selftest.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Rules of engagement so multiple AI agents can work in one repository without destroying each other — for the humans operating them, and for the agents themselves (Gemini, Claude, ChatGPT, Hermes, Cursor, or any agent that reads `AGENTS.md`).**

Built from one production case study: over 35 days, a swarm of agents built a real information system (a workshop management system, no inter-agent communication) — 1,417 commits, 229 pull requests, 275 issues, 5,787 automated tests. Every coordination incident was classified: 85 pull requests (37%) showed incident indications, concentrated on dependencies unrepresented in any artifact (database migration chains, connection pool ceilings, runner quotas). This kit is the set of patterns that caught them.

> Full research: DSR case study, 6 incident categories, 6 work-quality indicators — see `docs/RESEARCH.md`.

## The problem this solves

When several agents work in parallel on one repo:

- They edit the same files and **git reports no conflict**, while the semantics collide
- They **drain shared resources nobody owns** (database connection pools, CI runner quotas, service ports, Docker Compose project names)
- **Nobody owns responsibility**, because nobody declared it
- Merge quality is unknown, because **each lane tested only itself**

The result is seam defects landing behind a wall of green checkmarks. In the case study, one ten-lane merge produced six defects, none visible from inside any lane.

## Every rule traces to an incident, and every incident to a tool

This is the whole kit in one table. The left column is what actually went wrong over 35 days; the right column is what now refuses it mechanically.

| What went wrong | Weight in the case | What refuses it now |
|---|---|---|
| Ten lanes merged together produced six seam defects; git reported no conflict on any of them | the headline incident — 4 of the 6 would have reached `dev` | `merge_batch.sh` + `merge-gate.yml` — test the combined tree, not the lanes |
| Two lanes wrote a migration against the same parent; the chain forked | 40 of 85 flagged PRs touched shared DB resources — the largest category | `check_migration_chain.sh` — one head, and no migration cut from a stale parent |
| Two gate jobs shared one Compose project name; one job's `down -v` destroyed the other's database | latent for weeks, surfaced when runner count rose | `check_compose_name.sh` — a per-run, per-matrix identity or the gate fails |
| Connection pool demand 16 against a ceiling of 15, every lane inside a ceiling it could see | 2 incidents, hours of confused debugging | the shared resources register in `AGENTS.md` — ceilings written down and owned |
| Eight lanes stalled on an exhausted runner quota; nine PRs had been green since the previous day | 2 incidents | the same register: "expect queueing, don't kill queued jobs" |
| Undeclared file ownership, collisions found at merge time | supporting | `check_paths_owned.sh` — declare `## Paths owned` on the first push |
| Branch names that said nothing about their base | 0 incidents — prevented | `check_branch_base.sh` — a name is a claim, and CI tests the claim |

The one textual merge conflict in 229 pull requests was **preempted**, not resolved: nine issues known to touch the same file were assigned to one lane at planning time. Coordination through artifacts works before the fact, not only after it.

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
  check_paths_owned.sh      PRs must declare which file paths they own
  check_branch_base.sh      Branch names must declare their base (feature/ fix/ hotfix/)
  strip_ai_trailers.sh      Strip "Co-Authored-By: <AI model>" traces (opt-in policy)
  pre-push-example          Client-side hook: ask the gate's questions before the push
  commit-msg-example        Client-side hook: strip AI trailers at write time (opt-in)
verify-kit.sh               Run every script against throwaway repos — 38 checks
examples/mini-repo/         A minimal repository with the kit already installed
docs/RESEARCH.md            The case study: methodology, 85-incident classification, quality indicators
```

Verify your copy works before you trust it:

```bash
sh verify-kit.sh        # 38 checks, exits non-zero on any failure
```

The checks that matter most are the ones you run *before* a merge, not after:

```bash
# does this lane's migration still hang off the current head of dev?
scripts/check_migration_chain.sh --changed origin/dev

# do these three PRs survive being merged together?
scripts/merge_batch.sh --base dev --test "pytest -q" 12 15 19
```

## The principle

Every rule here expands one principle: **coordination through artifacts, not conversation.** Agents don't talk to each other. They write rules to each other through shared artifacts — ownership declarations, branch conventions, quality gates, merge policies — and behave correctly as long as those artifacts are explicit and mechanically enforced.

Three rules get violated the most, so start here:

1. **A lane never merges its own pull request.** The quality gate is the merge, not the green checkmark.
2. **Declare the file paths you own (`## Paths owned`) in your first push.** Collisions get found at merge time unless someone declares them earlier.
3. **Name your branch for its base** (`feature/`, `fix/`, `chore/`, `docs/` from the integration branch; `hotfix/` from `main`) — and let a script verify it. A rule nothing tests is only a convention; this makes it a fact.

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

One more step worth the thirty seconds, because the cheapest place to catch any of this is before the push leaves your machine:

```bash
ln -sf ../../scripts/pre-push-example .git/hooks/pre-push
```

## Installation for AGENTS (level 2)

Agents don't read READMEs — they read `AGENTS.md` in the repo root. Copy `AGENTS.md.template` to the root as `AGENTS.md` (or merge it into an existing one). Every agent opened in that repository — Claude Code, Cursor, Hermes, Codex, or any other context-file-reading agent — will find its rules of engagement there, with no verbal briefing needed.

This makes the framework self-propagating: a repo that adopts the kit **carries its own rules**, so any agent — today's or next year's model — complies immediately.

## Extending the kit (contributions welcome)

- **New incident categories**: found a new coordination failure mode in your agent swarm? Open a PR adding the pattern to the classification scheme in `docs/RESEARCH.md`.
- **Other platforms**: currently uses GitHub Actions. Ports of `lane-gate.yml` to GitLab CI / Jenkins / others are welcome.
- **Other agent harnesses**: the example assumes worktree-based agents. Variations for other harnesses are welcome.
- **Data**: if you run an agent swarm and classify its incidents with this kit, share your distribution (sanitized) — it enriches the shared taxonomy.

## License

MIT. Use, modify, and adopt freely.
