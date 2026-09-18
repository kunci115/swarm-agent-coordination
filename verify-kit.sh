#!/usr/bin/env sh
# verify-kit.sh — sanity checks that this kit's scripts work.
#
#   sh verify-kit.sh            # from the kit root, or by any path
#
# Exits non-zero if any check fails, so CI can gate on it.
# The kit enforces rules mechanically; this is the kit enforcing them on itself.

set -eu

KIT_ROOT=$(cd "$(dirname "$0")" && pwd)
export INTEGRATION_BRANCH=dev PRODUCTION_BRANCH=main
PASS=0; FAIL=0

check() { # description, expected_exit, command...
    desc="$1"; want="$2"; shift 2
    set +e
    "$@" >/dev/null 2>&1
    got=$?
    set -e
    if [ "$got" = "$want" ]; then PASS=$((PASS+1)); echo "PASS: $desc"
    else FAIL=$((FAIL+1)); echo "FAIL: $desc (exit $got, want $want)"; fi
}

echo "== check_branch_base.sh =="
check "feature/ claims dev"           0 sh "$KIT_ROOT/scripts/check_branch_base.sh" --target dev feature/login
check "fix/ claims dev"               0 sh "$KIT_ROOT/scripts/check_branch_base.sh" --target dev fix/null-crash
check "hotfix/ claims main"           0 sh "$KIT_ROOT/scripts/check_branch_base.sh" --target main hotfix/port-open
check "hotfix/ refused at dev"        1 sh "$KIT_ROOT/scripts/check_branch_base.sh" --target dev hotfix/port-open
check "feature/ refused at main"      1 sh "$KIT_ROOT/scripts/check_branch_base.sh" --target main feature/login
check "session-namespace refused"     1 sh "$KIT_ROOT/scripts/check_branch_base.sh" --target dev ao/123/fix
check "no-base refused"               1 sh "$KIT_ROOT/scripts/check_branch_base.sh" --target dev just-a-branch
check "main back-merge into dev"      0 sh "$KIT_ROOT/scripts/check_branch_base.sh" --target dev main

# ---- throwaway repo: two commits, the second carrying an AI trailer ----
TMP=$(mktemp -d)
trap 'cd /; rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/repo"
cd "$TMP/repo"
git init -q .
git config user.email t@t
git config user.name t
echo x > f.txt && git add f.txt && git commit -qm "initial"
echo y >> f.txt && git add f.txt
git commit -qm "add line

Co-Authored-By: Claude <claude@anthropic.com>"

echo ""
echo "== check_paths_owned.sh =="
printf '## Paths owned\n- f.txt\n' > "$TMP/body-ok.md"
printf 'Fixes the thing.\n' > "$TMP/body-missing.md"
check "body with declaration accepted"  0 sh "$KIT_ROOT/scripts/check_paths_owned.sh" --file "$TMP/body-ok.md" HEAD~1
check "body without declaration refused" 1 sh "$KIT_ROOT/scripts/check_paths_owned.sh" --file "$TMP/body-missing.md" HEAD~1
check "local mode lists touched paths"  1 sh "$KIT_ROOT/scripts/check_paths_owned.sh" --local HEAD~1

echo ""
echo "== strip_ai_trailers.sh =="
check "detects AI trailer"            1 sh "$KIT_ROOT/scripts/strip_ai_trailers.sh" --check HEAD~1..HEAD
sh "$KIT_ROOT/scripts/strip_ai_trailers.sh" HEAD~1..HEAD >/dev/null 2>&1
if git log --format=%B HEAD~1..HEAD | grep -qi "Co-Authored-By"; then
    FAIL=$((FAIL+1)); echo "FAIL: trailer stripped"
else
    PASS=$((PASS+1)); echo "PASS: trailer stripped"
fi
check "clean range reports OK"        0 sh "$KIT_ROOT/scripts/strip_ai_trailers.sh" --check HEAD~1..HEAD

echo ""
echo "===== $PASS passed, $FAIL failed ====="
[ "$FAIL" = 0 ]
