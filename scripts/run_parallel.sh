#!/usr/bin/env bash
# Run the t0 experiments for every setA instance in parallel, one Julia process
# per instance, with a bounded number of concurrent solves.
#
# Results and logs land in runs/<RUN_ID>/{results,logs}, keyed by a run id that
# defaults to the current local server time (YYYYMMDD-HHMMSS).
#
# Env overrides:
#   RUN_ID     run id (default: local time stamp)
#   MAX_PROCS  max concurrent instance solves (default: min(8, detected cores))
#   TIME_LIMIT per-instance solver time limit in seconds (default: 900)
#   DATA_DIR   directory holding the -net/-tm/-scenario.json files
#   JULIA      path to the julia binary (default: `julia` on PATH)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JULIA="${JULIA:-julia}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RUN_DIR="$REPO_ROOT/runs/$RUN_ID"
RESULTS_DIR="$RUN_DIR/results"
LOGS_DIR="$RUN_DIR/logs"
DATA_DIR="${DATA_DIR:-$REPO_ROOT/data}"
TIME_LIMIT="${TIME_LIMIT:-900}"

# Detect the number of cores (Linux: nproc, macOS: sysctl), with a safe fallback.
detect_cores() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 4
    fi
}

CORES="$(detect_cores)"
if [ "${MAX_PROCS:-}" = "" ]; then
    if [ "$CORES" -lt 8 ]; then
        MAX_PROCS="$CORES"
    else
        MAX_PROCS=8
    fi
fi

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
echo "runId=$RUN_ID cores=$CORES maxProcs=$MAX_PROCS timeLimit=${TIME_LIMIT}s"
echo "resultsDir=$RESULTS_DIR"

# Ensure the project environment is instantiated (downloads the HiGHS artifact on
# the first run; idempotent and fast afterwards). Abort early on failure so a bad
# environment does not fan out into one confusing failure per instance.
echo "==> instantiating project environment..."
if ! "$JULIA" --project="$REPO_ROOT" -e 'using Pkg; Pkg.instantiate()'; then
    echo "ERROR: Pkg.instantiate() failed; aborting." >&2
    exit 1
fi

# Discover instance names from the -net.json files in the data dir.
instances=()
while IFS= read -r f; do
    instances+=("$(basename "$f" -net.json)")
done < <(find "$DATA_DIR" -maxdepth 1 -name '*-net.json' | sort)

if [ "${#instances[@]}" -eq 0 ]; then
    echo "No instances found in $DATA_DIR" >&2
    exit 1
fi
echo "==> running ${#instances[@]} instances (${instances[*]})"

# One Julia process per instance, logging to its own file so parallel output
# never interleaves.
run_instance() {
    local name="$1"
    "$JULIA" --project="$REPO_ROOT" "$REPO_ROOT/scripts/solve_instance.jl" \
        "$name" --output "$RESULTS_DIR" --data-dir "$DATA_DIR" --time-limit "$TIME_LIMIT" \
        > "$LOGS_DIR/$name.log" 2>&1
}

# Bounded job pool (bash-3.2 safe: waves of MAX_PROCS). Track each job's exit
# code so the script reports failure instead of silently succeeding when an
# instance solve returns non-zero.
pids=()
failures=0
for name in "${instances[@]}"; do
    run_instance "$name" &
    pids+=($!)
    if [ "${#pids[@]}" -ge "$MAX_PROCS" ]; then
        for pid in "${pids[@]}"; do
            wait "$pid" || failures=$((failures + 1))
        done
        pids=()
    fi
done
for pid in "${pids[@]}"; do
    wait "$pid" || failures=$((failures + 1))
done

count="$(find "$RESULTS_DIR" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')"
echo "done: $count instance result(s) written to $RESULTS_DIR"
if [ "$failures" -gt 0 ]; then
    echo "WARNING: $failures instance(s) failed (non-zero exit code)." >&2
    exit 1
fi
