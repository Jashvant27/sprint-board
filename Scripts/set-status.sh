#!/bin/zsh
# Moves one card of the Sprint Board to a lane from the command line.
#
#   Scripts/set-status.sh <jira-key-or-title-substring> <todo|prog|block|done> [week]
#
# [week] is "4" (this quarter), "Q4/4" or "2026/Q4/4"; default this week. The match has to be
# unique, else the matches are listed and the script exits 2. The week files are in ~/Documents and
# readable here, but the app owns them, so the change goes through its sprintboard:// URL scheme:
# the app moves the card, writes the file and reloads the widget. The app has to have run once.
set -eu
here=${0:A:h}
source "$here/_common.sh"

query=${1:-}; lane=${2:-}; spec=${3:-}
[[ -z $query || -z $lane ]] && { echo "usage: $0 <jira-key-or-title-substring> <todo|prog|block|done> [week]" >&2; exit 2; }
case $lane in
  todo|prog|block|done) ;;
  *) echo "lane must be todo, prog, block or done" >&2; exit 2 ;;
esac
read y q k <<< "$(resolve_week "$spec")"
file=$(week_file "$y" "$q" "$k")
[[ -f $file ]] || { echo "no board for Week $k · Q$q $y ($file)" >&2; exit 2; }
id=$(unique_card "$file" "$query")
open "sprintboard://set?week=$y/Q$q/$k&id=$id&lane=$lane"
echo "Week $k · Q$q $y: $(find_card "$file" "$query" | cut -f4) -> $lane"
