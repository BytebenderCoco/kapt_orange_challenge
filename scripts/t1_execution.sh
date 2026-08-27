#!/usr/bin/env bash
# Run the t1 experiments in parallel, one Julia process per instance. Hardcoded to
# launch setA instances setA-04..08 (by sorted name) all at once,
# then wait for them — no per-instance RAM budgeting or job-count gate.
#
# Results land in t1_results/<RUN_ID>/ (one NN.json per instance), keyed by a run
# id that defaults to the current local server time (YYYYMMDD-HHMMSS). Logs are
# discarded.
#
# The experiment parameters (time limit, lex-descent depth) are hardcoded below.
#
# Env overrides:
#   RUN_ID      run id (default: local time stamp)
#   DATA_DIR    directory holding the -net/-tm/-scenario.json files
#   JULIA       path to the julia binary (default: `julia` on PATH)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve julia (PATH, then juliaup, then a bare `julia` as a last resort).
if command -v julia >/dev/null 2>&1; then
    JULIA="${JULIA:-$(command -v julia)}"
elif [ -x "$HOME/.juliaup/bin/julia" ]; then
    JULIA="${JULIA:-$HOME/.juliaup/bin/julia}"
else
    JULIA="${JULIA:-julia}"
fi

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
DATA_DIR="${DATA_DIR:-$REPO_ROOT/data}"
TIME_LIMIT=3600   # hardcoded: 1 hour per instance
MAX_LEVELS=3      # hardcoded: lex-descent depth per instance
RESULTS_DIR="$REPO_ROOT/t1_results/$RUN_ID"

# Per-instance HiGHS threads (hardcoded, not an env knob). With instances setA-04..08
# launched, each runs on 4 cores (4×5 = 20 cores total). Unlisted instances → 1.
threads_for() {
    case "$1" in
        setA-04|setA-05|setA-06|setA-07|setA-08) echo 4 ;;
        *)                                       echo 1 ;;
    esac
}

mkdir -p "$RESULTS_DIR"

# Ensure the project environment is instantiated (downloads the HiGHS artifact on
# the first run; idempotent and fast afterwards). Abort early on failure so a bad
# environment does not fan out into one confusing failure per instance.
echo "==> instantiating project environment..."
if ! "$JULIA" --project="$REPO_ROOT" -e 'using Pkg; Pkg.instantiate()'; then
    echo "ERROR: Pkg.instantiate() failed; aborting." >&2
    exit 1
fi

echo "runId=$RUN_ID instances=5 (parallel) timeLimit=${TIME_LIMIT}s maxLevels=${MAX_LEVELS}"
echo "resultsDir=$RESULTS_DIR"

# Discover instance stems (e.g. "setA-01") from the -net.json files in DATA_DIR.
solve_one() {
    name="$1"
    threads="$(threads_for "$name")"
    "$JULIA" --project="$REPO_ROOT" "$REPO_ROOT/scripts/t1_solve_instance.jl" \
        "$name" --output "$RESULTS_DIR" --data-dir "$DATA_DIR" --time-limit "$TIME_LIMIT" \
        --max-levels "$MAX_LEVELS" --threads "$threads" >/dev/null 2>&1
}

# Hardcoded to instances setA-04..08 (by sorted glob), all started in parallel. The
# glob expands in sorted order, so [@]:3:5 is setA-04..08.
netFiles=("$DATA_DIR"/*-net.json)
for netFile in "${netFiles[@]:3:5}"; do
    name="$(basename "$netFile" -net.json)"
    echo "start $name (threads $(threads_for "$name"))"
    solve_one "$name" &
done

# Drain the background solves.
wait

count="$(find "$RESULTS_DIR" -maxdepth 1 -name '*.json' | wc -l)"
echo "done: $count instance result(s) written to $RESULTS_DIR"
