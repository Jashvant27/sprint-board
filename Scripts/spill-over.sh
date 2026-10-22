#!/bin/zsh
# Spills one card over to next week: it stays in this week's lane, struck through, and a copy goes
# to the same lane of next week (file created if missing).
#
#   Scripts/spill-over.sh <jira-key-or-title-substring> [week]
#
# The match has to be unique, else the matches are listed and the script exits 2.
set -eu
here=${0:A:h}
source "$here/_common.sh"

query=${1:-}; spec=${2:-}
[[ -z $query ]] && { echo "usage: $0 <jira-key-or-title-substring> [week]" >&2; exit 2; }
read y q k <<< "$(resolve_week "$spec")"
file=$(week_file "$y" "$q" "$k")
[[ -f $file ]] || { echo "no board for Week $k · Q$q $y ($file)" >&2; exit 2; }
id=$(unique_card "$file" "$query")
open "sprintboard://spill?week=$y/Q$q/$k&id=$id"
echo "Week $k · Q$q $y: spilled \"$(find_card "$file" "$query" | cut -f4)\" over to next week"
