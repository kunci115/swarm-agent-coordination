#!/usr/bin/env sh
# run.sh — one run of the experiment, end to end.
#
#   sh run.sh [--condition stale-green|re-gated] [WORKDIR]
#
# Builds the fixture, runs both lanes, grades them alone and merged, prints one
# JSON line. Repeat it to get a distribution; one run of anything involving a
# language model is one sample, not a result.
#
# Conditions
#
#   stale-green  Both lanes open against the same base and are never re-gated
#                against the base they will actually land on. This is the
#                default state of a pull request: its checks do not re-run when
#                its base moves, so a branch sits green against a base that has
#                changed underneath it.
#
#   re-gated     The second lane sees the first one landed before it cuts its
#                migration. This is the condition the kit's rules are meant to
#                produce, and it is the negative control: an instrument that
#                only ever reports a defect measures nothing.

set -eu
HERE=$(cd "$(dirname "$0")" && pwd)

CONDITION=stale-green
case "${1:-}" in
    --condition) CONDITION="${2:?--condition needs a value}"; shift 2 ;;
esac
WORK="${1:-$(mktemp -d)/repo}"

sh "$HERE/fixture.sh" "$WORK" > /dev/null

A=feature/booking-notes
B=feature/job-priority

case "$CONDITION" in
    stale-green)
        sh "$HERE/lanes/lane.sh" "$WORK" "$A" BOOKINGS notes    0003a >&2
        sh "$HERE/lanes/lane.sh" "$WORK" "$B" JOBS     priority 0003b >&2
        ;;
    re-gated)
        sh "$HERE/lanes/lane.sh" "$WORK" "$A" BOOKINGS notes    0003a >&2
        # the first lane lands before the second one starts, so the second
        # cuts from the head it will actually merge onto
        (cd "$WORK" && git checkout -q dev && git merge -q --no-ff --no-edit -m "merge $A" "$A")
        sh "$HERE/lanes/lane.sh" "$WORK" "$B" JOBS     priority 0003b >&2
        ;;
    *)
        echo "unknown condition: $CONDITION (stale-green | re-gated)" >&2
        exit 2 ;;
esac

RESULT=$(sh "$HERE/grade.sh" "$WORK" "$A" "$B")
printf '%s\n' "$RESULT" | sed "s/^{/{\"condition\":\"$CONDITION\",/"
