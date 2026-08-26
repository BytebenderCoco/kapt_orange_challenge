#!/usr/bin/env bash
# Run the t0 experiments in parallel, one Julia process per instance. This is a
# thin wrapper around scripts/run_scheduler.jl, which is hardcoded to launch the
# first 10 setA instances (setA-01..10) all at once — no RAM budgeting, no
# admission gating.
#
# Results land in t0_results/<RUN_ID>/ (one NN.json per instance), keyed by a run
# id that defaults to the current local server time (YYYYMMDD-HHMMSS). Logs are
# discarded.
#
# Env overrides:
#   RUN_ID      run id (default: local time stamp)
#   TIME_LIMIT  per-instance solver time limit in seconds (default: 900)
#   MAX_LEVELS  lex-descent depth per instance (default: solve_instance.jl's 8)
#   DATA_DIR    directory holding the -net/-tm/-scenario.json files
#   JULIA       path to the julia binary (default: `julia` on PATH)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve julia and export everything the scheduler reads from the environment.
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

# Ensure the project environment is instantiated (downloads the HiGHS artifact on
# the first run; idempotent and fast afterwards). Abort early on failure so a bad
# environment does not fan out into one confusing failure per instance.
echo "==> instantiating project environment..."
if ! "$JULIA" --project="$REPO_ROOT" -e 'using Pkg; Pkg.instantiate()'; then
    echo "ERROR: Pkg.instantiate() failed; aborting." >&2
    exit 1
fi

exec "$JULIA" --project="$REPO_ROOT" "$REPO_ROOT/scripts/run_scheduler.jl"
