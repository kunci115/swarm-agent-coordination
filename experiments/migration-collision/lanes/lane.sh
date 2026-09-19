#!/usr/bin/env sh
# lane.sh — a scripted stand-in for one agent.
#
#   sh lane.sh WORKDIR BRANCH TABLE COLUMN REVISION
#
# It does what a competent lane does: branch from the current dev, add the
# column, cut a migration from the head it can see, run the suite, commit.
#
# Scripted on purpose, for now. An instrument has to be trusted before it is
# pointed at anything expensive, and debugging a grader and a language model at
# the same time means learning nothing about either. Swap this for a real agent
# once the grader is known to detect the collision it exists to detect — the
# interface is a branch, so nothing else changes.

set -eu

WORK="${1:?workdir}"; BRANCH="${2:?branch}"; TABLE="${3:?table}"
COLUMN="${4:?column}"; REV="${5:?revision}"
cd "$WORK"

git checkout -q dev
git checkout -q -b "$BRANCH"

# The head this lane can see when it starts. Both lanes see the same one.
HEAD_REV=$(
    revs=$(grep -h '^revision' app/db/migrations/versions/*.py | sed 's/.*"\(.*\)"/\1/' | sort)
    downs=$(grep -h '^down_revision' app/db/migrations/versions/*.py | sed -n 's/.*"\(.*\)"/\1/p' | sort)
    echo "$revs" | while read -r r; do echo "$downs" | grep -qx "$r" || echo "$r"; done
)

# the model gains a column
awk -v table="$TABLE" -v col="$COLUMN" '
    $0 ~ "^" table " = \\[" { inside = 1 }
    inside && /^\]/ { printf "    \"%s\",\n", col; inside = 0 }
    { print }
' app/db/models.py > app/db/models.py.new
mv app/db/models.py.new app/db/models.py

# and a migration, cut from the head this lane can see
cat > "app/db/migrations/versions/${REV}_${COLUMN}.py" <<PY
revision = "$REV"
down_revision = "$HEAD_REV"

COLUMNS = {"$TABLE": ["$COLUMN"]}
PY

# the lane gates itself before pushing, and passes
if ! sh tests/run.sh > /dev/null 2>&1; then
    echo "lane $BRANCH: own suite failed — the lane is broken, not the merge" >&2
    exit 1
fi

git add -A
git commit -qm "feat($TABLE): $COLUMN

## Paths owned
- app/db/models.py
- app/db/migrations/versions/${REV}_${COLUMN}.py"

echo "lane $BRANCH: green, migration $REV cut from $HEAD_REV"
