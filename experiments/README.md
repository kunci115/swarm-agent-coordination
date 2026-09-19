# experiments/

The case study is one observation. These are attempts to produce the same
failures on demand, in a setting small enough to repeat.

```bash
sh experiments/migration-collision/run.sh --condition stale-green
sh experiments/migration-collision/run.sh --condition re-gated
```

Each run prints one JSON line. A grid of them is a dataset.

## Why version control is the whole point

The published benchmark work on multi-agent coordination measures what happens
*inside* a run: who messaged whom, which files were read, how many tokens it
cost. The best of it — Destefanis & Aste, [arXiv:2608.16801](https://arxiv.org/abs/2608.16801),
1,902 runs — has no version control, no branches, and no merge step.

That is not an oversight, it is a scope. But it means an entire class of failure
is invisible to it by construction: the defect that appears only when two
correct pieces of work are combined. In the case study behind this kit, that
class was the largest thing that went wrong, and git reported no conflict for
any of it.

So these experiments give every lane a worktree, take their output as branches,
and grade twice — each lane alone, then the merged tree. **The gap between those
two gradings is the measurement.**

## migration-collision

Two lanes, two briefs, neither mentioning the other. Bookings need a `notes`
column; jobs need a `priority` column. Both require a migration, and there is
one migration chain.

| condition | what differs | result |
|---|---|---|
| `stale-green` | both lanes cut from the same head, never re-gated against the base they land on | both lanes green, **merge red**, no textual conflict |
| `re-gated` | the second lane cuts after the first has landed | both lanes green, merge green |

`stale-green` is not a strawman: a pull request's checks do not re-run when its
base moves, so a branch sits green against a base that changed underneath it.
That gap is what is being measured.

`re-gated` is the negative control, and it is the more important of the two. An
instrument that only ever reports a defect measures nothing. Both conditions
produce two green lanes; the only difference is *when* the second lane cut its
migration, and the grading flips on that alone.

## Status: instrument validated, agents not yet attached

The lanes are currently **scripted** — `lanes/lane.sh` does what a competent
agent would do, deterministically. Five runs per condition, identical results,
no variance.

This is deliberate sequencing rather than a shortcut. An instrument has to be
trusted before it is pointed at anything expensive, and debugging a grader and a
language model simultaneously teaches nothing about either. With scripted lanes
the variance is zero by construction, so any variance that appears later belongs
to the agents, which is the thing worth measuring.

The interface between a lane and the grader is a git branch. Swapping
`lanes/lane.sh` for a real agent changes nothing else.

### What is still unknown

- **Cost.** Every figure anyone has offered for this, including mine, is a
  guess until one real agent run is measured. That measurement is the next step
  and it needs API access.
- **Whether agents reproduce the collision at all.** A real agent might notice
  the other lane's migration, or might not — and *that rate* is the finding,
  not an assumption to be built on.
- **Variance.** Destefanis & Aste found the same pinned configuration giving
  incompatible results across collection sessions. Ten runs per cell may not be
  enough. The scripted baseline gives a floor to compare against.

## Files

```
migration-collision/
├── task.md          the two briefs, and what the grader measures
├── fixture.sh       builds the repository the lanes work in
├── lanes/lane.sh    a scripted stand-in for one agent
├── grade.sh         grades each lane alone, then the merged result
└── run.sh           one run, end to end, one JSON line out
```

POSIX `sh` throughout, like the rest of the kit: git, grep, sed, awk.
