# Headless single-instance solver for the Orange ROADEF 2026 challenge (t0 model).
#
# Runs the period-0 pipeline for one setA instance and writes its result as one
# JSON file. It is meant to be launched once per instance by run_parallel.sh, so
# many instances solve in parallel (one process each) and results land
# incrementally as each instance finishes.
#
# Usage:
#   julia --project=. scripts/solve_instance.jl <instanceName> \
#       [--output <resultsDir>] [--data-dir <dataDir>] [--time-limit <sec>]

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

# Always use the repo's project environment so the packages below resolve no
# matter how the script is invoked (with or without --project).
using Pkg
Pkg.activate(REPO_ROOT; io = devnull)

using JSON3
using Graphs
using JuMP
using HiGHS

include(joinpath(REPO_ROOT, "source", "Graph.jl"))
using .Graph
include(joinpath(REPO_ROOT, "source", "SplitCoefficients.jl"))
using .SplitCoefficients
include(joinpath(REPO_ROOT, "source", "TrafficMatrix.jl"))
using .TrafficMatrix
include(joinpath(REPO_ROOT, "source", "Scenario.jl"))
using .Scenario
include(joinpath(REPO_ROOT, "source", "Model.jl"))
using .Model

# Parse the CLI arguments into (instanceName, resultsDir, dataDir, timeLimitSec).
function parse_args(args)
    resultsDir   = joinpath(REPO_ROOT, "results")
    dataDir      = joinpath(REPO_ROOT, "data")
    timeLimitSec = 900
    positional   = String[]

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--output" || arg == "-o"
            resultsDir = args[i + 1]
            i += 2
        elseif arg == "--data-dir"
            dataDir = args[i + 1]
            i += 2
        elseif arg == "--time-limit"
            timeLimitSec = parse(Int, args[i + 1])
            i += 2
        elseif startswith(arg, "--")
            error("Unknown option: $arg")
        else
            push!(positional, arg)
            i += 1
        end
    end

    isempty(positional) && error(
        "Usage: solve_instance.jl <instanceName> [--output <dir>] [--data-dir <dir>] [--time-limit <sec>]"
    )

    return (
        instanceName = positional[1],
        resultsDir   = resultsDir,
        dataDir      = dataDir,
        timeLimitSec = timeLimitSec,
    )
end

# Load and validate the network graph from one instance's -net.json.
function get_graph_from_instance(dataDir, instanceName)
    netFile = joinpath(dataDir, "$instanceName-net.json")
    json = JSON3.read(read(netFile, String))
    is_jsonData_valid(json) || error("Invalid network JSON: $netFile")
    return get_graph_from_json(json)
end

# Load and validate the traffic-matrix demands from one instance's -tm.json.
function get_demands_from_instance(dataDir, instanceName, graph)
    tmFile = joinpath(dataDir, "$instanceName-tm.json")
    tm = JSON3.read(read(tmFile, String))
    is_tmData_valid(tm) || error("Invalid traffic-matrix JSON: $tmFile")
    return get_demands_from_json(tm, graph)
end

# Load and validate maxSeg from one instance's -scenario.json.
function get_maxSegments_from_instance(dataDir, instanceName)
    scenarioFile = joinpath(dataDir, "$instanceName-scenario.json")
    scenario = JSON3.read(read(scenarioFile, String))
    is_scenarioData_valid(scenario) || error("Invalid scenario JSON: $scenarioFile")
    return get_maxSegments_from_json(scenario)
end

# One result row for a single instance: run the whole period-0 pipeline.
function get_experimentRow_from_instance(dataDir, instanceName; timeLimitSec = 900)
    graph      = get_graph_from_instance(dataDir, instanceName)
    r          = get_splitCoefficients_by_graph(graph)
    capacities = get_capacities_by_graph(graph)
    demands    = get_demands_from_instance(dataDir, instanceName, graph)
    maxSeg     = get_maxSegments_from_instance(dataDir, instanceName)
    # Assemble the period-0 model with the fluent builder, then solve it.
    n          = nv(graph.graph)
    builder    = AsrModelBuilder(; timeLimitSec)
    set_variables!(builder, demands, n)
    set_flowConservation!(builder, demands, n)
    set_segmentCap!(builder, demands, n, maxSeg)
    set_loadBounds!(builder, graph, r, demands, capacities)
    solution   = solve!(build(builder))
    return (
        instance   = instanceName,
        succeeded  = true,
        vertices   = nv(graph.graph),
        links      = ne(graph.graph),
        demands    = length(demands),
        status     = string(solution.status),
        mlu        = solution.mlu,
        lowerBound = solution.lowerBound,
        gap        = solution.gap,
        cpuTime    = solution.cpuTime,
    )
end

# Map a result row to a JSON-safe form: JSON has no Inf, so a non-finite MLU or
# bound is written as null.
function to_jsonable(row)
    return (
        instance   = row.instance,
        succeeded  = row.succeeded,
        vertices   = row.vertices,
        links      = row.links,
        demands    = row.demands,
        status     = row.status,
        mlu        = isfinite(row.mlu) ? row.mlu : nothing,
        lowerBound = isfinite(row.lowerBound) ? row.lowerBound : nothing,
        gap        = row.gap,
        cpuTime    = row.cpuTime,
    )
end

# Write one instance's result to <resultsDir>/<instanceName>.json atomically
# (temp file + rename) so a reader never sees a half-written result.
function save_result_to_json(row, resultsDir)
    mkpath(resultsDir)
    outPath = joinpath(resultsDir, "$(row.instance).json")
    tmpPath = "$outPath.tmp"
    open(tmpPath, "w") do io
        JSON3.pretty(io, JSON3.write(to_jsonable(row)))
    end
    mv(tmpPath, outPath; force = true)
    return outPath
end

function main()
    args = parse_args(ARGS)

    row = try
        get_experimentRow_from_instance(
            args.dataDir, args.instanceName; timeLimitSec = args.timeLimitSec
        )
    catch err
        @error "solve failed for instance" args.instanceName exception = (err, catch_backtrace())
        (
            instance   = args.instanceName,
            succeeded  = false,
            vertices   = nothing,
            links      = nothing,
            demands    = nothing,
            status     = "error",
            mlu        = Inf,
            lowerBound = Inf,
            gap        = 0.0,
            cpuTime    = 0.0,
        )
    end

    path = save_result_to_json(row, args.resultsDir)
    println("$(row.instance): $(row.status) mlu=$(row.mlu) cpu=$(round(row.cpuTime, digits=2))s -> $path")

    return row.succeeded ? 0 : 1
end

try
    exit(main())
catch err
    @error "uncaught error" exception = (err, catch_backtrace())
    exit(1)
end
