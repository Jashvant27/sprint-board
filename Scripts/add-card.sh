#!/bin/zsh
# Adds a card to the Sprint Board from the command line.
#
#   Scripts/add-card.sh "<title>" [jira-key] [todo|prog|block|done] [week]
#
# Lane defaults to todo, week to this week ("4", "Q4/4" or "2026/Q4/4"). Goes through the app's
# sprintboard:// URL scheme; the app writes the week file (creating it) and reloads the widget.
set -eu
here=${0:A:h}
source "$here/_common.sh"

title=${1:-}; jira=${2:-}; lane=${3:-todo}; spec=${4:-}
[[ -z $title ]] && { echo "usage: $0 \"<title>\" [jira-key] [todo|prog|block|done] [week]" >&2; exit 2; }
case $lane in
  todo|prog|block|done) ;;
  *) echo "lane must be todo, prog, block or done" >&2; exit 2 ;;
esac
read y q k <<< "$(resolve_week "$spec")"
open "sprintboard://add?week=$y/Q$q/$k&title=$(urlencode "$title")&jira=$(urlencode "$jira")&lane=$lane"
echo "Week $k · Q$q $y: added \"$title\"${jira:+ [$jira]} to $lane"
