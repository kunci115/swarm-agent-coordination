# Swarms in production fail at coordination, not at coding. This kit is the fix.

**swarm-agent-coordination** — rules of engagement + mechanical enforcement for repositories where multiple AI agents (Claude Code, Cursor, Codex, Hermes, Gemini CLI, or any agent reading `AGENTS.md`) work in parallel.

From a 35-day production case study: 1,417 commits, 229 PRs, one human orchestrator, zero inter-agent communication. 85 coordination incidents classified. The six failure modes that dominated — undeclared file ownership, migration chain forks, connection pool ceilings, runner quotas, shared Compose identities, and merge-quality blind spots — each map to one mechanical rule in this kit.

The rules — four, because every rule costs every agent attention forever:

1. A lane never merges its own PR — the combined result is the gate, not the green checkmark. `merge_batch.sh` builds that combined result and tests it.
2. Every PR declares `## Paths owned` in its first push
3. Branch names declare their base (`feature/ fix/ chore/ docs/` ← integration; `hotfix/` ← main) — verified by script
4. Shared resources (DB pools, runners, Compose names, migration chains) get a register with ceilings — and `check_migration_chain.sh` / `check_compose_name.sh` enforce the two that did the most damage

Stripping AI attribution trailers is shipped too, as an opt-in repo policy rather than a rule: no coordination incident in the case study involved one, and a rule that traces to no incident does not belong beside four that do.

Full case study (6-category incident taxonomy, quality indicators, limitations): [`docs/RESEARCH.md`](docs/RESEARCH.md)

Install in 5 minutes: copy `scripts/`, drop `lane-gate.yml` into `.github/workflows/`, paste `AGENTS.md.template` as `AGENTS.md`. Agents reading context files comply immediately; humans get CI enforcement; you get an incident taxonomy you can measure.

MIT. Contributions welcome — especially new incident categories from your own swarms.
