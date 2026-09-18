#!/usr/bin/env sh
# check_migration_chain.sh — is the migration chain still one straight line?
#
#   scripts/check_migration_chain.sh                 # the tree as it stands: one head?
#   scripts/check_migration_chain.sh --changed BASE  # did this lane cut from BASE's head?
#   MIGRATIONS_DIR=path scripts/check_migration_chain.sh
#
# Why this script exists: shared database resources were the largest incident
# category in the case study behind this kit — 40 of 85 flagged pull requests.
# The mechanism is always the same. Two lanes each write a migration against the
# same parent. Each lane is internally consistent, each lane's tests pass, and
# git reports no conflict because the two lanes wrote different files. The chain
# forks, and the fork is only discovered when someone tries to upgrade.
#
# Two modes, because there are two moments worth asking:
#
#   default    Compute the leaves of the chain. More than one leaf is a fork
#              that already exists. Run it on a merge result.
#   --changed  The preventive question, and the one that belongs in CI: every
#              migration this lane ADDS must hang off the current head of BASE.
#              A migration cut from a stale parent is a fork that has not
#              happened yet — catching it here costs one rebase, catching it
#              after the merge costs a coordinated repair.
#
# Format: Alembic (`revision` / `down_revision` module globals), which is what
# the case study ran. The logic is only parent pointers, so adapting it to
# another tool means changing rev_of() and downs_of() below and nothing else.
#
# Exits 0 when no migrations directory is found: adopters without migrations
# are not blocked by a check that does not apply to them.

set -eu

MODE="${1:-}"
BASE="${2:-}"

# ---- locate the migrations directory ----
find_migrations_dir() {
    if [ -n "${MIGRATIONS_DIR:-}" ]; then
        [ -d "$MIGRATIONS_DIR" ] && echo "$MIGRATIONS_DIR"
        return
    fi
    for d in alembic/versions migrations/versions db/migrations/versions \
             */alembic/versions */migrations/versions */db/migrations/versions; do
        [ -d "$d" ] && { echo "$d"; return; }
    done
    echo ""
}

MIG_DIR=$(find_migrations_dir)
if [ -z "$MIG_DIR" ]; then
    echo "SKIP: no migrations directory found (set MIGRATIONS_DIR to override)."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---- parsing: one revision id, and every parent a file names ----
# `revision = "abc"`, `revision: str = "abc"` both parse. A merge revision names
# several parents as a tuple, so downs_of prints one parent per line.
rev_of() {
    sed -n -E "s/^revision[[:space:]]*(:[^=]*)?=[[:space:]]*['\"]([^'\"]+)['\"].*/\2/p" "$1" | head -1
}
downs_of() {
    sed -n -E "s/^down_revision[[:space:]]*(:[^=]*)?=[[:space:]]*//p" "$1" | head -1 |
        grep -oE "['\"][^'\"]+['\"]" | tr -d "\"'" || true
}

# Collect revisions and parents from a set of files (paths on stdin).
collect() { # revs_out, downs_out
    : > "$1"; : > "$2"
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "$f" in */__init__.py) continue ;; esac
        r=$(rev_of "$f")
        [ -n "$r" ] && echo "$r" >> "$1"
        downs_of "$f" >> "$2"
    done
}

# Heads = revisions that no file names as a parent.
heads_from() { # revs, downs
    while IFS= read -r r; do
        grep -qxF "$r" "$2" || echo "$r"
    done < "$1"
}

list_migration_files() {
    find "$MIG_DIR" -name '*.py' ! -name '__init__.py' | sort
}

# ---------------- default mode: is the chain forked right now? ----------------
if [ "$MODE" != "--changed" ]; then
    list_migration_files | collect "$TMP/revs" "$TMP/downs"

    COUNT=$(wc -l < "$TMP/revs" | tr -d ' ')
    if [ "$COUNT" = 0 ]; then
        echo "SKIP: $MIG_DIR holds no parseable migrations."
        exit 0
    fi

    heads_from "$TMP/revs" "$TMP/downs" > "$TMP/heads"
    NHEADS=$(wc -l < "$TMP/heads" | tr -d ' ')

    if [ "$NHEADS" -le 1 ]; then
        echo "OK: $MIG_DIR — $COUNT migrations, one head ($(cat "$TMP/heads"))."
        exit 0
    fi

    echo "::error::migration chain has forked — $NHEADS heads in $MIG_DIR:"
    sed 's/^/  /' "$TMP/heads"
    echo ""
    echo "Two lanes wrote a migration against the same parent. Pick the chain order,"
    echo "then re-cut the later migration's down_revision onto the other head."
    exit 1
fi

# ------------- --changed mode: did this lane cut from BASE's head? -------------
[ -n "$BASE" ] || { echo "usage: $0 --changed BASE" >&2; exit 2; }
[ -d .git ] || { echo "not in a git repository" >&2; exit 2; }

git rev-parse --verify --quiet "$BASE" >/dev/null || {
    echo "WARN: cannot resolve '$BASE' — skipping (fetch it first to enable this check)."
    exit 0
}

# what BASE's chain looked like, straight out of the object store
: > "$TMP/base_revs"; : > "$TMP/base_downs"
git ls-tree -r --name-only "$BASE" -- "$MIG_DIR" | while IFS= read -r f; do
    case "$f" in */__init__.py|"") continue ;; esac
    git show "$BASE:$f" > "$TMP/blob" 2>/dev/null || continue
    r=$(rev_of "$TMP/blob")
    [ -n "$r" ] && echo "$r" >> "$TMP/base_revs"
    downs_of "$TMP/blob" >> "$TMP/base_downs"
done
[ -f "$TMP/base_revs" ] || : > "$TMP/base_revs"
heads_from "$TMP/base_revs" "$TMP/base_downs" > "$TMP/base_heads" 2>/dev/null || : > "$TMP/base_heads"

# migrations this lane adds
git diff --name-only --diff-filter=A "$BASE"...HEAD -- "$MIG_DIR" > "$TMP/added" || : > "$TMP/added"
if [ ! -s "$TMP/added" ]; then
    echo "OK: this lane adds no migrations."
    exit 0
fi

collect "$TMP/mine_revs" "$TMP/mine_downs" < "$TMP/added"

BASE_HEAD=$(head -1 "$TMP/base_heads" 2>/dev/null || echo "")
NBASE_HEADS=$(wc -l < "$TMP/base_heads" | tr -d ' ')
if [ "$NBASE_HEADS" -gt 1 ]; then
    echo "::error::$BASE itself has $NBASE_HEADS migration heads — fix the base chain first:"
    sed 's/^/  /' "$TMP/base_heads"
    exit 1
fi

STATUS=0
while IFS= read -r f; do
    [ -f "$f" ] || continue
    r=$(rev_of "$f")
    downs_of "$f" > "$TMP/f_downs"
    # A migration whose parent is another migration from this same lane is
    # interior to the lane's own chain — only the anchor is worth checking.
    ANCHOR=1
    while IFS= read -r d; do
        grep -qxF "$d" "$TMP/mine_revs" && ANCHOR=0
    done < "$TMP/f_downs"
    [ "$ANCHOR" = 1 ] || continue

    PARENT=$(head -1 "$TMP/f_downs" 2>/dev/null || echo "")
    if [ -z "$PARENT" ]; then
        # down_revision = None: only legitimate when BASE has no chain yet
        if [ -n "$BASE_HEAD" ]; then
            echo "::error::$f ($r) declares no parent, but $BASE already has head $BASE_HEAD."
            STATUS=1
        fi
        continue
    fi
    if [ "$PARENT" != "$BASE_HEAD" ]; then
        echo "::error::$f ($r) hangs off '$PARENT', but the head of $BASE is '$BASE_HEAD'."
        echo "  Cut from a stale parent — this becomes a forked chain at merge time."
        echo "  Fix: set down_revision = \"$BASE_HEAD\" and re-run your migration locally."
        STATUS=1
    fi
done < "$TMP/added"

if [ "$STATUS" = 0 ]; then
    echo "OK: every migration this lane adds hangs off ${BASE_HEAD:-<empty chain>}."
fi
exit "$STATUS"
