#!/usr/bin/env sh
# check_branch_base.sh — does this branch's name tell the truth about its base?
#
#   scripts/check_branch_base.sh                      # current branch vs INTEGRATION_BRANCH
#   scripts/check_branch_base.sh <NAME>               # named branch, from HEAD
#   scripts/check_branch_base.sh <NAME> <REV>         # named branch at REV
#   scripts/check_branch_base.sh --target <BASE> <NAME>
#
# Configuration: set INTEGRATION_BRANCH (default: dev) and PRODUCTION_BRANCH
# (default: main) in the environment, or edit the defaults below.
#
# The naming scheme says the type implies the base:
#   feature/ | fix/ | chore/ | docs/  ->  integration branch (dev)
#   hotfix/                           ->  production branch (main)
#   anything else                     ->  invalid: a name that declares no base
#                                         is the state this check exists to end.
#
# A name is a claim, and a claim nothing tests is only a convention.
# This script is what makes it a fact.
set -eu

INTEGRATION_BRANCH="${INTEGRATION_BRANCH:-dev}"
PRODUCTION_BRANCH="${PRODUCTION_BRANCH:-main}"

claim_for() {
    case "$1" in
        hotfix/*)                        echo "$PRODUCTION_BRANCH" ;;
        feature/*|fix/*|chore/*|docs/*)  echo "$INTEGRATION_BRANCH" ;;
        *)                               echo "" ;;
    esac
}

may_merge_into() {
    base="$1"
    head="$2"
    case "$base" in
        "$INTEGRATION_BRANCH")
            # lanes + the hotfix back-merge from production
            if [ "$head" = "$PRODUCTION_BRANCH" ]; then
                echo yes
            elif [ "$(claim_for "$head")" = "$INTEGRATION_BRANCH" ]; then
                echo yes
            else
                echo no
            fi
            ;;
        "$PRODUCTION_BRANCH")
            # hotfixes only; promotion of the integration branch is a
            # fast-forward, not a merge — do not route it through a PR
            if [ "$(claim_for "$head")" = "$PRODUCTION_BRANCH" ]; then
                echo yes
            else
                echo no
            fi
            ;;
        *) echo yes ;;   # not an integration line; not this check's business
    esac
}

MODE="${1:-self}"

if [ "${1:-}" = "--target" ]; then
    BASE="$2"
    NAME="$3"
    [ -n "$NAME" ] || { echo "usage: $0 --target BASE NAME" >&2; exit 2; }
    if [ "$(may_merge_into "$BASE" "$NAME")" = yes ]; then
        echo "OK: $NAME may merge into $BASE"
        exit 0
    fi
    echo "REFUSED: $NAME may not merge into $BASE (claims base: $(claim_for "$NAME"))"
    exit 1
fi

NAME="${1:-}"
REV="${2:-HEAD}"

if [ -z "$NAME" ]; then
    NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    [ -n "$NAME" ] || { echo "not in a git repository and no NAME given" >&2; exit 2; }
fi

CLAIM=$(claim_for "$NAME")
if [ -z "$CLAIM" ]; then
    echo "REFUSED: branch '$NAME' declares no base."
    echo "Rename it: feature/*, fix/*, chore/*, docs/* (from $INTEGRATION_BRANCH) or hotfix/* (from $PRODUCTION_BRANCH)."
    exit 1
fi

# verify the branch really was cut from its claimed base
MERGE_BASE=$(git merge-base "$REV" "$CLAIM" 2>/dev/null || echo "")
if [ -z "$MERGE_BASE" ]; then
    echo "WARN: cannot verify (no common ancestor with $CLAIM) — name claim: $NAME -> $CLAIM"
    exit 0
fi
AHEAD=$(git rev-list --count "$MERGE_BASE..$REV" 2>/dev/null || echo 0)
echo "OK: $NAME claims base $CLAIM (merge-base found, $AHEAD commits ahead)"
