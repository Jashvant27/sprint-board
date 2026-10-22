#!/bin/zsh
# Prints a week's cards, lane by lane, straight from its JSON file (no app needed).
#
#   Scripts/list-cards.sh [week]      # "4", "Q4/4" or "2026/Q4/4"; default this week
#   Scripts/list-cards.sh --weeks     # every week that has a file
set -eu
here=${0:A:h}
source "$here/_common.sh"

if [[ ${1:-} == "--weeks" ]]; then
  find "$root" -name 'Week *.json' | sed -E "s#^$root/##; s#/Q([0-9])/Week ([0-9]+)\.json\$#\tQ\1\tWeek \2#" | sort -t$'\t' -k1,1n -k2,2 -k3,3V
  exit 0
fi

read y q k <<< "$(resolve_week "${1:-}")"
file=$(week_file "$y" "$q" "$k")
[[ -f $file ]] || { echo "no board for Week $k · Q$q $y ($file)" >&2; exit 2; }
python3 -I - "$file" <<'PY'
import json, sys
board = json.load(open(sys.argv[1]))
w = board["week"]
print(f'Week {w["week"]} · Q{w["quarter"]} {w["year"]}  ({sys.argv[1]})')
names = {"todo": "TO DO", "prog": "IN PROGRESS", "block": "BLOCKED", "done": "DONE"}
for lane in board["lanes"]:
    cards = lane["cards"]
    print(f'\n{names.get(lane["lane"], lane["lane"])} ({len(cards)})')
    for c in cards:
        key = f'[{c["jiraKey"]}] ' if c.get("jiraKey") else ""
        tail = ""
        if m := c.get("movedTo"):
            tail = f'  ~~ moved to Week {m["week"]} · Q{m["quarter"]} {m["year"]}'
        elif m := c.get("movedFrom"):
            tail = f'  (from Week {m["week"]} · Q{m["quarter"]} {m["year"]})'
        print(f'  - {key}{c["title"]}{tail}')
PY
