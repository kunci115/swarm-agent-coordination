# Mini example repo

A minimal working example of the kit installed on a tiny project.

```
mini-repo/
├── AGENTS.md                # the template, filled in for this example
├── CONTRIBUTING.md          # the rules, in human-facing prose
└── .github/workflows/
    └── lane-gate.yml        # symlink-equivalent of the kit's gate
```

## Try it locally

```bash
# 1. cut a lane correctly
git checkout dev && git pull
git checkout -b feature/add-greeting        # name declares base: dev

# 2. do your work, declare ownership in the PR body
#    ## Paths owned
#    - greeting.sh

# 3. check yourself before pushing
../scripts/check_branch_base.sh
../scripts/strip_ai_trailers.sh --check dev..HEAD

# 4. open the PR against dev — then stop. Someone else merges it.
```

## Try the failure modes

```bash
git checkout -b my-branch dev                # no base declared -> gate refuses
git checkout -b hotfix/quick dev             # hotfix/ must come from main -> refuses
# forget ## Paths owned in the PR body       # gate refuses on PR
```

Each refusal is the mechanical enforcement that turns a convention into a fact.
