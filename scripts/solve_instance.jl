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
include(joinpath(REPO_ROOT, "source", "Result.jl"))
using .Result

# Parse the CLI arguments into (instanceName, resultsDir, dataDir, timeLimitSec).
function parse_args(args)
    resultsDir   = joinpath(REPO_ROOT, "t0_results")
    dataDir      = joinpath(REPO_ROOT, "data")
    timeLimitSec = 900
    positional   = String[]

    # Return the value following a `--flag`, erroring clearly if it is missing
    # (rather than throwing an opaque BoundsError from `args[i + 1]`).
    option_value(name, i) = begin
        i + 1 <= length(args) || error("Option $name requires a value.")
        args[i + 1]
    end

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--output" || arg == "-o"
            resultsDir = option_value(arg, i)
            i += 2
        elseif arg == "--data-dir"
            dataDir = option_value(arg, i)
            i += 2
        elseif arg == "--time-limit"
            timeLimitSec = parse(Int, option_value(arg, i))
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

# One result row for a single instance: run the whole period-0 pipeline, recording
# each step into `events`. Mirrors the notebook's get_experimentRow_from_instance so
# both paths produce the same experimentRow (and, through Result, the same document).
function get_experimentRow_from_instance(dataDir, instanceName, events; timeLimitSec = 900)
    record_event!(events, "loading instance data")
    graph        = get_graph_from_instance(dataDir, instanceName)
    record_event!(events, "graph calculated")
    r            = get_splitCoefficients_by_graph(graph)
    demands      = get_demands_from_instance(dataDir, instanceName, graph)
    maxSeg       = get_maxSegments_from_instance(dataDir, instanceName)
    record_event!(events, "parameters built")
    record_event!(events, "building model")
    # Period-0-only model: the period set is just {0} (no budget step).
    n            = nv(graph.graph)
    periods      = 0:0
    periodInputs = Dict(0 => (graph = graph, r = r))
    builder      = AsrModelBuilder(; timeLimitSec)
    set_variables!(builder, demands, n, periods)
    set_flowConservation!(builder, demands, n, periods)
    set_segmentCap!(builder, demands, n, maxSeg, periods)
    set_loadBounds!(builder, periodInputs, demands, periods)
    model        = build(builder)
    record_event!(events, "solving model")
    solution     = solve!(model)
    record_event!(events, "model solved")
    waypoints    = get_waypoints_by_solvedModel(model, periodInputs, demands, periods)[0]
    record_event!(events, "waypoints decoded")
    return (
        instance   = instanceName,
        vertices   = nv(graph.graph),
        links      = ne(graph.graph),
        demands    = length(demands),
        status     = solution.status,
        mlu        = solution.mlu,
        lowerBound = solution.lowerBound,
        gap        = solution.gap,
        cpuTime    = solution.cpuTime,
        waypoints  = waypoints,
        events     = events,
    )
end

function main()
    args = parse_args(ARGS)

    events = NamedTuple[]
    row = try
        get_experimentRow_from_instance(
            args.dataDir, args.instanceName, events; timeLimitSec = args.timeLimitSec
        )
    catch err
        # Emit a same-schema :error row so the saved file stays on-schema; the process
        # exit code (below) also signals the failure to run_parallel.sh.
        record_event!(events, sprint(showerror, err); level = :error)
        @error "solve failed for instance" args.instanceName exception = (err, catch_backtrace())
        (
            instance = args.instanceName,
            vertices = missing, links = missing, demands = missing,
            status = :error,
            mlu = missing, lowerBound = missing, gap = missing, cpuTime = missing,
            waypoints = missing, events = events,
        )
    end

    path      = save_resultDoc_to_json(get_resultDoc_by_experimentRow(row), args.resultsDir)
    succeeded = row.status !== :error
    mlu       = row.mlu === missing ? "n/a" : row.mlu
    cpuTime   = row.cpuTime === missing ? 0.0 : round(row.cpuTime, digits = 2)
    println("$(args.instanceName): $(row.status) mlu=$mlu cpu=$(cpuTime)s -> $path")

    return succeeded ? 0 : 1
end

try
    exit(main())
catch err
    @error "uncaught error" exception = (err, catch_backtrace())
    exit(1)
end
