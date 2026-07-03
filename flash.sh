#!/bin/bash
#
# Flash the Corne from the latest GitHub Actions firmware build.
#
# Usage:
#   ./flash.sh          # flash left, then right
#   ./flash.sh left     # flash only the left half
#   ./flash.sh right    # flash only the right half

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW_DIR="$REPO_DIR/firmware"
VOLUME="/Volumes/NICENANO"
WORKFLOW="build.yml"
BRANCH="main"

SIDES=("left" "right")
if [ $# -ge 1 ]; then
  case "$1" in
    left|right) SIDES=("$1") ;;
    *) echo "Usage: $0 [left|right]"; exit 1 ;;
  esac
fi

echo "Looking up the latest '$WORKFLOW' run on '$BRANCH'..."
run_id=$(gh run list --workflow "$WORKFLOW" --branch "$BRANCH" --limit 1 \
  --json databaseId -q '.[0].databaseId')
if [ -z "$run_id" ]; then
  echo "ERROR: no workflow runs found." >&2
  exit 1
fi

status=$(gh run view "$run_id" --json status -q '.status')
if [ "$status" != "completed" ]; then
  echo "Run $run_id is still '$status' — waiting for it to finish..."
  gh run watch "$run_id" --exit-status
else
  conclusion=$(gh run view "$run_id" --json conclusion -q '.conclusion')
  if [ "$conclusion" != "success" ]; then
    echo "ERROR: latest run concluded with '$conclusion' — fix CI first." >&2
    exit 1
  fi
fi

echo "Using run $run_id: $(gh run view "$run_id" \
  --json displayTitle,headSha -q '.displayTitle + " (" + .headSha[0:7] + ")"')"

rm -rf "$FW_DIR"
gh run download "$run_id" --name firmware --dir "$FW_DIR"
echo "Downloaded firmware to $FW_DIR"

flash_side() {
  local side="$1"
  local file="$FW_DIR/corne_${side}-nice_nano_v2-zmk.uf2"
  if [ ! -f "$file" ]; then
    echo "ERROR: $file not found in the downloaded artifact." >&2
    exit 1
  fi

  echo ""
  echo ">>> Double-press the reset button on the *${side}* half..."
  until [ -d "$VOLUME" ]; do sleep 1; done

  echo "Bootloader mounted, copying $(basename "$file")..."
  # The nice!nano reboots the instant the UF2 finishes writing, so cp often
  # reports an I/O error even on success — the volume unmounting is the
  # real success signal.
  cp -X "$file" "$VOLUME/" 2>/dev/null || true

  local i
  for i in $(seq 1 30); do
    if [ ! -d "$VOLUME" ]; then
      echo "The $side half is flashed and rebooting."
      return 0
    fi
    sleep 1
  done
  echo "ERROR: $VOLUME never unmounted — the flash may have failed." >&2
  exit 1
}

for side in "${SIDES[@]}"; do
  flash_side "$side"
done

echo ""
echo "Done."
