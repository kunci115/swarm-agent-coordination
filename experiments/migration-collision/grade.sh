#!/usr/bin/env sh
# grade.sh — grade each lane alone, then the merged result. The gap is the measure.
#
#   sh grade.sh WORKDIR BRANCH...
#
# A lane's own suite proves the lane works beside the base. It says nothing
# about the lane working beside the other lanes landing the same day, and no
# amount of care inside a lane can make it say that. Only the merged tree
# answers, and only someone other than the lane can build it.
#
# Emits one JSON line per run, so a grid of these is a dataset.

set -eu

WORK="${1:?usage: grade.sh WORKDIR BRANCH...}"; shift
[ $# -gt 0 ] || { echo "usage: grade.sh WORKDIR BRANCH..." >&2; exit 2; }
cd "$WORK"

LANES=""
GREEN=0
RED=0

for b in "$@"; do
    git checkout -q "$b"
    if sh tests/run.sh > /dev/null 2>&1; then
        GREEN=$((GREEN + 1)); state=green
    else
        RED=$((RED + 1)); state=red
    fi
    LANES="$LANES $b:$state"
done

# the combined result, built the way merge_batch.sh builds it
git checkout -q dev
git checkout -q -B graded-merge dev
CONFLICT=0
for b in "$@"; do
    git merge --no-ff --no-edit -m "merge $b" "$b" > /dev/null 2>&1 || {
        CONFLICT=1
        git merge --abort 2>/dev/null || true
    }
done

MERGED_OUT=$(mktemp)
trap 'rm -f "$MERGED_OUT"' EXIT INT TERM
if [ "$CONFLICT" = 1 ]; then
    MERGED=conflict
elif sh tests/run.sh > "$MERGED_OUT" 2>&1; then
    MERGED=green
else
    MERGED=red
fi

# The cell the experiment exists for: every lane green, the merge not.
if [ "$RED" = 0 ] && [ "$MERGED" = "red" ]; then
    SEAM=1
else
    SEAM=0
fi

git checkout -q dev

printf '{"lanes":"%s","lanes_green":%d,"lanes_red":%d,"merged":"%s","textual_conflict":%d,"seam_defect":%d}\n' \
    "${LANES# }" "$GREEN" "$RED" "$MERGED" "$CONFLICT" "$SEAM"

echo "" >&2
echo "  lanes alone : $GREEN green, $RED red" >&2
echo "  merged      : $MERGED" >&2
if [ "$SEAM" = 1 ]; then
    echo "  seam defect : YES — every lane passed, the merge did not" >&2
    echo "" >&2
    sed 's/^/    /' "$MERGED_OUT" >&2
else
    echo "  seam defect : no" >&2
fi
