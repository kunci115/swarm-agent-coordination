#!/usr/bin/env sh
# merge_batch.sh — test the combined result, which is the only thing that ships.
#
#   scripts/merge_batch.sh 12 15 19
#   scripts/merge_batch.sh --base dev --test "pytest -q" 12 15 19
#   scripts/merge_batch.sh --keep feature/a feature/b
#
# This is the script behind Rule 2. Ten independently-green pull requests are
# exactly how seam defects get in: in the case study behind this kit, one
# ten-lane landing produced six defects, not one of them visible from inside
# any single lane, and git reported no conflict on any of them. Four of the six
# would have reached the integration branch had the lanes merged themselves.
#
# The reason no lane can catch these is structural, not a matter of diligence:
# a lane's test run proves the lane works next to the base, and says nothing
# about the lane working next to the nine other lanes landing the same day.
# Only the combined tree answers that, and only someone other than the lane can
# build it.
#
# What this script does NOT do: merge anything into your integration branch.
# It builds a throwaway branch, reports what it found, and deletes it. The
# decision to land stays with a person or the orchestrator — Rule 2 in both
# directions.
#
# Arguments are pull request numbers (fetched as refs/pull/N/head) or any ref
# name. Exit codes: 0 combined result is green, 1 conflict or failing test,
# 2 usage error or dirty worktree.

set -eu

BASE="${INTEGRATION_BRANCH:-dev}"
REMOTE="${REMOTE:-origin}"
TEST_CMD="${TEST_COMMAND:-}"
KEEP=0

while [ $# -gt 0 ]; do
    case "$1" in
        --base)   BASE="${2:?--base needs a branch}"; shift 2 ;;
        --test)   TEST_CMD="${2:?--test needs a command}"; shift 2 ;;
        --remote) REMOTE="${2:?--remote needs a name}"; shift 2 ;;
        --keep)   KEEP=1; shift ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        --*) echo "unknown option: $1" >&2; exit 2 ;;
        *) break ;;
    esac
done

[ $# -gt 0 ] || { echo "usage: $0 [--base BR] [--test CMD] [--keep] PR|REF..." >&2; exit 2; }
[ -d .git ] || { echo "not in a git repository" >&2; exit 2; }

if [ -n "$(git status --porcelain)" ]; then
    echo "REFUSED: worktree is dirty. Commit or stash first — this script switches branches." >&2
    exit 2
fi

ORIGINAL=$(git rev-parse --abbrev-ref HEAD)
if [ "$ORIGINAL" = "HEAD" ]; then          # detached: remember the commit
    ORIGINAL=$(git rev-parse HEAD)
fi
BATCH="merge-batch/$(date +%Y%m%d-%H%M%S)"

cleanup() {
    git merge --abort 2>/dev/null || true
    git checkout -q "$ORIGINAL" 2>/dev/null || true
    if [ "$KEEP" = 1 ]; then
        echo ""
        echo "Batch branch kept: $BATCH"
    else
        git branch -q -D "$BATCH" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

git rev-parse --verify --quiet "$BASE" >/dev/null || {
    echo "cannot resolve base '$BASE'" >&2; exit 2
}

echo "== batch from $BASE =="
git checkout -q -b "$BATCH" "$BASE"

MERGED=""
CONFLICTED=""

for ref in "$@"; do
    case "$ref" in
        [0-9]*)
            TARGET="refs/merge-batch/pr-$ref"
            if ! git fetch -q "$REMOTE" "refs/pull/$ref/head:$TARGET" --force 2>/dev/null; then
                echo "FAIL: cannot fetch PR #$ref from $REMOTE"
                CONFLICTED="$CONFLICTED #$ref(unfetchable)"
                continue
            fi
            LABEL="#$ref" ;;
        *)
            TARGET="$ref"
            git rev-parse --verify --quiet "$TARGET" >/dev/null || {
                echo "FAIL: cannot resolve ref '$ref'"
                CONFLICTED="$CONFLICTED $ref(unresolvable)"
                continue
            }
            LABEL="$ref" ;;
    esac

    if git merge --no-ff --no-edit -m "merge-batch: $LABEL" "$TARGET" >/dev/null 2>&1; then
        echo "  merged   $LABEL"
        MERGED="$MERGED $LABEL"
    else
        echo "  CONFLICT $LABEL  (against:$MERGED)"
        git diff --name-only --diff-filter=U | sed 's/^/             /'
        git merge --abort 2>/dev/null || true
        CONFLICTED="$CONFLICTED $LABEL"
    fi
done

echo ""
echo "== combined result =="
echo "  merged:    ${MERGED:-none}"
echo "  conflicts: ${CONFLICTED:-none}"

TEST_STATUS=0
if [ -z "$TEST_CMD" ]; then
    echo "  tests:     NOT RUN (pass --test 'CMD' or set TEST_COMMAND)"
    echo ""
    echo "A batch with no test run proves only that the merges apply. The seam"
    echo "defects this script exists to catch live in the test run."
elif [ -z "$MERGED" ]; then
    echo "  tests:     skipped (nothing merged)"
else
    echo "  tests:     running -> $TEST_CMD"
    echo ""
    if sh -c "$TEST_CMD"; then
        TEST_STATUS=0
        echo ""
        echo "  tests:     PASS on the combined tree"
    else
        TEST_STATUS=1
        echo ""
        echo "  tests:     FAIL on the combined tree"
        echo ""
        echo "Every one of these lanes may be green on its own. That is the normal"
        echo "shape of a seam defect: it belongs to the join, not to any lane."
        echo "Do not ask one lane to fix it — it is a coordination incident."
    fi
fi

[ -z "$CONFLICTED" ] && [ "$TEST_STATUS" = 0 ] || exit 1
echo ""
echo "OK: this batch is safe to land on $BASE."
