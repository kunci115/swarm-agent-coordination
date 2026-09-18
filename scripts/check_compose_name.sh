#!/usr/bin/env sh
# check_compose_name.sh — does every CI job get its own Docker Compose identity?
#
#   scripts/check_compose_name.sh            # scans .github/workflows
#   scripts/check_compose_name.sh DIR        # scans DIR instead
#
# Why this script exists. In the case study behind this kit, two gate jobs ran
# with the same COMPOSE_PROJECT_NAME. The second job's `up -d` attached to the
# first job's database, and whichever job finished first destroyed the other's
# data with `down -v`. Nothing in either job was wrong on its own. The defect
# was latent for as long as the two jobs never overlapped in time, and surfaced
# only when runner count went up and they finally ran together.
#
# The root cause is worth stating exactly, because it is easy to reproduce:
# a workflow-level `env:` block cannot see matrix values. A name that looks
# unique per leg — because the workflow has a matrix — is in fact one shared
# name for every leg.
#
# Three checks, in the order they failed:
#   1. a workflow that runs compose must set COMPOSE_PROJECT_NAME at all
#   2. the name must carry a per-run component (github.run_id)
#   3. a workflow with a matrix must reference matrix.* in the name
#
# Limits, stated plainly: this is a grep, not a YAML parser, so precision is
# per FILE, not per job. A workflow whose matrix lives in one job and whose
# compose usage lives in another can report a false positive. When that
# happens, split the workflow or silence the file — do not weaken the check.

set -eu

DIR="${1:-.github/workflows}"

if [ ! -d "$DIR" ]; then
    echo "SKIP: no workflow directory at $DIR."
    exit 0
fi

FILES=$(find "$DIR" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) | sort)
if [ -z "$FILES" ]; then
    echo "SKIP: no workflow files in $DIR."
    exit 0
fi

STATUS=0
CHECKED=0

for f in $FILES; do
    grep -qE 'docker[ -]compose' "$f" || continue
    CHECKED=$((CHECKED+1))

    NAMES=$(grep -nE 'COMPOSE_PROJECT_NAME' "$f" || true)

    # 1. compose without an identity at all
    if [ -z "$NAMES" ]; then
        echo "::error file=$f::runs docker compose but never sets COMPOSE_PROJECT_NAME."
        echo "  Two jobs sharing the default project name share — and destroy — one database."
        echo "  Fix: COMPOSE_PROJECT_NAME: app-\${{ github.run_id }}-\${{ github.job }}"
        STATUS=1
        continue
    fi

    # 2. an identity that does not vary per run
    if ! printf '%s\n' "$NAMES" | grep -qE 'github\.run_id|GITHUB_RUN_ID'; then
        echo "::error file=$f::COMPOSE_PROJECT_NAME carries no per-run component."
        printf '%s\n' "$NAMES" | sed 's/^/    /'
        echo "  Two runs of the same workflow will collide. Add \${{ github.run_id }}."
        STATUS=1
    fi

    # 3. the case study's actual bug: a matrix the name cannot see
    if grep -qE '^[[:space:]]*matrix:' "$f"; then
        if ! printf '%s\n' "$NAMES" | grep -qE 'matrix\.'; then
            echo "::error file=$f::workflow has a matrix, but COMPOSE_PROJECT_NAME never references matrix.*"
            printf '%s\n' "$NAMES" | sed 's/^/    /'
            echo "  A workflow-level env: cannot see matrix values, so every leg gets the SAME name."
            echo "  One leg's \`down -v\` then destroys the database another leg is still reading."
            echo "  Fix: include the matrix value, e.g. ...-\${{ matrix.os }}, and set it per JOB, not per workflow."
            STATUS=1
        fi
    fi
done

if [ "$CHECKED" = 0 ]; then
    echo "SKIP: no workflow in $DIR runs docker compose."
    exit 0
fi

if [ "$STATUS" = 0 ]; then
    echo "OK: $CHECKED compose-using workflow(s) in $DIR carry a unique identity."
fi
exit "$STATUS"
