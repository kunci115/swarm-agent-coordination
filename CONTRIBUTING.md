# Contributing

This repository runs on the rules it ships. If you have read `AGENTS.md.template`, you already know them — they apply here too, which is the only honest way to publish a kit like this.

## Branch model

- Integration branch: **`dev`** — the default branch, and where every pull request lands.
- Production branch: **`main`** — promoted from `dev` by fast-forward, never by a pull request.
- Cut `feature/`, `fix/`, `chore/`, `docs/` from `dev`. Cut `hotfix/` from `main`.
- A branch name is a claim about where it was cut from, and `lane-gate.yml` tests the claim. A name that declares no base is refused.

## Before you push

```bash
sh verify-kit.sh      # 33 checks; must pass
```

Every script is POSIX `sh` with no dependencies beyond git, grep, and sed — CI runs `sh -n` over all of them on Linux and macOS. If you reach for `bash`, `yq`, or Python, the kit stops being installable in one copy, so please don't.

Your pull request body needs a `## Paths owned` section listing the files it touches. The gate refuses it otherwise, and that refusal is the feature.

## What's most welcome

- **New incident categories.** Found a coordination failure mode your swarm hit that the six categories in `docs/RESEARCH.md` don't cover? That is the most valuable contribution there is — it grows the taxonomy, which is the part of this repo that can't be written from opinion.
- **Data.** If you ran an agent swarm and classified its incidents with this kit, a sanitized distribution enriches the shared picture. One case is one case; the limitation is stated plainly in `docs/RESEARCH.md` and only more cases fix it.
- **Ports.** `lane-gate.yml` and `merge-gate.yml` are GitHub Actions. GitLab CI, Jenkins, Buildkite equivalents are wanted.
- **Other migration tools.** `check_migration_chain.sh` reads Alembic's `revision` / `down_revision` today. The logic is only parent pointers — Django, Rails, and Flyway support means changing `rev_of()` and `downs_of()` and nothing else.

## What a new check has to do

Every check in `scripts/` follows the same shape, and a new one should too:

1. **Skip cleanly when it doesn't apply.** Exit 0 with a `SKIP:` line — an adopter without migrations should never be blocked by a migration check.
2. **Have a local mode.** Asking before the push is cheaper than failing after it. Wire it into `scripts/pre-push-example`.
3. **Say what it cannot do.** `check_paths_owned.sh` states that it only verifies the section exists; `check_compose_name.sh` states that it is a grep and not a YAML parser. Overclaiming is worse than a narrow check.
4. **Come with fixtures in `verify-kit.sh`** — one case that passes and one that fails. A check nothing tests is a check that will quietly stop working.

## Adding a rule

Rules are expensive: every one of them costs every adopter attention forever. A new rule in `AGENTS.md.template` needs an incident behind it — yours or one from the case study — described in the pull request. "This seems like good practice" is not enough, and the existing rules should be held to the same standard.
