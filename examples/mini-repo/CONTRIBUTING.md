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

## AI trailers

Strip `Co-Authored-By: <AI>` trailers before pushing:
`scripts/strip_ai_trailers.sh dev..HEAD`
