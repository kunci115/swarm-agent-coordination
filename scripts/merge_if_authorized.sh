#!/usr/bin/env sh
# merge_if_authorized.sh — land a batch only if the declared policy allows it.
#
#   scripts/merge_if_authorized.sh 12 15 19          # evaluate, then merge
#   scripts/merge_if_authorized.sh --dry-run 12 15   # evaluate, merge nothing
#   scripts/merge_if_authorized.sh --explain FIXTURE # evaluate from a file
#
# Whether a machine may land work is a delegation decision. This script does
# not make it — `.swarm/merge-policy.yml` does, and an absent or unparseable
# policy is a refusal rather than a default-allow.
#
# Every condition is mechanically checkable. None of them asks an agent to
# judge whether a change looks safe, because an agent's judgement is the thing
# a policy exists to not depend on.
#
# The conditions, and where each comes from:
#
#   combined gate green     the ten-lane landing that produced six defects,
#                           none visible from inside any lane
#   distinct merger         a lane never merges its own pull request
#   no requires_human path  forks and workflow edits are invisible to the gate
#                           that would have caught them
#   batch within ceiling    a bigger batch hides which change broke it
#
# Exit: 0 authorized (and merged unless --dry-run), 1 refused, 2 usage.

set -eu

POLICY="${POLICY:-.swarm/merge-policy.yml}"
DRY=0
EXPLAIN=""

while [ $# -gt 0 ]; do
    case "$1" in
        --policy)  POLICY="${2:?--policy needs a path}"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        --explain) EXPLAIN="${2:?--explain needs a fixture}"; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --*) echo "unknown option: $1" >&2; exit 2 ;;
        *) break ;;
    esac
done

# ---- policy ---------------------------------------------------------------

[ -f "$POLICY" ] || {
    echo "REFUSED: no merge policy at $POLICY."
    echo "Authority to land work is declared, not assumed. Copy the kit's"
    echo ".swarm/merge-policy.yml and edit it before using this script."
    exit 1
}

# A deliberately small YAML subset: `key: value`, and `key:` followed by
# indented `- item` lines. Anything else is not understood, and a policy that
# is not understood is a refusal.
policy_value() { # key
    sed -n "s/^$1:[[:space:]]*//p" "$POLICY" | sed 's/[[:space:]]*#.*$//' | head -1
}
policy_list() { # key
    sed -n "/^$1:[[:space:]]*$/,/^[^[:space:]-]/p" "$POLICY" |
        sed -n 's/^[[:space:]]*-[[:space:]]*//p' | sed 's/[[:space:]]*#.*$//'
}

VERSION=$(policy_value version)
COMBINED=$(policy_value require_combined_gate)
TEST_CMD=$(policy_value test_command)
DISTINCT=$(policy_value require_distinct_merger)
MAX_BATCH=$(policy_value max_batch)

[ "$VERSION" = "1" ] || {
    echo "REFUSED: $POLICY declares version '${VERSION:-none}', which this script does not understand."
    exit 1
}

# The one setting with no "false". Honouring it would rebuild the failure this
# kit exists to prevent, so a policy that asks for it is refused outright
# rather than obeyed.
[ "$COMBINED" = "true" ] || {
    echo "REFUSED: require_combined_gate is not true."
    echo ""
    echo "There is no supported way to land on each lane's own green checks."
    echo "Ten independently-green pull requests is how seam defects get in: one"
    echo "ten-lane landing in the case study produced six defects, not one of"
    echo "them visible from inside any lane, and git reported no conflict."
    exit 1
}

[ -n "$TEST_CMD" ] || { echo "REFUSED: $POLICY sets no test_command, so nothing would prove the combined tree works."; exit 1; }

REFUSALS=0
refuse() { echo "  REFUSED: $1"; REFUSALS=$((REFUSALS + 1)); }

# ---- the batch ------------------------------------------------------------
# Either read from the fixture (--explain, for tests) or from the platform.
# One shape either way: "number<TAB>author<TAB>path,path,path".

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

if [ -n "$EXPLAIN" ]; then
    [ -f "$EXPLAIN" ] || { echo "no fixture at $EXPLAIN" >&2; exit 2; }
    grep -v '^#' "$EXPLAIN" | grep -v '^[[:space:]]*$' > "$TMP/batch"
    MERGER="${MERGER:-orchestrator}"
    GATE_RESULT="${GATE_RESULT:-green}"
else
    [ $# -gt 0 ] || { echo "usage: merge_if_authorized.sh [--dry-run] PR..." >&2; exit 2; }
    : > "$TMP/batch"
    for pr in "$@"; do
        gh pr view "$pr" --json number,author,files \
            --jq '[.number, .author.login, ([.files[].path] | join(","))] | @tsv' >> "$TMP/batch"
    done
    MERGER="${MERGER:-$(gh api user --jq .login)}"
    GATE_RESULT=""
fi

COUNT=$(wc -l < "$TMP/batch" | tr -d ' ')
echo "== authorizing $COUNT pull request(s) against $POLICY =="

# ---- condition: batch ceiling --------------------------------------------
if [ -n "$MAX_BATCH" ] && [ "$COUNT" -gt "$MAX_BATCH" ]; then
    refuse "batch of $COUNT exceeds max_batch of $MAX_BATCH"
fi

# ---- condition: distinct merger, and no requires_human path --------------
policy_list requires_human > "$TMP/human"

while IFS="$(printf '\t')" read -r number author paths; do
    [ -n "$number" ] || continue

    if [ "$DISTINCT" = "true" ] && [ "$author" = "$MERGER" ]; then
        refuse "#$number was opened by $author, who is also the merger — a lane does not land its own work"
    fi

    printf '%s\n' "$paths" | tr ',' '\n' | while IFS= read -r path; do
        [ -n "$path" ] || continue
        while IFS= read -r guarded; do
            [ -n "$guarded" ] || continue
            case "$path" in
                "$guarded"|"${guarded%/}"/*) echo "$number|$path|$guarded" >> "$TMP/guard_hits" ;;
            esac
        done < "$TMP/human"
    done
done < "$TMP/batch"

if [ -f "$TMP/guard_hits" ]; then
    while IFS='|' read -r number path guarded; do
        refuse "#$number touches $path, under requires_human path $guarded"
    done < "$TMP/guard_hits"
fi

# ---- condition: the combined result ---------------------------------------
# Last, because it is the expensive one: no point building a merge for a batch
# already refused on a cheap condition.
if [ "$REFUSALS" = 0 ]; then
    if [ -n "$EXPLAIN" ]; then
        [ "$GATE_RESULT" = "green" ] || refuse "combined-result gate reported $GATE_RESULT"
    else
        echo ""
        echo "-- combined-result gate --"
        if sh "$(dirname "$0")/merge_batch.sh" --test "$TEST_CMD" "$@"; then
            GATE_RESULT=green
        else
            GATE_RESULT=red
            refuse "the combined result is not green — this is a coordination incident, not one lane's bug"
        fi
    fi
fi

echo ""
if [ "$REFUSALS" -gt 0 ]; then
    echo "NOT AUTHORIZED: $REFUSALS condition(s) failed. Nothing was merged."
    exit 1
fi

echo "AUTHORIZED: every condition in $POLICY holds."
[ "$DRY" = 1 ] && { echo "(--dry-run: nothing merged)"; exit 0; }
[ -n "$EXPLAIN" ] && { echo "(--explain: nothing merged)"; exit 0; }

# ---- land it, carrying the evidence --------------------------------------
# A machine merge is more auditable than a human one, not less: the message
# records which gate ran, over what, and what it found.
for pr in "$@"; do
    gh pr merge "$pr" --merge \
        --subject "Merge pull request #$pr" \
        --body "Authorized by $POLICY (version $VERSION).

Combined-result gate: $GATE_RESULT
  batch:   $(echo "$@" | tr ' ' ',')
  command: $TEST_CMD
  merger:  $MERGER

Conditions checked: combined gate, distinct merger, requires_human paths, batch ceiling."
    echo "merged #$pr"
done
