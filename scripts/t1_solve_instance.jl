# Headless single-instance solver for the Orange ROADEF 2026 challenge (t1 model).
#
# Runs the two-period pipeline (steps 6–8) for one setA instance and writes its
# result as one JSON file. It is meant to be launched once per instance by a t1
# execution wrapper, so many instances solve in parallel (one process each) and
# results land incrementally as each instance finishes.
#
# Period 1 is a maintenance period: the scenario's interventions q(1) take some
# links down. We build G₁ by removing those down-links from the nominal graph G₀,
# recompute the split coefficients r₁ on G₁, and solve both periods together with
# the reconfiguration budget β(1) (constraint 4) capping the rerouting from period
# 0 to period 1. The result uses the two-period (v2) schema: per-period waypoints.
#
# The solve is the lexicographic min-max of objective (5): solve! minimizes the MLU,
# then descends the sorted load vector, flattening the profile below the MLU.
# `--max-levels` caps how many levels of that descent to run (depth ≥ 1; 1 = MLU only).
#
# Usage:
#   julia --project=. scripts/t1_solve_instance.jl <instanceName> \
#       [--output <resultsDir>] [--data-dir <dataDir>] [--time-limit <sec>] \
#       [--max-levels <k>] [--threads <n>]

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
    resultsDir   = joinpath(REPO_ROOT, "t1_results")
    dataDir      = joinpath(REPO_ROOT, "data")
    timeLimitSec = 1800
    maxLevels    = 3
    threads      = 1
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
        elseif arg == "--max-levels"
            maxLevels = parse(Int, option_value(arg, i))
            i += 2
        elseif arg == "--threads"
            threads = parse(Int, option_value(arg, i))
            i += 2
        elseif startswith(arg, "--")
            error("Unknown option: $arg")
        else
            push!(positional, arg)
            i += 1
        end
    end

    isempty(positional) && error(
        "Usage: t1_solve_instance.jl <instanceName> [--output <dir>] [--data-dir <dir>] [--time-limit <sec>] [--max-levels <k>] [--threads <n>]"
    )

    maxLevels >= 1 || error("--max-levels must be >= 1 (1 = MLU only).")
    threads >= 1 || error("--threads must be >= 1.")

    return (
        instanceName = positional[1],
        resultsDir   = resultsDir,
        dataDir      = dataDir,
        timeLimitSec = timeLimitSec,
        maxLevels    = maxLevels,
        threads      = threads,
    )
end

# Load and validate the nominal (period-0) network graph from one instance's -net.json.
function get_graph_from_instance(dataDir, instanceName)
    netFile = joinpath(dataDir, "$instanceName-net.json")
    json = JSON3.read(read(netFile, String))
    is_jsonData_valid(json) || error("Invalid network JSON: $netFile")
    return get_graph_from_json(json)
end

# Load and validate the traffic-matrix demands (both time slots) from one instance's -tm.json.
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

# downtimeLinks q(t): the JSON link ids down at period t, loaded and validated from
# one instance's -scenario.json.
function get_downtimeLinks_from_instance(dataDir, instanceName, t)
    scenarioFile = joinpath(dataDir, "$instanceName-scenario.json")
    scenario = JSON3.read(read(scenarioFile, String))
    is_scenarioData_valid(scenario) || error("Invalid scenario JSON: $scenarioFile")
    return get_downtimeLinks_from_json(scenario, t)
end

# β(t): reconfiguration budget at period t, loaded and validated from one instance's
# -scenario.json.
function get_budget_from_instance(dataDir, instanceName, t)
    scenarioFile = joinpath(dataDir, "$instanceName-scenario.json")
    scenario = JSON3.read(read(scenarioFile, String))
    is_scenarioData_valid(scenario) || error("Invalid scenario JSON: $scenarioFile")
    return get_budget_from_json(scenario, t)
end

# One result row for a single instance: run the whole two-period pipeline (build G₀
# and G₁, recompute r₀/r₁, assemble + solve the budgeted two-period model), recording
# each step into `events`. Mirrors the notebook's get_experimentRow_from_instance so
# both paths produce the same experimentRow (and, through Result, the same v2 document).
function get_experimentRow_from_instance(dataDir, instanceName, events; timeLimitSec = 1800, maxLevels = 3, threads = 1)
    record_event!(events, "loading instance data")
    graph         = get_graph_from_instance(dataDir, instanceName)
    record_event!(events, "period-0 graph calculated")
    # r₀: split coefficients on the nominal graph G₀.
    r             = get_splitCoefficients_by_graph(graph)
    # q(1): the links down at period 1; G₁ is G₀ with those links removed.
    downtimeLinks = get_downtimeLinks_from_instance(dataDir, instanceName, 1)
    graph1        = get_graph_by_downtimeLinks(graph, downtimeLinks)
    record_event!(events, "period-1 graph calculated")
    # r₁: split coefficients recomputed on G₁.
    r1            = get_splitCoefficients_by_graph(graph1)
    demands       = get_demands_from_instance(dataDir, instanceName, graph)
    maxSeg        = get_maxSegments_from_instance(dataDir, instanceName)
    # β(1): the reconfiguration budget linking period 0 → 1.
    budget1       = get_budget_from_instance(dataDir, instanceName, 1)
    record_event!(events, "parameters built")
    record_event!(events, "building model")
    # Two-period model: periods {0, 1}, with the optional budget step linking them.
    n             = nv(graph.graph)
    periods       = 0:1
    periodInputs  = Dict(0 => (graph = graph, r = r), 1 => (graph = graph1, r = r1))
    builder       = AsrModelBuilder(; timeLimitSec, threads)
    set_variables!(builder, demands, n, periods)
    set_flowConservation!(builder, demands, n, periods)
    set_segmentCap!(builder, demands, n, maxSeg, periods)
    set_loadBounds!(builder, periodInputs, demands, periods)
    # (4) β(1) links period 0 → 1: total rerouting must stay within the budget.
    add_budgetBounds!(builder, demands, n, Dict(1 => budget1), periods)
    model         = build(builder)
    record_event!(events, "solving model")
    # Lexicographic descent (objective 5); maxLevels caps the depth. See Model.solve!.
    solution      = solve!(model; maxLevels)
    record_event!(events, "model solved")
    # Per-period, per-demand waypoint lists (JSON node ids). Empty for a demand routed
    # on shortest paths, or for the whole run if infeasible.
    waypoints     = get_waypoints_by_solvedModel(model, periodInputs, demands, periods)
    record_event!(events, "waypoints decoded")
    # L: sorted per-arc utilizations across both periods at the final solution (spec objective 5).
    loadVector    = get_loadVector_by_solvedModel(model, periodInputs)
    record_event!(events, "load vector decoded")
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
        maxrss     = Sys.maxrss(),
        waypoints  = waypoints,
        loadVector = loadVector,
        events     = events,
    )
end

function main()
    args = parse_args(ARGS)

    events = NamedTuple[]
    row = try
        get_experimentRow_from_instance(
            args.dataDir, args.instanceName, events;
            timeLimitSec = args.timeLimitSec, maxLevels = args.maxLevels, threads = args.threads
        )
    catch err
        # Emit a same-schema :error row so the saved file stays on-schema; the process
        # exit code (below) also signals the failure to the execution wrapper.
        record_event!(events, sprint(showerror, err); level = :error)
        @error "solve failed for instance" args.instanceName exception = (err, catch_backtrace())
        (
            instance = args.instanceName,
            vertices = missing, links = missing, demands = missing,
            status = :error,
            mlu = missing, lowerBound = missing, gap = missing, cpuTime = missing,
            maxrss = Sys.maxrss(), waypoints = missing, loadVector = missing, events = events,
        )
    end

    # Two-period schema (v2): per-period waypoints.
    path      = save_resultDoc_to_json(get_resultDoc_by_experimentRow(row; version = SCHEMA_VERSION_V2), args.resultsDir)
    succeeded = row.status !== :error
    mlu       = row.mlu === missing ? "n/a" : row.mlu
    cpuTime   = row.cpuTime === missing ? 0.0 : round(row.cpuTime, digits = 2)
    maxrss   = row.maxrss === missing ? 0.0 : round(row.maxrss / 2^30, digits = 2)
    println("$(args.instanceName): $(row.status) mlu=$mlu cpu=$(cpuTime)s maxrss=$(maxrss)GiB -> $path")

    return succeeded ? 0 : 1
end

try
    exit(main())
catch err
    @error "uncaught error" exception = (err, catch_backtrace())
    exit(1)
end
