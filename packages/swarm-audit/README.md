# swarm-audit

Audit a repository's pull request history for multi-agent coordination incidents.

```sh
npx swarm-audit owner/repo            # public repo
GITHUB_TOKEN=... npx swarm-audit owner/private-repo
npx swarm-audit --from-file prs.json  # offline, local PR export
```

## Where the result goes

`./swarm-audit-report/` in the directory you ran from, holding `report.html`,
`report.json` and `badge.svg`. The run prints a `file://` link, which most
terminals make clickable, and the badge markdown ready to paste:

```
Report: file:///Users/you/project/swarm-audit-report/report.html
Badge:  swarm-audit-report/badge.svg

Paste into your README:
  ![coordination incidents](swarm-audit-report/badge.svg)
```

`--open` launches the report in your browser instead of leaving you a path.

That directory is usually inside someone's repository, so it writes a
`.gitignore` containing `*` into itself. An audit should not turn into an
accidental commit. Delete that file if you want to check the report in
deliberately.

## Where the codebook comes from

`src/codebook.default.json` is derived from `analysis/classify.py`, the rule set
written against a 35-day production corpus in which every coordination incident
was classified by hand. Scored against that corpus's 85 labelled pull requests,
it finds **80 of them** at the default confidence floor — written without sight
of the original keyword list, which is the point: the taxonomy is
operationalizable by someone other than its author.

`make audit` runs the unit tests and, when the corpus is present, that scoring.

Five labelled pull requests are not found, and four of them appear to be
mislabels in the reference set rather than misses here: one carries no rework
vocabulary at all despite a `rework` label, and three rest on a single loose
word (`database`, `queue`) in an otherwise unrelated pull request. Chasing 85 of
85 would mean fitting noise. The fifth, #99, is a genuine under-detection: its
database vocabulary is generic (`alembic`, `migration`) and those terms sit in
`weak`, which counts only in a title at `medium`. `--min-confidence low` finds it.

## `--deep`: what the text never says

```sh
npx swarm-audit owner/repo --deep
```

Two signals computed from what pull requests *did*:

- **Migration files open in two pull requests at once.** Two lanes writing a
  migration against the same parent is the mechanism behind the largest
  incident category in the case study. Each lane is internally consistent, each
  lane's tests pass, and git reports no conflict because the two lanes wrote
  different files.
- **A reference to work closed without merging.** That is a supersede chain
  whether or not anyone used the word. A number in a body is just an integer —
  in the corpus three quarters of them point at issues — so each one is looked
  up rather than assumed.

Structural hits are never filtered by `--min-confidence`. The confidence ladder
describes how sure we are about a *word*; a measurement is not a reading of a
word.

Scored on the corpus, the migration signal flags 8 pull requests and **2 of them
say nothing about it in their own text** — neither carries a label from the
original keyword pass. One of those two is independently known to be a real
chain fork from the git history. That is the whole argument for `--deep`: the
failures that matter most are the ones nobody wrote down.

It costs about one API request per pull request, which is why it is not the
default. Unauthenticated requests are capped at 60 per hour, so `--deep` on a
repository with more pull requests than that needs a token:

```sh
GITHUB_TOKEN=... npx swarm-audit owner/repo --deep
```

The run checks the remaining budget before spending it and refuses up front
rather than failing halfway, because a half-finished run leaves you with nothing
and an hour to wait.

## What it reports on an ordinary repository

Measured today, from a clean install against the live API, unauthenticated:

| repository | incident rate |
|---|---|
| `sindresorhus/got` | 0% of 60 |
| `vercel/swr` | 2% of 60 |
| `kunci115/swarm-agent-coordination` | **60% of 10** |

The first two are the point: a human-maintained repository scores near zero, so
a number from this tool means something. The third is the failure mode worth
knowing before you trust a score — **this repository is about coordination
incidents, so its pull requests are full of the vocabulary.** The classifier
cannot tell a pull request that *caused* a seam defect from one that *discusses*
them.

Any repository whose subject matter is testing, merging, migrations or CI will
read high for the same reason. Read the flagged list, not just the percentage.

## What this cannot see

The audit reads pull request prose, so it measures **how often a failure was
written about**. Two categories under-report for structural reasons, and the
corpus is specific about both:

- **Runner contention** is a property of the CI system, not of a pull request.
  In the corpus the median pull request waited eleven minutes for a runner and
  155 of 226 waited over five, while exactly **2** narrated it. A number from
  this tool counts narration.
- **Migration chain forks** happen between pushes and are usually repaired
  before review, so no pull request ever mentions them. In the corpus the chain
  forked 11 times and **none** of the eleven was a pull request merge commit.

`--deep` closes part of the first gap and none of the second: a fork that was
repaired before either pull request opened leaves no overlap to find. Both still
need the gates in `scripts/` — a pre-push hook, not a report. The audit is the
thing that tells you to install them.

Hits carry a confidence level; the default floor is `medium`. Treat results as
leads, not verdicts.

Tests run offline: `npm test`.
