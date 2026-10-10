#!/usr/bin/env bash
# Start the slicer on a virtual display and check that it comes up.
#
#   scripts/smoke-test.sh <command> [args...]
#
# Passes when the app is still running after SMOKE_SECONDS (default 60) and
# has loaded its bundled fonts. That is far from a full test, but it catches
# what an unattended release must not ship: a missing library, a crash on
# start-up, or resources the app cannot find.
set -uo pipefail

seconds=${SMOKE_SECONDS:-60}
log=$(mktemp)
trap 'rm -f "$log"' EXIT

# The app exits at start-up when it cannot create its config directory, and a
# fresh container has no ~/.config to create it in.
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"

# stdbuf: the app prints its font lines with stdio, which buffers them when
# writing to a file, and the buffer is lost when timeout stops the app.
start=$SECONDS
xvfb-run -a -s '-screen 0 1920x1080x24' \
  timeout --kill-after=10 "$seconds" stdbuf -oL -eL "$@" >"$log" 2>&1
status=$?
ran=$((SECONDS - start))

fonts=$(grep -c 'add font of .* returns 1' "$log")

# timeout exits 124 when it had to stop the command, which is the good case:
# the app was still running. The app itself ignores SIGTERM, so when it is
# timeout's direct child (no launcher in between) it takes the SIGKILL ten
# seconds later and the status is 137; only after the full time does that
# mean the same thing, since 137 is also what an early OOM kill looks like.
if [[ ( $status -eq 124 || ( $status -eq 137 && $ran -ge $seconds ) ) && $fonts -ge 1 ]]; then
  echo "Smoke test passed: still running after ${seconds}s, $fonts font(s) loaded."
  exit 0
fi

echo "Smoke test FAILED: exit status $status after ${ran}s (124, or 137 after the full time, means still running), $fonts font(s) loaded." >&2
echo "--- last 80 lines of output ---" >&2
tail -n 80 "$log" >&2
exit 1
