#!/usr/bin/env sh
# check_paths_owned.sh — verify that a pull request declares the paths it touches.
#
#   scripts/check_paths_owned.sh <PR_NUMBER>          # in CI: reads PR body via gh
#   scripts/check_paths_owned.sh --local <BASE>       # local pre-push: diff vs BASE
#   scripts/check_paths_owned.sh --file <BODY.md> <BASE>
#
# The rule: a pull request body must contain a "## Paths owned" section listing
# the file paths the lane touches. Collisions between parallel agent lanes are
# found at merge time unless someone declares ownership earlier.
#
# This check only verifies THAT the section exists (the CI gate). The softer,
# smarter check — whether the declared paths match the actual diff — is
# `--local`, which lists touched paths so a human or agent can compare.

set -eu

MODE="${1:-}"

if [ "$MODE" = "--local" ] || [ "$MODE" = "--file" ]; then
    # ---- local mode: list paths touched vs BASE, check a body file (or stdin) ----
    if [ "$MODE" = "--file" ]; then
        BODY_FILE="$2"
        BASE="$3"
    else
        BODY_FILE=""
        BASE="$2"
    fi
    [ -n "$BASE" ] && [ -d .git ] || {
        echo "usage: check_paths_owned.sh --local <BASE> | --file <BODY.md> <BASE>" >&2
        exit 2
    }

    echo "# Paths this branch touches (vs $BASE):"
    git diff --name-only "$BASE"...HEAD | sort

    BODY_CONTENT=""
    if [ -n "$BODY_FILE" ] && [ -f "$BODY_FILE" ]; then
        BODY_CONTENT=$(cat "$BODY_FILE")
    elif [ -n "$BODY_FILE" ]; then
        BODY_CONTENT="$BODY_FILE"   # allow passing the body as an argument
    fi

    if printf '%s' "$BODY_CONTENT" | grep -qi "paths owned"; then
        echo ""
        echo "OK: 'Paths owned' declared."
        echo "Compare the lists above manually — declared vs touched."
        exit 0
    else
        echo ""
        echo "MISSING: no '## Paths owned' section found in the provided body."
        echo "Add it before pushing:"
        echo ""
        echo "  ## Paths owned"
        echo "  - path/to/file.py"
        exit 1
    fi
fi

# ---- CI mode: PR number, read body via gh ----
PR_NUMBER="${1:-}"
[ -n "$PR_NUMBER" ] && [ -n "$GITHUB_REPOSITORY" ] || {
    echo "usage: check_paths_owned.sh <PR_NUMBER>   (CI, needs GH_TOKEN + GITHUB_REPOSITORY)"
    echo "       check_paths_owned.sh --local <BASE> | --file <BODY.md> <BASE>"
    exit 2
}

BODY=$(gh pr view "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --json body --jq .body)

if printf '%s' "$BODY" | grep -qi "paths owned"; then
    echo "OK: PR #$PR_NUMBER declares paths owned."
    exit 0
fi

echo "::error::PR #$PR_NUMBER is missing a '## Paths owned' section in its body."
echo "The lane must declare which file paths it touches, e.g.:"
echo ""
echo "  ## Paths owned"
echo "  - src/api/routes/bookings.py"
echo "  - migrations/0042_add_field.py (new)"
exit 1
