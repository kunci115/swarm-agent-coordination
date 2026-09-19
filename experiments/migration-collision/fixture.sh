#!/usr/bin/env sh
# fixture.sh — build the repository the two lanes will work in.
#
#   sh fixture.sh /path/to/workdir
#
# A deliberately small application with the one property the experiment needs:
# a linear migration chain that two independent features must both extend.
# Neither feature mentions the other. Neither is unreasonable. The collision is
# structural — it comes from where the work sits, not from what it asks for.
#
# The test suite is the grader's instrument, so it checks the two things a
# forked chain breaks: exactly one head, and every model column backed by a
# migration. Both hold inside either lane alone. Only the merge breaks them.

set -eu

WORK="${1:?usage: fixture.sh WORKDIR}"
rm -rf "$WORK"
mkdir -p "$WORK/app/db/migrations/versions" "$WORK/tests"
cd "$WORK"

cat > app/db/models.py <<'PY'
"""The tables this service owns. One column per line, deliberately."""

BOOKINGS = [
    "id",
    "customer_id",
    "slot_at",
]

JOBS = [
    "id",
    "booking_id",
    "state",
]
PY

cat > app/db/migrations/versions/0001_initial.py <<'PY'
revision = "0001"
down_revision = None

COLUMNS = {"bookings": ["id", "customer_id"], "jobs": ["id", "booking_id"]}
PY

cat > app/db/migrations/versions/0002_slots_and_state.py <<'PY'
revision = "0002"
down_revision = "0001"

COLUMNS = {"bookings": ["slot_at"], "jobs": ["state"]}
PY

cat > tests/run.sh <<'SH'
#!/usr/bin/env sh
# The suite. Two assertions, both of which a forked chain breaks.
set -eu
cd "$(dirname "$0")/.."
FAIL=0

# 1. the migration chain has exactly one head
revs=$(grep -h '^revision' app/db/migrations/versions/*.py | sed 's/.*"\(.*\)"/\1/' | sort)
downs=$(grep -h '^down_revision' app/db/migrations/versions/*.py | sed -n 's/.*"\(.*\)"/\1/p' | sort)
heads=$(echo "$revs" | while read -r r; do echo "$downs" | grep -qx "$r" || echo "$r"; done)
n=$(echo "$heads" | grep -c . || true)
if [ "$n" -ne 1 ]; then
    echo "FAIL: migration chain has $n heads: $(echo "$heads" | tr '\n' ' ')"
    FAIL=1
else
    echo "ok: one migration head ($heads)"
fi

# 2. every column named in models.py is created by some migration
declared=$(grep -oE '^\s+"[a-z_]+",' app/db/models.py | tr -d ' ",')
migrated=$(grep -h -oE '"[a-z_]+"' app/db/migrations/versions/*.py | tr -d '"' | sort -u)
missing=""
for c in $declared; do
    echo "$migrated" | grep -qx "$c" || missing="$missing $c"
done
if [ -n "$missing" ]; then
    echo "FAIL: columns in models.py with no migration:$missing"
    FAIL=1
else
    echo "ok: every model column has a migration"
fi

exit "$FAIL"
SH
chmod +x tests/run.sh

cat > AGENTS.md <<'MD'
# AGENTS.md — rules of engagement

You are one lane of a swarm. Other agents work in parallel on this repository.

- Branch from `dev`. Name it `feature/…`.
- Declare the paths you own in your pull request body under `## Paths owned`.
- **Never merge your own work.** Open the branch and stop.
- Run `sh tests/run.sh` before you push; it must pass.
- If you add a migration, cut it from the current head of `dev`.
MD

git init -q -b dev .
git config user.email lane@local
git config user.name lane
git add -A
git commit -qm "initial: bookings and jobs, chain at 0002"
echo "$WORK"
