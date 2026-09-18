# Swarms in production fail at coordination, not at coding. This kit is the fix.

**swarm-agent-coordination** — rules of engagement + mechanical enforcement for repositories where multiple AI agents (Claude Code, Cursor, Codex, Hermes, Gemini CLI, or any agent reading `AGENTS.md`) work in parallel.

From a 35-day production case study: 1,417 commits, 229 PRs, one human orchestrator, zero inter-agent communication. 85 coordination incidents classified. The six failure modes that dominated — undeclared file ownership, migration chain forks, connection pool ceilings, runner quotas, shared Compose identities, and merge-quality blind spots — each map to one mechanical rule in this kit.

The rules:

1. A lane never merges its own PR — the combined result is the gate, not the green checkmark
2. Every PR declares `## Paths owned` in its first push
3. Branch names declare their base (`feature/ fix/ chore/ docs/` ← integration; `hotfix/` ← main) — verified by script
4. Shared resources (DB pools, runners, Compose names) get a register with ceilings
5. AI attribution trailers are stripped before push

Full case study (6-category incident taxonomy, quality indicators, limitations): [`docs/RESEARCH.md`](docs/RESEARCH.md)

Install in 5 minutes: copy `scripts/`, drop `lane-gate.yml` into `.github/workflows/`, paste `AGENTS.md.template` as `AGENTS.md`. Agents reading context files comply immediately; humans get CI enforcement; you get an incident taxonomy you can measure.

MIT. Contributions welcome — especially new incident categories from your own swarms.
