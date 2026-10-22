#!/bin/zsh
# Points the project at your Apple Developer team, so Xcode signs it and the app and the widget
# share their App Group on your Mac.
#
#   Scripts/set-team.sh <TEAM_ID> [bundle-prefix]
#
# TEAM_ID is the 10-character id of your team (Xcode → Settings → Accounts → your Apple ID → the
# team's "Team ID"; a free personal team works). The optional bundle prefix (default: the one in
# project.yml, e.g. com.example) is yours to pick; it only has to be unique on your Mac.
#
# Rewrites the team id and the prefix wherever they occur: project.yml, the two entitlements
# files, Info.plist, Shared/SharedStore.swift (the App Group id the widget reads) and the
# .xcodeproj, then regenerates the project with xcodegen when it is installed. The App Group id is
# Team-ID-prefixed on purpose: a "group."-prefixed id is refused for a personal team.
set -eu
here=${0:A:h}
proj=${here:h}
team=${1:-}
prefix=${2:-}
[[ $team =~ ^[A-Z0-9]{10}$ ]] || { echo "usage: $0 <TEAM_ID (10 characters)> [bundle-prefix]" >&2; exit 2; }
if [[ -n $prefix && ! $prefix =~ ^[A-Za-z0-9.-]+$ ]]; then echo "bundle prefix must look like com.example" >&2; exit 2; fi

old_team=$(sed -nE 's/^ *DEVELOPMENT_TEAM: *([A-Z0-9]+).*/\1/p' "$proj/project.yml" | head -1)
old_prefix=$(sed -nE 's/^ *bundleIdPrefix: *([A-Za-z0-9.-]+).*/\1/p' "$proj/project.yml" | head -1)
new_prefix=${prefix:-$old_prefix}
[[ -n $old_team && -n $old_prefix ]] || { echo "cannot read the current team or prefix from project.yml" >&2; exit 1; }

files=(
  project.yml
  Shared/SharedStore.swift
  SprintBoard/SprintBoard.entitlements
  SprintBoardWidget/SprintBoardWidget.entitlements
  SprintBoard/Info.plist
  SprintBoard.xcodeproj/project.pbxproj
)
for f in $files; do
  [[ -f $proj/$f ]] || continue
  sed -i '' -e "s/$old_team/$team/g" -e "s/${old_prefix//./\\.}\.sprintboard/$new_prefix.sprintboard/g" \
      -e "s/bundleIdPrefix: $old_prefix/bundleIdPrefix: $new_prefix/" "$proj/$f"
done
echo "team $old_team -> $team, bundle prefix $old_prefix -> $new_prefix"
echo "App Group: $team.$new_prefix.sprintboard"

if command -v xcodegen >/dev/null; then
  (cd "$proj" && xcodegen generate)
else
  echo "xcodegen is not installed (brew install xcodegen): the .xcodeproj was patched in place instead"
fi
echo "Now open SprintBoard.xcodeproj in Xcode and press Run. If the app was already running, quit it first: a running copy keeps its old entitlements."
