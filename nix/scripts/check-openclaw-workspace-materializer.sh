#!/bin/sh
set -eu

script="${OPENCLAW_WORKSPACE_MATERIALIZER:?OPENCLAW_WORKSPACE_MATERIALIZER is required}"

work="$(mktemp -d)"
stale="$work/workspace/skills/stale"
current="$work/workspace/AGENTS.md"

mkdir -p "$stale" "$work/src"
printf 'stale\n' > "$stale/SKILL.md"
printf 'old-doc\n' > "$current"
printf '%s\n%s\n' "$stale" "$current" > "$work/manifest"
printf 'new-doc\n' > "$work/src/AGENTS.md"
printf '%s\t%s\n' "$work/src/AGENTS.md" "$current" > "$work/source.tsv"

"$script" "$work/manifest" "$work/source.tsv"

test ! -e "$stale"
test -f "$current"
grep -q 'new-doc' "$current"
grep -Fxq "$current" "$work/manifest"
! grep -Fxq "$stale" "$work/manifest"

empty_work="$(mktemp -d)"
empty_stale="$empty_work/workspace/skills/stale"

mkdir -p "$empty_stale"
printf 'stale\n' > "$empty_stale/SKILL.md"
printf '%s\n' "$empty_stale" > "$empty_work/manifest"
: > "$empty_work/source.tsv"

"$script" "$empty_work/manifest" "$empty_work/source.tsv"

test ! -e "$empty_stale"
test ! -s "$empty_work/manifest"
