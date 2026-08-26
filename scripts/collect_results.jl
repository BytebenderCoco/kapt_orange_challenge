# Aggregate the per-instance result JSONs of one run into a single summary CSV
# (the Step-5 experiment table). Run this after a run finishes (or mid-run, to
# snapshot the instances solved so far).
#
# Usage:
#   julia --project=. scripts/collect_results.jl [runId]
#
# Without a runId it picks the most recent directory under t0_results/ (run ids
# are local-server-time stamps, so lexical order == chronological order).

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

using Pkg
Pkg.activate(REPO_ROOT; io = devnull)

using JSON3

# The most recent run id under t0_results/, or `nothing` if there are none.
function get_latest_runId(t0ResultsDir)
    isdir(t0ResultsDir) || return nothing
    ids = sort([d for d in readdir(t0ResultsDir) if isdir(joinpath(t0ResultsDir, d))])
    return isempty(ids) ? nothing : ids[end]
end

# Load all result JSONs in a run's directory, sorted by file name (NN.json).
function get_rows_from_run(resultsDir)
    isdir(resultsDir) || error("No results directory: $resultsDir")
    files = sort([f for f in readdir(resultsDir) if endswith(f, ".json")])
    isempty(files) && error("No result files in $resultsDir")
    return [JSON3.read(read(joinpath(resultsDir, f), String)) for f in files]
end

# Write the summary table as CSV. Empty string for missing/non-finite numbers. The
# solve metrics live in the nested `results` block of the Result-module schema; the
# `waypoints` and `events` fields of that document are not summary columns.
function save_summary_csv(rows, outPath)
    header = "instance,succeeded,vertices,links,demands,status,mlu,lowerBound,gap,cpuTime"
    lines = String[header]
    for row in rows
        results = row.results
        push!(lines, join([
            string(row.instance),
            string(row.succeeded),
            results.vertices === nothing ? "" : string(results.vertices),
            results.links    === nothing ? "" : string(results.links),
            results.demands  === nothing ? "" : string(results.demands),
            string(results.status),
            results.mlu        === nothing ? "" : string(results.mlu),
            results.lowerBound === nothing ? "" : string(results.lowerBound),
            results.gap        === nothing ? "" : string(results.gap),
            results.cpuTime    === nothing ? "" : string(results.cpuTime),
        ], ','))
    end
    write(outPath, join(lines, '\n') * "\n")
    return outPath
end

function main()
    runId = isempty(ARGS) ? get_latest_runId(joinpath(REPO_ROOT, "t0_results")) : ARGS[1]
    runId === nothing && error("No runs found under t0_results/. Run t0_execution.sh first.")

    resultsDir = joinpath(REPO_ROOT, "t0_results", runId)
    outPath    = joinpath(resultsDir, "summary.csv")

    rows = get_rows_from_run(resultsDir)
    save_summary_csv(rows, outPath)

    println("wrote $(length(rows)) rows -> $outPath")
    return 0
end

try
    exit(main())
catch err
    @error "uncaught error" exception = (err, catch_backtrace())
    exit(1)
end
