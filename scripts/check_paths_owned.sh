#!/usr/bin/env sh
# check_paths_owned.sh — does the declaration match what the branch actually touched?
#
#   scripts/check_paths_owned.sh <PR_NUMBER>          # CI: reads body + files via gh
#   scripts/check_paths_owned.sh --local <BASE>       # local: diff vs BASE, no body
#   scripts/check_paths_owned.sh --file <BODY.md> <BASE>
#
# The rule: a pull request body must contain a "## Paths owned" section listing
# the file paths the lane touches, and that list must cover the diff. Collisions
# between parallel agent lanes are found at merge time unless someone declares
# ownership earlier — and a declaration that does not match the diff declares
# nothing.
#
# This check used to verify only that the section EXISTED. The corpus behind
# this kit priced that choice: of 221 pull requests carrying the block, 88 did
# not cover their own diff, leaving 674 files touched but undeclared. A gate
# measuring presence passed 40% of the violations it existed to catch.
#
# A declaration may be a literal path, a glob, a brace list, or a directory:
#
#   ## Paths owned
#   - app/api/routers/bookings.py
#   - app/ui/templates/{bookings,jobs}/*.html
#   - tests/*
#   - docs/booking/
#
# Declaring a glob is not cheating. The point is that the declaration should
# predict the diff, so another lane reading it learns what to stay away from.
# `tests/*` is a fine answer; silence is not.
#
# One deliberate imprecision, stated plainly: matching uses `case`, where `*`
# crosses `/`. So `tests/*` also covers `tests/agents/test_x.py`. The check errs
# toward accepting a broad declaration rather than rejecting a correct one — a
# gate that cries wolf gets switched off, and then it protects nothing.

set -eu

MODE="${1:-}"

# ---- matching -------------------------------------------------------------

# Expand one brace list into one pattern per line. `case` has no brace
# expansion, and real declarations in the corpus use it heavily.
expand_braces() {
    case "$1" in
        *'{'*'}'*)
            _pre=${1%%\{*}
            _rest=${1#*\{}
            _opts=${_rest%%\}*}
            _post=${_rest#*\}}
            _oldifs=$IFS
            IFS=','
            for _o in $_opts; do
                IFS=$_oldifs
                expand_braces "${_pre}${_o}${_post}"
                IFS=','
            done
            IFS=$_oldifs
            ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# Does any declared pattern cover this path?
covers() { # path, then patterns on stdin
    _f="$1"
    while IFS= read -r _pat; do
        [ -n "$_pat" ] || continue
        # The subshell ends with an explicit `exit 1`: an unmatched `case`
        # returns 0, so without it every pattern would appear to match.
        if expand_braces "$_pat" | (
            while IFS= read -r _p; do
                [ "$_f" = "$_p" ] && exit 0                   # exact
                case "$_f" in "${_p%/}"/*) exit 0 ;; esac     # directory prefix
                case "$_f" in $_p) exit 0 ;; esac             # glob (unquoted)
            done
            exit 1
        ); then
            return 0
        fi
    done
    return 1
}

# Pull the declared paths out of a body, between the "## Paths owned" heading
# and the next heading.
#
# Real declarations are not always a bullet list. In the corpus behind this kit
# they are just as often a markdown table with the path in backticks:
#
#   | `app/api/routers/sessions.py` | the clearing control |
#
# So both shapes are read: backticked tokens anywhere in the section, and the
# first token of each list item. Anything that looks like prose rather than a
# path is dropped — a stray `**` from bold text would otherwise be parsed as a
# pattern that matches every file and silently pass the whole check.
declared_paths() {
    sed -n '/^#\{1,6\}[[:space:]]*[Pp]aths owned/,/^#\{1,6\}[[:space:]]/p' > "$TMP/section"

    {
        # backticked tokens: `app/x.py`
        grep -o '`[^`]*`' < "$TMP/section" | tr -d '`'
        # bullet list items: - app/x.py (new)
        sed -n 's/^[[:space:]]*[-*][[:space:]][[:space:]]*//p' < "$TMP/section" |
            sed 's/[[:space:]].*$//'
    } |
        sed 's/[,;:]$//; s|^\./||' |
        # a path has a separator or an extension, and never starts with a
        # markdown marker
        grep -E '^[^*#|[:space:]][^[:space:]]*([/.][^[:space:]]*)+$' |
        sort -u || true
}

# Compare a declaration against a list of touched paths. Both are files.
compare() { # declared_file, touched_file
    _missing=0
    : > "$TMP/undeclared"
    while IFS= read -r _file; do
        [ -n "$_file" ] || continue
        if ! covers "$_file" < "$1"; then
            echo "$_file" >> "$TMP/undeclared"
            _missing=$((_missing + 1))
        fi
    done < "$2"

    if [ "$_missing" = 0 ]; then
        echo "OK: the declaration covers all $(wc -l < "$2" | tr -d ' ') touched paths."
        return 0
    fi

    echo "::error::$_missing file(s) touched but not declared in '## Paths owned':"
    head -20 "$TMP/undeclared" | sed 's/^/    /'
    [ "$_missing" -gt 20 ] && echo "    ... and $((_missing - 20)) more"

    # Suggest the shortest glob that would have covered what was missed.
    _dirs=$(sed 's|/[^/]*$||' "$TMP/undeclared" | sort -u)
    echo ""
    echo "Extend the declaration before you push. A glob is a valid declaration:"
    echo "$_dirs" | head -8 | sed 's|$|/*|; s/^/    - /'
    echo ""
    echo "Two lanes editing the same file without a declaration is how collisions"
    echo "are found at merge time. The declaration is how they are found earlier."
    return 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---- match mode: a body and a path list, no git ---------------------------
# Exists so the matching rules can be tested against real declarations without
# reconstructing a repository for each one.
#
#   printf 'app/a.py\ntests/b.py\n' | check_paths_owned.sh --match BODY.md

if [ "$MODE" = "--match" ]; then
    BODY_ARG="${2:?usage: check_paths_owned.sh --match <BODY.md> < paths}"
    if [ -f "$BODY_ARG" ]; then
        declared_paths < "$BODY_ARG" > "$TMP/declared"
    else
        printf '%s\n' "$BODY_ARG" | declared_paths > "$TMP/declared"
    fi
    sort > "$TMP/touched"
    [ -s "$TMP/declared" ] || { echo "::error::no '## Paths owned' section found."; exit 1; }
    compare "$TMP/declared" "$TMP/touched" > /dev/null 2>&1 || exit 1
    exit 0
fi

# ---- local / file modes ---------------------------------------------------

if [ "$MODE" = "--local" ] || [ "$MODE" = "--file" ]; then
    if [ "$MODE" = "--file" ]; then
        BODY_ARG="${2:-}"
        BASE="${3:-}"
    else
        BODY_ARG=""
        BASE="${2:-}"
    fi
    [ -n "$BASE" ] && [ -d .git ] || {
        echo "usage: check_paths_owned.sh --local <BASE> | --file <BODY.md> <BASE>" >&2
        exit 2
    }

    git diff --name-only "$BASE"...HEAD | sort > "$TMP/touched"
    echo "# Paths this branch touches (vs $BASE):"
    sed 's/^/  /' "$TMP/touched"
    echo ""

    if [ -n "$BODY_ARG" ] && [ -f "$BODY_ARG" ]; then
        declared_paths < "$BODY_ARG" > "$TMP/declared"
    elif [ -n "$BODY_ARG" ]; then
        printf '%s\n' "$BODY_ARG" | declared_paths > "$TMP/declared"
    else
        echo "No body given, so only the touched paths are listed."
        echo "Pass the pull request body to check it:"
        echo "  check_paths_owned.sh --file BODY.md $BASE"
        exit 1
    fi

    if [ ! -s "$TMP/declared" ]; then
        echo "::error::no '## Paths owned' section found in the provided body."
        echo "Add it before pushing:"
        echo ""
        echo "  ## Paths owned"
        sed 's|^|  - |' "$TMP/touched" | head -10
        exit 1
    fi

    echo "Declared:"
    sed 's/^/  /' "$TMP/declared"
    echo ""
    compare "$TMP/declared" "$TMP/touched"
    exit $?
fi

# ---- CI mode: PR number, body and files via gh -----------------------------

PR_NUMBER="${1:-}"
[ -n "$PR_NUMBER" ] && [ -n "${GITHUB_REPOSITORY:-}" ] || {
    echo "usage: check_paths_owned.sh <PR_NUMBER>   (CI, needs GH_TOKEN + GITHUB_REPOSITORY)"
    echo "       check_paths_owned.sh --local <BASE> | --file <BODY.md> <BASE>"
    exit 2
}

gh pr view "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --json body --jq .body > "$TMP/body"
gh pr view "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --json files --jq '.files[].path' |
    sort > "$TMP/touched"

declared_paths < "$TMP/body" > "$TMP/declared"

if [ ! -s "$TMP/declared" ]; then
    echo "::error::PR #$PR_NUMBER is missing a '## Paths owned' section in its body."
    echo "The lane must declare which file paths it touches, e.g.:"
    echo ""
    echo "  ## Paths owned"
    sed 's|^|  - |' "$TMP/touched" | head -10
    exit 1
fi

if [ ! -s "$TMP/touched" ]; then
    echo "OK: PR #$PR_NUMBER declares paths owned (no files reported by the API)."
    exit 0
fi

echo "PR #$PR_NUMBER declares:"
sed 's/^/  /' "$TMP/declared"
echo ""
compare "$TMP/declared" "$TMP/touched"
