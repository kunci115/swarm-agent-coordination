# swarm-audit

Audit a repository's pull request history for multi-agent coordination incidents.

```sh
npx swarm-audit owner/repo            # public repo
GITHUB_TOKEN=... npx swarm-audit owner/private-repo
npx swarm-audit --from-file prs.json  # offline, local PR export
```

Outputs `report.html`, `report.json`, and `badge.svg` in `./swarm-audit-report/`.

Add the badge to your README:

```md
![coordination incidents](./swarm-audit-report/badge.svg)
```

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

Both need the gates in `scripts/` — a pre-push hook, not a report — to be seen
properly. The audit is the thing that tells you to install them.

Hits carry a confidence level; the default floor is `medium`. Treat results as
leads, not verdicts.

Tests run offline: `npm test`.
