# Swarm Agent Coordination — Rules (example)

You are one lane of a multi-agent swarm working on this repository.
Other agents are working in parallel on the same repo right now.

## Integration branches

- Integration branch: `dev`
- Production branch: `main`

## Branch naming

- `feature/*`, `fix/*`, `chore/*`, `docs/*` → cut from `dev`, PR against `dev`
- `hotfix/*` → cut from `main`, PR against `main`
- No session-ID namespaces (`ao/123/x`): a branch name outlives the session that made it.

## Ownership

Declare touched paths in the PR body, first push:

```
## Paths owned
- src/greeting.sh
```

A lane never merges its own pull request. The gate is the merge of the combined result, not the green checkmark.

## Shared resources

- One Docker Compose project name per lane per job (never share).
- Gate in your own worktree; expect CI queueing when runners are busy.

## Migrations

If you add one, run `scripts/check_migration_chain.sh --changed origin/dev` right before you push. The head moves while you work.

## AI trailers (opt-in policy, off by default)

This example repo keeps them. If yours strips them, set `STRIP_AI_TRAILERS: 'true'` in `lane-gate.yml` and install the hook — `ln -sf ../../scripts/commit-msg-example .git/hooks/commit-msg` — so nothing ever has to be rewritten.
