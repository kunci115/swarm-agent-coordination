#!/usr/bin/env sh
# strip_ai_trailers.sh — remove AI-attribution trailers from commit messages.
#
#   scripts/strip_ai_trailers.sh <RANGE>       # e.g. origin/dev..HEAD
#   scripts/strip_ai_trailers.sh --check <RANGE>
#   scripts/strip_ai_trailers.sh --last <N>    # rewrite last N commits
#
# This is the REPAIR path, for trailers that are already committed. The fix is
# scripts/commit-msg-example, a hook that strips them as the message is written:
#
#   ln -sf ../../scripts/commit-msg-example .git/hooks/commit-msg
#
# Install that once and this script becomes something you never need again.
#
# Why prefer the hook: this script rewrites every SHA in the range. Run it on a
# pull request that has already gone green and you re-run the entire gate,
# invalidate every review, and need a force-push to land work that was already
# landable. Do it BEFORE pushing, or better, do not need it.
#
# Whether AI attribution appears in history at all is the repo owner's call and
# opt-in — see the "Repo policy: AI attribution" section of AGENTS.md. It is a
# preference about how history reads, not a coordination rule.
#
# Default behavior rewrites commits (filter-branch). --check only reports.

set -eu

PATTERN='(Co-Authored-By|Authored-By|Generated-by|Generated with|Claude-Session|AI-Model).*(Claude|GPT|OpenAI|Anthropic|Copilot|Gemini|Cursor|DeepSeek|AI|generative)'

RANGE=""
CHECK=""
case "${1:-}" in
    --check) CHECK=1; RANGE="${2:?usage: strip_ai_trailers.sh --check RANGE}" ;;
    --last)  RANGE="HEAD~${2:?usage: strip_ai_trailers.sh --last N}..HEAD" ;;
    *)       RANGE="${1:?usage: strip_ai_trailers.sh RANGE | --check RANGE | --last N}" ;;
esac

FOUND=$(git log --format="%H %b" "$RANGE" | grep -iE "$PATTERN" || true)

if [ -z "$FOUND" ]; then
    echo "OK: no AI trailers in $RANGE"
    exit 0
fi

echo "Found AI trailers in $RANGE:"
echo "$FOUND" | sed 's/^/  /'

if [ -n "$CHECK" ]; then
    echo ""
    echo "Run without --check to strip them (rewrites commits in $RANGE):"
    echo "  scripts/strip_ai_trailers.sh $RANGE"
    exit 1
fi

echo ""
echo "Rewriting commits in $RANGE (stripping trailers)..."
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --msg-filter "
    sed -E '/^Co-[Aa]uthored-[Bb]y:.*(Claude|GPT|OpenAI|Anthropic|Copilot|Gemini|Cursor|DeepSeek|AI)/d;
            /^Authored-By:.*(Claude|GPT|OpenAI|Anthropic|Copilot|Gemini|Cursor|DeepSeek|AI)/d;
            /^Generated-[Bb]y:.*(Claude|GPT|OpenAI|Anthropic|Copilot|Gemini|Cursor|DeepSeek|AI)/d;
            /^Generated with .*(Claude|GPT|OpenAI|Anthropic|Copilot|Gemini|Cursor|DeepSeek|AI)/d;
            /^Claude-Session:/d;
            /^AI-Model:/d' | sed -e :a -e '/^\n*$/{\$d;N;ba' -e '}'
" -- "$RANGE"

echo ""
echo "Done. Verify with:"
echo "  scripts/strip_ai_trailers.sh --check $RANGE"
echo ""
echo "Then push with --force-with-lease (the rewrite changed SHAs)."
