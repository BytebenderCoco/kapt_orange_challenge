#!/usr/bin/env bash
# Launch the full t0 experiment run in the background so it does not block the
# terminal and keeps running after you disconnect.
#
# Usage:
#   bash scripts/run_on_server.sh          # detached via nohup (default)
#   bash scripts/run_on_server.sh tmux     # inside a tmux session you can reattach
#
# Env overrides:
#   RUN_ID      run id (default: local server time stamp)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RESULTS_DIR="$REPO_ROOT/t0_results/$RUN_ID"
# Single detached-run log, kept out of git (see .gitignore); per-instance logs
# are discarded by t0_execution.sh.
LOGS_DIR="$REPO_ROOT/logs/$RUN_ID"

# Locate julia: prefer the one on PATH, fall back to a juliaup install at
# ~/.juliaup/bin/julia (common on servers where juliaup only edited .profile).
if command -v julia >/dev/null 2>&1; then
    export JULIA="$(command -v julia)"
elif [ -x "$HOME/.juliaup/bin/julia" ]; then
    export JULIA="$HOME/.juliaup/bin/julia"
else
    export JULIA="julia"
fi

MODE="${1:-nohup}"
mkdir -p "$LOGS_DIR"

if [ "$MODE" = "tmux" ]; then
    echo "==> launching in tmux session: orange-$RUN_ID"
    tmux new-session -d -s "orange-$RUN_ID" \
        "cd '$REPO_ROOT' && RUN_ID='$RUN_ID' bash scripts/t0_execution.sh"
    echo "attach with: tmux attach -t orange-$RUN_ID"
else
    RUN_LOG="$LOGS_DIR/run.log"
    echo "==> launching detached (nohup), runId=$RUN_ID"
    nohup env RUN_ID="$RUN_ID" bash "$REPO_ROOT/scripts/t0_execution.sh" \
        > "$RUN_LOG" 2>&1 &
    echo $! > "$LOGS_DIR/run.pid"
    echo "pid:  $(cat "$LOGS_DIR/run.pid")"
    echo "log:  $RUN_LOG"
    echo "monitor: tail -f $RUN_LOG"
fi

echo "results: $RESULTS_DIR"
