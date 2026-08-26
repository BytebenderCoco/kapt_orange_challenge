#!/usr/bin/env bash
# Run the t0 experiments for every setA instance in parallel, one Julia process
# per instance. This is a thin wrapper around scripts/run_scheduler.jl, which
# does the actual work-queue scheduling:
#
#   * instances start as soon as a running solve finishes (no more "waves"),
#   * admission is gated by a RAM budget (MAX_RAM_GB, required) and a CPU ceiling
#     (MAX_PROCS, default = detected cores), each instance weighted by a static
#     peak-RAM estimate.
#
# Results land in t0_results/<RUN_ID>/ (one NN.json per instance + summary.csv),
# keyed by a run id that defaults to the current local server time
# (YYYYMMDD-HHMMSS). Logs are discarded.
#
# Env overrides:
#   RUN_ID      run id (default: local time stamp)
#   MAX_RAM_GB  required fixed RAM budget in GiB
#   MAX_PROCS   max concurrent instance solves (default: detected cores)
#   TIME_LIMIT  per-instance solver time limit in seconds (default: 900)
#   MAX_LEVELS  lex-descent depth per instance (default: solve_instance.jl's 8)
#   DATA_DIR    directory holding the -net/-tm/-scenario.json files
#   JULIA       path to the julia binary (default: `julia` on PATH)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve julia and export everything the scheduler reads from the environment
# (an exported empty MAX_RAM_GB/MAX_PROCS is ignored by the scheduler).
if command -v julia >/dev/null 2>&1; then
    export JULIA="${JULIA:-$(command -v julia)}"
elif [ -x "$HOME/.juliaup/bin/julia" ]; then
    export JULIA="${JULIA:-$HOME/.juliaup/bin/julia}"
else
    export JULIA="${JULIA:-julia}"
fi

export RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
export DATA_DIR="${DATA_DIR:-$REPO_ROOT/data}"
export TIME_LIMIT="${TIME_LIMIT:-900}"
export MAX_LEVELS="${MAX_LEVELS:-}"
export MAX_RAM_GB="${MAX_RAM_GB:-}"
export MAX_PROCS="${MAX_PROCS:-}"

# Ensure the project environment is instantiated (downloads the HiGHS artifact on
# the first run; idempotent and fast afterwards). Abort early on failure so a bad
# environment does not fan out into one confusing failure per instance.
echo "==> instantiating project environment..."
if ! "$JULIA" --project="$REPO_ROOT" -e 'using Pkg; Pkg.instantiate()'; then
    echo "ERROR: Pkg.instantiate() failed; aborting." >&2
    exit 1
fi

exec "$JULIA" --project="$REPO_ROOT" "$REPO_ROOT/scripts/run_scheduler.jl"
