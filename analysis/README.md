# analysis/

Two scripts that recompute every published number from the exported corpus, and
a second, independent pass at the incident taxonomy.

```bash
make reproduce    # recompute the published numbers
make classify     # re-derive incidents -> data/incidents.json
make check        # both
```

Standard library only. A reproduction script that needs a dependency resolved
four years from now does not reproduce anything.

## What the corpus is, and what it is not

`export/` holds the machine artifacts of a 35-day production build: commits,
pull requests, issues, CI runs and jobs, and a migration-chain timeline. It is
**not** in this repository. It contains pull request prose from a real business's
private system, and it stays on the machine that produced it. `.gitignore`
refuses `export*/` and `raw*/` on purpose — one `git add -A` is all it takes.

What *is* published here is `data/incidents.json`: pull request numbers,
categories, and which rule fired. No prose, no paths, no identities.

## Why events rather than conclusions

The obvious way to publish this work is a table of labelled pull requests. It is
also the wrong way, because a label is a conclusion. Change the taxonomy and
every row has to be recoded by hand, and nobody can disagree with the
classification without redoing the whole study.

So the corpus keeps the events, `classify.py` keeps the rules, and
`data/incidents.json` is regenerated output. Proposing a rival taxonomy means
editing one file and rerunning, not asking anyone for access.

## Two kinds of rule

`classify.py` carries the original method and a second one beside it:

- **text rules** match what a human wrote in the pull request. This is what the
  published classification could see, and all it could see.
- **signal rules** compute from structured data, and fire whether or not anyone
  narrated the problem.

Every piece of evidence records which kind fired, and what it detected:

| kind | meaning |
|---|---|
| `narrated` | a human wrote that something went wrong |
| `exposure` | the pull request touched a shared resource — nothing broke, but it was in a position where something could |
| `failure` | the resource actually broke: the chain forked, the work was undone |

Keeping `exposure` separate from `failure` matters. Counting exposure as
incident is what inflates a shared-resource category: most pull requests that
touch a migration do so uneventfully.

## What the second pass found

**80 of the 85 published pull requests were found again** by rules written
without sight of the original keyword list. The taxonomy is operationalizable by
someone else, which is the claim worth testing.

Three results were not in the original analysis, and two of them are corrections
rather than additions.

### Runner contention is not a property of a pull request

The published count is 2. The measurement is that the median pull request waited
**eleven minutes** for a runner and 155 of 226 waited over five.

Three attempts at a per-PR runner rule reached precision 0.01, 0.02, and 0.02.
The threshold was never the problem. Queueing was a background condition for
thirty-five days, so any per-PR rule either fires on two thirds of the corpus or
becomes an arbitrary cut through a smooth distribution.

The published 2 does not count how often runners ran out. It counts how often
somebody wrote it down.

So the rule was removed and contention is reported at corpus level, where it
lives. Attributing a shared-resource shortage to the individual work that
happened to be queued behind it is the same mistake the shortage is made of.

### No migration chain fork happened in a pull request

The chain forked 11 times. **None of the eleven occurred in a pull request merge
commit.** They happened in local integration-round merges, in `dev`→lane
back-merges, and in one ordinary feature commit — moments when no pull request
existed to gate.

By the time each pull request opened, the chain had been repaired: the corpus
ends at a single head with no fork. A gate that only runs on pull requests sees
a healthy chain every time, and is right every time, and would still have missed
all eleven.

This is the strongest argument in the corpus for the client-side hook
(`scripts/pre-push-example`) over the CI gate alone. The fork exists between
pushes, not at review time.

### Declaring ownership is not the same as declaring it correctly

221 pull requests carried a `## Paths owned` block. In **68 of them the
declaration did not cover the diff**, leaving 546 files touched but undeclared.

The published figure — a declaration present in 99 of the last 100 pull requests
— measures the ritual. The corpus says the gap between ritual and substance is
**31%**.

`scripts/check_paths_owned.sh` now enforces the substance, and this measurement
is what calibrated it.

> **Correction.** The first version of this analysis reported 94 violations and
> 914 undeclared files. That count was wrong, and it was wrong in the direction
> that flattered the finding. Its parser read only bullet lists and compared
> paths literally, so it missed declarations written as markdown tables —
> common in this corpus — and treated every glob, brace list and directory
> prefix as a non-match. Fixing the parser moved the count from 94 to 68.
>
> The two implementations are now cross-checked against each other: a harness
> replays all 221 declarations through both `check_paths_owned.sh` and
> `declared_paths()`/`covered()` here, and they agree on every one. Two
> implementations agreeing is weak evidence when one was derived from the
> other, which is why the shell version was written first and the Python
> brought to match it, not the reverse.

## Where the numbers still disagree

`reproduce.py` prints 26 metrics. Three disagree, all of them feature cycle time:

| metric | published | recomputed |
|---|---|---|
| median | 4.3 h | 5.0 h |
| mean | 9.7 h | 13.9 h |
| max | 73.1 h | 143 h |

One cause: the platform's issue-link graph did not survive extraction, so links
are recovered from the closing keyword in pull request bodies. That recovers 172
pairs across the same **140** pull requests the original reported — the pull
request count matches exactly, the pair set is wider, and the extra pairs skew
long.

The conclusion holds in direction: cycle time is measured in hours, not days.
The disagreement is a difference of linking method and is left standing rather
than tuned away. A reproduction script whose numbers always agree is not
reproducing anything either.
