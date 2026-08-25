# Aggregate the per-instance result JSONs of one run into a single summary CSV
# (the Step-5 experiment table). Run this after a run finishes (or mid-run, to
# snapshot the instances solved so far).
#
# Usage:
#   julia --project=. scripts/collect_results.jl [runId]
#
# Without a runId it picks the most recent directory under runs/ (run ids are
# local-server-time stamps, so lexical order == chronological order).

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

using Pkg
Pkg.activate(REPO_ROOT; io = devnull)

using JSON3

# The most recent run id under runs/, or `nothing` if there are none.
function get_latest_runId(runsDir)
    isdir(runsDir) || return nothing
    ids = sort([d for d in readdir(runsDir) if isdir(joinpath(runsDir, d))])
    return isempty(ids) ? nothing : ids[end]
end

# Load all result JSONs in a run's results/ directory, sorted by instance name.
function get_rows_from_run(resultsDir)
    isdir(resultsDir) || error("No results directory: $resultsDir")
    files = sort([f for f in readdir(resultsDir) if endswith(f, ".json")])
    isempty(files) && error("No result files in $resultsDir")
    return [JSON3.read(read(joinpath(resultsDir, f), String)) for f in files]
end

# Write the summary table as CSV. Empty string for missing/non-finite numbers.
function save_summary_csv(rows, outPath)
    header = "instance,succeeded,vertices,links,demands,status,mlu,lowerBound,gap,cpuTime"
    lines = String[header]
    for row in rows
        push!(lines, join([
            string(row.instance),
            string(row.succeeded),
            row.vertices === nothing ? "" : string(row.vertices),
            row.links    === nothing ? "" : string(row.links),
            row.demands  === nothing ? "" : string(row.demands),
            string(row.status),
            row.mlu        === nothing ? "" : string(row.mlu),
            row.lowerBound === nothing ? "" : string(row.lowerBound),
            row.gap        === nothing ? "" : string(row.gap),
            row.cpuTime    === nothing ? "" : string(row.cpuTime),
        ], ','))
    end
    write(outPath, join(lines, '\n') * "\n")
    return outPath
end

function main()
    runId = isempty(ARGS) ? get_latest_runId(joinpath(REPO_ROOT, "runs")) : ARGS[1]
    runId === nothing && error("No runs found under runs/. Run run_parallel.sh first.")

    resultsDir = joinpath(REPO_ROOT, "runs", runId, "results")
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
