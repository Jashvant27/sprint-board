# Sourced by the Sprint Board scripts. The week files are plain JSON under ~/Documents, so the
# scripts read them directly; writes go through the app's sprintboard:// URL scheme.
root="$HOME/Documents/Sprint Boards"

# Prints "year quarter week" for today: ISO week → quarter = (week-1)/13+1 capped at 4,
# quarter week = ISO week - 13*(quarter-1). Same rule as Shared/WeekRule.swift.
current_week() {
  local iy iw q
  iy=$(date +%G); iw=$((10#$(date +%V)))
  q=$(( (iw - 1) / 13 + 1 )); (( q > 4 )) && q=4
  echo "$iy $q $((iw - 13 * (q - 1)))"
}

# resolve_week [spec] → "year quarter week". spec: "4" (this quarter), "Q4/4" (this year),
# "2026/Q4/4"; empty = this week.
resolve_week() {
  local spec=${1:-} cy cq cw
  read cy cq cw <<< "$(current_week)"
  [[ -z $spec ]] && { echo "$cy $cq $cw"; return 0; }
  local -a parts
  parts=("${(@s:/:)spec}")
  parts=("${parts[@]//Q/}")
  parts=("${parts[@]//Week /}")
  case ${#parts} in
    1) echo "$cy $cq ${parts[1]}" ;;
    2) echo "$cy ${parts[1]} ${parts[2]}" ;;
    3) echo "${parts[1]} ${parts[2]} ${parts[3]}" ;;
    *) echo "bad week: $spec (use 4, Q4/4 or 2026/Q4/4)" >&2; return 2 ;;
  esac
}

week_file() { echo "$root/$1/Q$2/Week $3.json"; }

urlencode() { python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# find_card <file> <query> [--all]: one "id<TAB>lane<TAB>key<TAB>title" line per match. A Jira key
# that equals the query wins; else the title or key has to contain it (case-insensitive).
# Spilled cards are left out unless --all.
find_card() {
  python3 -I - "$1" "$2" "${3:-}" <<'PY'
import json, sys
path, query, mode = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
try:
    board = json.load(open(path))
except FileNotFoundError:
    sys.exit(0)
cards = [c for lane in board["lanes"] for c in lane["cards"]]
if mode != "--all":
    cards = [c for c in cards if not c.get("movedTo")]
exact = [c for c in cards if (c.get("jiraKey") or "").lower() == query]
hits = exact or [c for c in cards if query in c["title"].lower() or query in (c.get("jiraKey") or "").lower()]
for c in hits:
    print(f'{c["id"]}\t{c["lane"]}\t{c.get("jiraKey") or "-"}\t{c["title"]}')
PY
}

# unique_card <file> <query> → prints the id of the one match, or lists the matches and returns 2.
unique_card() {
  local -a matches
  matches=("${(@f)$(find_card "$1" "$2")}")
  matches=("${(@)matches:#}")
  if (( ${#matches} == 1 )); then
    echo "${matches[1]%%$'\t'*}"
    return 0
  fi
  if (( ${#matches} == 0 )); then
    echo "no card matches \"$2\" in $1" >&2
  else
    echo "${#matches} cards match \"$2\"; be more specific:" >&2
    printf '  %s\n' "${matches[@]}" | cut -f2- >&2
  fi
  return 2
}
