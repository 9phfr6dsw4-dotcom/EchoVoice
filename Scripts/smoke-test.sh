#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGED="$ROOT_DIR/dist/verify-extracted/EchoVoice.app"
test -x "$PACKAGED/Contents/MacOS/EchoVoice"

# Launch a copy from a clean place, away from the build folders.
SMOKE_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/echovoice-smoke.XXXXXX")"
trap 'pkill -x EchoVoice >/dev/null 2>&1 || true; rm -rf "$SMOKE_DIR"' EXIT
ditto "$PACKAGED" "$SMOKE_DIR/EchoVoice.app"

# MLX check: loads the GPU library from inside the app and does a tiny calculation.
# Informational on CI runners, whose virtual GPUs may not support it; the file checks in
# package-app.sh are the strict part.
if output="$("$SMOKE_DIR/EchoVoice.app/Contents/MacOS/EchoVoice" --mlx-self-test 2>&1)"; then
    printf '%s\n' "$output"
else
    printf 'warning: MLX self-test did not pass on this runner:\n%s\n' "$output"
fi

open -n -g "$SMOKE_DIR/EchoVoice.app"
for _ in $(seq 1 10); do
    if pgrep -x EchoVoice >/dev/null 2>&1; then
        sleep 3
        if pgrep -x EchoVoice >/dev/null 2>&1; then
            printf 'Launch smoke test passed: EchoVoice started from a clean location and kept running.\n'
            exit 0
        fi
    fi
    sleep 1
done
printf 'EchoVoice did not keep running after launch.\n' >&2
exit 1
