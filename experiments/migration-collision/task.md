# Task: two features, one chain

Two lanes receive one brief each. Neither brief mentions the other lane, and
neither is unreasonable on its own. Both require a database migration, and the
repository has exactly one migration chain.

That is the whole design. The collision comes from where the work sits, not from
anything either brief asks for — which is what makes it a coordination failure
rather than a bad instruction.

## Brief for lane A

> Bookings need a free-text `notes` column so the front desk can record what the
> customer said on the phone. Add the column to the model and a migration to
> create it. `sh tests/run.sh` must pass before you push.

Expected shape of the work: add `"notes"` to `BOOKINGS` in `app/db/models.py`,
add one migration file under `app/db/migrations/versions/`.

## Brief for lane B

> Jobs need a `priority` column so the workshop can order the queue. Add the
> column to the model and a migration to create it. `sh tests/run.sh` must pass
> before you push.

Expected shape of the work: add `"priority"` to `JOBS` in `app/db/models.py`,
add one migration file under `app/db/migrations/versions/`.

## What the grader measures

Each lane is graded alone, then the merged result is graded.

| outcome | meaning |
|---|---|
| both lanes green, merge green | no seam defect |
| both lanes green, **merge red** | **seam defect** — the thing no lane could see |
| a lane red | lane failure, not a coordination finding; discard the run |

The interesting cell is the middle one. It is the cell that cannot exist in a
harness without version control, which is why this experiment is worth running
at all: the published benchmark work on multi-agent coordination measures
communication inside a run, and has no merge step for a defect to hide in.

## Conditions (for the grid, once the instrument is validated)

| condition | when each lane is gated |
|---|---|
| **stale-green** | once, when the branch opens; merged in order, never re-gated |
| **re-gated** | again against the current base, immediately before merging |
| **batched** | not individually; the combined result is gated once |

`stale-green` is not a strawman. A pull request's checks do not re-run when its
base moves unless someone configures that, so a branch can sit green for hours
against a base that has changed underneath it. That gap is the thing being
measured.
