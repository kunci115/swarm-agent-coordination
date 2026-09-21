# swarm-kit roadmap

Goal: turn `swarm-agent-coordination` from a copy-paste kit into a tool people try in one command and keep using.

Funnel: **audit (free, zero install) → `swarm-kit init` → lease + planner → merge safely**.
Viral loops: README badge from every audit, and opt-in anonymized incident data that improves the classifier.

Hook for all launch material: *git caught 1 of 85 coordination incidents.*

---

## Rules for agents working on this roadmap

This repo eats its own dog food. Follow `AGENTS.md` first; this section adds roadmap-specific rules.

1. **One lane per task.** Branch name `feature/<task-id>-<slug>` cut from `dev`. Never work on two tasks in one branch.
2. **Declare owned paths** in the PR description (`Owned paths:` block). Only touch paths listed for your task below. If you need a path owned by another task, stop and open an issue instead.
3. **No network in tests.** Every test runs offline against fixtures in `test/fixtures/`.
4. **Zero runtime dependencies** unless the task says otherwise. Node >= 20, ESM, `node:test`.
5. **Done means:** acceptance criteria below pass, `npm test` is green, README section updated, PR opened against `dev`.
6. Do not edit `docs/RESEARCH.md` or the published figures. The audit may reuse the codebook; it must not change the research numbers.

---

## Phase 1: `swarm-audit` (week 1): entry point

Owned path: `packages/swarm-audit/**`

A prototype of this phase is already written (see "Status" at the bottom). Remaining tasks:

| ID | Task | Acceptance criteria |
|----|------|---------------------|
| ~~A1~~ | ~~Replace `src/codebook.default.json` with rules derived from `analysis/`~~ **done** | Scored by `tools/corpus-check.mjs`: finds 80 of the 85 labelled pull requests at the default confidence floor, the bar `analysis/classify.py` set. Acceptance was restated: reproducing the *published counts* would mean reproducing one particular keyword list, and the corpus shows that list contains false positives. |
| ~~A2~~ | ~~Live GitHub fetch hardening~~ **done** | Already satisfied by the prototype and covered by tests: paginates and stops on a short page, distinguishes a rate limit from a plain 403 and reports the reset time, names `GITHUB_TOKEN` on 404, returns empty for a repo with no pull requests. |
| A3 | Structural signals beyond keywords | Detect supersede chains from closed-unmerged PRs referenced by later PRs; detect migration files touched by 2+ open PRs (needs `/pulls/{n}/files`, behind `--deep` flag) |
| ~~A4~~ | ~~Recommended gate per category in the report~~ **done** | Each flagged row links every script and workflow it names, and carries a copy-paste install line. A category with no hits shows neither. The report also states what prose cannot show, with the two numbers that make the point. |
| A5 | Publish | `npx swarm-audit owner/repo` works from npm; version 0.1.0 tagged |

## Phase 2: hosted audit page (week 1–2)

Owned path: `apps/audit-web/**`

| ID | Task | Acceptance criteria |
|----|------|---------------------|
| W1 | Static page: paste repo URL → run audit in the browser via GitHub API (unauthenticated, public repos only) | Reuses `packages/swarm-audit/src/classify.mjs` unchanged; report renders same as CLI HTML |
| W2 | Shareable result URL + badge endpoint | `/badge/<owner>/<repo>.svg` returns the badge; result page has "copy badge markdown" |
| W3 | Deploy on GitHub Pages or Cloudflare Pages | Public URL in main README |

## Phase 3: `swarm-kit init` (week 2)

Owned path: `packages/swarm-kit/**`

| ID | Task | Acceptance criteria |
|----|------|---------------------|
| K1 | Stack detection | Detects Alembic, Prisma, Django migrations, Rails, Flyway, Docker Compose, GitHub Actions / GitLab CI |
| K2 | Install only relevant gates | Copies matching `scripts/` + workflows, renders `AGENTS.md` from template with detected integration branch |
| K3 | `--from-audit report.json` | Installs exactly the gates for categories found by the audit |
| K4 | Pre-push hook installed by default | `.git/hooks/pre-push` symlinked; `--no-hook` to skip |
| K5 | Claude Code plugin + skill | `claude plugin install swarm-kit` works; skill tells the agent to run `init` and fill the shared resources register |
| K6 | Port `check_migration_chain.sh` to Prisma, Django, Rails, Flyway | Each port has a throwaway-repo test in `verify-kit.sh` |

## Phase 4: continuous audit as a GitHub App (week 3)

Owned path: `apps/github-app/**`

| ID | Task | Acceptance criteria |
|----|------|---------------------|
| G1 | Label each new PR with incident categories on open/sync | Uses the same classifier; labels prefixed `swarm:` |
| G2 | Weekly summary issue | Incident rate trend, top category, suggested gate |

## Phase 5: lease server + planner (week 3–4): the differentiator

Owned paths: `packages/swarm-lease/**`, `packages/swarm-planner/**`, `scripts/**`

| ID | Task | Acceptance criteria |
|----|------|---------------------|
| L1 | MCP server exposing `claim`, `release`, `list` for named resources (migration head, ports, DB pool slots, CI runner slots) | Two agents claiming the same resource: second waits or gets a clear refusal |
| L2 | Leases stored as a file in the repo (`.swarm/leases.json`) so coordination stays artifact-based | Works with no server process for read-only checks; CI gate fails if a PR touches a resource it did not lease |
| L3 | Resource ceilings read from the shared resources register in `AGENTS.md` | Claim beyond ceiling is refused |
| P1 | Planner: given open issues, predict overlapping files/resources | Uses issue text + past PR file history; outputs suggested lanes |
| P2 | `swarm-planner --assign` writes lane labels to issues | Issues known to touch the same file land in the same lane |

### Merge authority (M-series)

Whether a machine may land work is the managerial question the case study was
built to ask, and its answer there was *no*: across 229 pull requests the
corpus records one distinct merger and zero self-merges. So the kit must not
ship a `--auto-merge` flag. A flag is a preference living in one person's shell
history; what belongs here is the same thing as every other rule in this kit —
**the authority written down as an artifact, and refused by default.**

One constraint is not negotiable. If the policy gates on a pull request's own
green checks, it rebuilds the exact failure this research documents: ten
independently-green lanes producing six defects. It gates on the **combined
result** or it does not ship.

| ID | Task | Acceptance criteria |
|----|------|---------------------|
| M1 | `.swarm/merge-policy.yml` — declared conditions under which an automated merge is authorized | Absent or unparseable policy means refuse. Every condition is mechanically checkable; none rests on an agent's judgement |
| M2 | `scripts/merge_if_authorized.sh` — runs `merge_batch.sh`, evaluates the policy, merges or stops | Refuses unless: the combined-result gate is green; the merger identity differs from every author in the batch; no pull request touches a `requires_human` path; batch size within the ceiling; no category the repo marks `manual_review` was flagged by `swarm-audit`. A refusal names which condition failed |
| M3 | The merge commit carries its own evidence | Message records which gate ran, the batch it covered, and the result — so a machine merge is more auditable than a human one, not less |

Out of scope, and worth stating so nobody files it as a bug: none of this can
grant an agent permission its own harness withholds. A repository declares
*this merge is authorized*; a harness declares *this agent may merge*. Two
questions, two owners, and a repo should not be able to hand an agent a
capability its operator has not.

## Launch checklist (after Phase 2)

- [ ] Rewrite main README: hook stat on line 1, GIF of an audit report, one command to try
- [ ] Audit 15–20 public repos with heavy agent PR volume; publish aggregate numbers only, or named results with maintainer permission
- [ ] Posts: Show HN, r/ClaudeAI, X, dev.to, Indonesian dev communities
- [ ] Data contribution form: anonymized category distribution from `swarm-audit --export-anon`

## Success metrics

Audits run, badges installed, anonymized datasets contributed. Stars follow.

---

## Status

- Phase 1 prototype written and tested offline: CLI, keyword classifier, JSON + HTML report, SVG badge, `--from-file` offline mode.
- **A1, A2 and A4 done.** A3 (`--deep` structural signals) and A5 (publish) remain in Phase 1.
- The codebook is derived from `analysis/` and scored against the corpus (`make audit`): 80 of 85 labelled pull requests found, 11 unit tests green offline. Package moved to the roadmap's owned path `packages/swarm-audit/`.
- Two roadmap assumptions were corrected by the scoring, and later tasks should carry the correction: the reference set contains probable false positives, so "reproduce the published counts" is the wrong acceptance criterion; and `runner_queue` cannot be measured from pull request text at all, which is an argument for A3 (`--deep`) rather than for more keywords.
- Note for every lane on this roadmap: rule 2 says `Owned paths:`, but the gate in `lane-gate.yml` requires a `## Paths owned` heading and refuses anything else. Use the heading.
