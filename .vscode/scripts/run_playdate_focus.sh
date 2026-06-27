#!/usr/bin/env bash
# Launch the most recent .pdx with the Playdate Simulator and bring it to front
set -euo pipefail

# Find the most recently modified .pdx folder in builds/
pdx_path="$(ls -td "${PWD}/builds"/*.pdx 2>/dev/null | head -n1 || true)"
if [ -z "$pdx_path" ]; then
  echo "No .pdx found in ${PWD}/builds. Build the project first."
  exit 1
fi

echo "Opening: $pdx_path"
open -a "Playdate Simulator" "$pdx_path"

# Give the app a moment to launch, then activate it so the window appears correctly
sleep 0.25
osascript -e 'tell application "Playdate Simulator" to activate' || true

exit 0
