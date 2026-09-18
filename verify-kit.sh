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

check_in() { # dir, description, expected_exit, command...
    dir="$1"; desc="$2"; want="$3"; shift 3
    set +e
    ( cd "$dir" && "$@" ) >/dev/null 2>&1
    got=$?
    set -e
    if [ "$got" = "$want" ]; then PASS=$((PASS+1)); echo "PASS: $desc"
    else FAIL=$((FAIL+1)); echo "FAIL: $desc (exit $got, want $want)"; fi
}

TMP=$(mktemp -d)
trap 'cd /; rm -rf "$TMP"' EXIT INT TERM

git_init_quiet() { # dir
    mkdir -p "$1"
    cd "$1"
    git init -q -b dev .
    git config user.email t@t
    git config user.name t
}

mk_mig() { # path, revision, down_revision ("" means None)
    mkdir -p "$(dirname "$1")"
    if [ -z "$3" ]; then
        printf 'revision = "%s"\ndown_revision = None\n\ndef upgrade():\n    pass\n' "$2" > "$1"
    else
        printf 'revision = "%s"\ndown_revision = "%s"\n\ndef upgrade():\n    pass\n' "$2" "$3" > "$1"
    fi
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
git_init_quiet "$TMP/repo"
echo x > f.txt && git add f.txt && git commit -qm "initial"
echo y >> f.txt && git add f.txt
git commit -qm "add line

Co-Authored-By: Claude <claude@anthropic.com>"

echo ""
echo "== check_paths_owned.sh =="
printf '## Paths owned\n- f.txt\n' > "$TMP/body-ok.md"
printf 'Fixes the thing.\n' > "$TMP/body-missing.md"
check "body with declaration accepted"   0 sh "$KIT_ROOT/scripts/check_paths_owned.sh" --file "$TMP/body-ok.md" HEAD~1
check "body without declaration refused" 1 sh "$KIT_ROOT/scripts/check_paths_owned.sh" --file "$TMP/body-missing.md" HEAD~1
check "local mode lists touched paths"   1 sh "$KIT_ROOT/scripts/check_paths_owned.sh" --local HEAD~1

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
echo "== commit-msg-example (prevention, opt-in) =="
cat > "$TMP/msg-in.txt" <<'MSG'
feat: add the thing

Explains why the thing is added.

Co-Authored-By: Claude <claude@anthropic.com>
🤖 Generated with [Claude Code](https://claude.com/claude-code)
MSG
sh "$KIT_ROOT/scripts/commit-msg-example" "$TMP/msg-in.txt" >/dev/null 2>&1 || true
if grep -qiE "Co-Authored-By|Generated with" "$TMP/msg-in.txt"; then
    FAIL=$((FAIL+1)); echo "FAIL: hook strips trailers from a message"
else
    PASS=$((PASS+1)); echo "PASS: hook strips trailers from a message"
fi
if grep -q "Explains why the thing is added." "$TMP/msg-in.txt" &&
   head -1 "$TMP/msg-in.txt" | grep -q "feat: add the thing"; then
    PASS=$((PASS+1)); echo "PASS: hook keeps the real message intact"
else
    FAIL=$((FAIL+1)); echo "FAIL: hook keeps the real message intact"
fi
if [ -n "$(tail -1 "$TMP/msg-in.txt")" ]; then
    PASS=$((PASS+1)); echo "PASS: hook leaves no trailing blank run"
else
    FAIL=$((FAIL+1)); echo "FAIL: hook leaves no trailing blank run"
fi

# a message with nothing to strip must come out byte-identical
printf 'fix: ordinary commit\n\nNo trailers here.\n' > "$TMP/msg-clean.txt"
cp "$TMP/msg-clean.txt" "$TMP/msg-clean.orig"
sh "$KIT_ROOT/scripts/commit-msg-example" "$TMP/msg-clean.txt" >/dev/null 2>&1 || true
check "clean message passes through unchanged" 0 cmp -s "$TMP/msg-clean.txt" "$TMP/msg-clean.orig"

# and the hook must actually work when git invokes it
git_init_quiet "$TMP/hookrepo"
mkdir -p .git/hooks
cp "$KIT_ROOT/scripts/commit-msg-example" .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
echo z > z.txt && git add z.txt
git commit -qm "chore: real commit through the hook

Co-Authored-By: Claude <claude@anthropic.com>"
if git log -1 --format=%B | grep -qi "Co-Authored-By"; then
    FAIL=$((FAIL+1)); echo "FAIL: installed hook strips on a real commit"
else
    PASS=$((PASS+1)); echo "PASS: installed hook strips on a real commit"
fi
cd "$TMP/repo"

# ---------------------------------------------------------------------------
echo ""
echo "== check_migration_chain.sh =="
cd "$TMP"

mk_mig "$TMP/mig-linear/migrations/versions/0001.py" r1 ""
mk_mig "$TMP/mig-linear/migrations/versions/0002.py" r2 r1
check_in "$TMP/mig-linear" "linear chain accepted"  0 sh "$KIT_ROOT/scripts/check_migration_chain.sh"

# the case study's largest category: two lanes, same parent, no git conflict
mk_mig "$TMP/mig-forked/migrations/versions/0001.py"  r1  ""
mk_mig "$TMP/mig-forked/migrations/versions/0002a.py" r2a r1
mk_mig "$TMP/mig-forked/migrations/versions/0002b.py" r2b r1
check_in "$TMP/mig-forked" "forked chain refused"   1 sh "$KIT_ROOT/scripts/check_migration_chain.sh"

mkdir -p "$TMP/mig-none"
check_in "$TMP/mig-none" "no migrations dir skips"  0 sh "$KIT_ROOT/scripts/check_migration_chain.sh"

# --changed: the preventive check, against a base that moves under the lane
git_init_quiet "$TMP/mig-git"
mk_mig migrations/versions/0001.py r1 ""
git add -A && git commit -qm "first migration"
git checkout -q -b feature/lane-a
mk_mig migrations/versions/0002.py r2 r1
git add -A && git commit -qm "lane a migration"
check_in "$TMP/mig-git" "migration off current head accepted" 0 \
    sh "$KIT_ROOT/scripts/check_migration_chain.sh" --changed dev

# another lane lands first; lane-a's parent is now stale
git checkout -q dev
mk_mig migrations/versions/0002b.py r2b r1
git add -A && git commit -qm "lane b migration landed first"
git checkout -q feature/lane-a
check_in "$TMP/mig-git" "migration off stale parent refused" 1 \
    sh "$KIT_ROOT/scripts/check_migration_chain.sh" --changed dev

git checkout -q dev
check_in "$TMP/mig-git" "lane adding no migration accepted" 0 \
    sh "$KIT_ROOT/scripts/check_migration_chain.sh" --changed dev

# ---------------------------------------------------------------------------
echo ""
echo "== check_compose_name.sh =="
mkdir -p "$TMP/wf-good" "$TMP/wf-matrix-blind" "$TMP/wf-missing" "$TMP/wf-norunid" "$TMP/wf-nocompose"

cat > "$TMP/wf-good/ci.yml" <<'YML'
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    steps:
      - run: docker compose up -d
        env:
          COMPOSE_PROJECT_NAME: app-${{ github.run_id }}-${{ matrix.os }}
YML
check "matrix-aware compose name accepted" 0 sh "$KIT_ROOT/scripts/check_compose_name.sh" "$TMP/wf-good"

# the exact latent bug: workflow-level env cannot see matrix values
cat > "$TMP/wf-matrix-blind/ci.yml" <<'YML'
env:
  COMPOSE_PROJECT_NAME: app-${{ github.run_id }}
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    steps:
      - run: docker compose up -d
YML
check "matrix-blind compose name refused"  1 sh "$KIT_ROOT/scripts/check_compose_name.sh" "$TMP/wf-matrix-blind"

cat > "$TMP/wf-missing/ci.yml" <<'YML'
jobs:
  test:
    steps:
      - run: docker-compose up -d && docker-compose down -v
YML
check "compose without a name refused"     1 sh "$KIT_ROOT/scripts/check_compose_name.sh" "$TMP/wf-missing"

cat > "$TMP/wf-norunid/ci.yml" <<'YML'
jobs:
  test:
    steps:
      - run: docker compose up -d
        env:
          COMPOSE_PROJECT_NAME: app-fixed
YML
check "compose name without run_id refused" 1 sh "$KIT_ROOT/scripts/check_compose_name.sh" "$TMP/wf-norunid"

cat > "$TMP/wf-nocompose/ci.yml" <<'YML'
jobs:
  test:
    steps:
      - run: pytest -q
YML
check "workflows without compose skip"     0 sh "$KIT_ROOT/scripts/check_compose_name.sh" "$TMP/wf-nocompose"

# ---------------------------------------------------------------------------
echo ""
echo "== merge_batch.sh =="
git_init_quiet "$TMP/batch"
echo "base" > shared.txt
mkdir -p app && echo "a" > app/a.txt
git add -A && git commit -qm "base"

git checkout -q -b feature/lane-a
echo "lane a" > app/a_feature.txt
git add -A && git commit -qm "lane a"

git checkout -q dev && git checkout -q -b feature/lane-b
echo "lane b" > app/b_feature.txt
git add -A && git commit -qm "lane b"

# lane-c edits the same line lane-d does: the rare textual conflict (1 of 85)
git checkout -q dev && git checkout -q -b feature/lane-c
echo "c wins" > shared.txt
git add -A && git commit -qm "lane c"
git checkout -q dev && git checkout -q -b feature/lane-d
echo "d wins" > shared.txt
git add -A && git commit -qm "lane d"
git checkout -q dev

check_in "$TMP/batch" "clean batch with passing tests"  0 \
    sh "$KIT_ROOT/scripts/merge_batch.sh" --base dev --test "true" feature/lane-a feature/lane-b
check_in "$TMP/batch" "combined test failure reported"  1 \
    sh "$KIT_ROOT/scripts/merge_batch.sh" --base dev --test "false" feature/lane-a
check_in "$TMP/batch" "conflicting batch refused"       1 \
    sh "$KIT_ROOT/scripts/merge_batch.sh" --base dev --test "true" feature/lane-c feature/lane-d
check_in "$TMP/batch" "unresolvable ref refused"        1 \
    sh "$KIT_ROOT/scripts/merge_batch.sh" --base dev --test "true" feature/does-not-exist
check_in "$TMP/batch" "no refs is a usage error"        2 \
    sh "$KIT_ROOT/scripts/merge_batch.sh" --base dev --test "true"

cd "$TMP/batch" && echo "uncommitted" >> shared.txt
check_in "$TMP/batch" "dirty worktree refused"          2 \
    sh "$KIT_ROOT/scripts/merge_batch.sh" --base dev --test "true" feature/lane-a
git checkout -q -- shared.txt

# the batch branch must not survive, and dev must be untouched
cd "$TMP/batch"
if git branch --list 'merge-batch/*' | grep -q .; then
    FAIL=$((FAIL+1)); echo "FAIL: batch branch cleaned up"
else
    PASS=$((PASS+1)); echo "PASS: batch branch cleaned up"
fi
if [ "$(git rev-parse dev)" = "$(git rev-parse HEAD)" ] && [ ! -f app/a_feature.txt ]; then
    PASS=$((PASS+1)); echo "PASS: integration branch left untouched"
else
    FAIL=$((FAIL+1)); echo "FAIL: integration branch left untouched"
fi

echo ""
echo "===== $PASS passed, $FAIL failed ====="
[ "$FAIL" = 0 ]
