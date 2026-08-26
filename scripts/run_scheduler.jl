# Parallel launcher for the t0 experiments.
#
# Hardcoded to solve the first 10 setA instances (setA-01..10 by sorted name),
# one Julia process each, all started at once — no RAM budgeting and no admission
# gating. Each instance's result lands in t0_results/<RUN_ID>/ as it finishes, so a
# cancelled run keeps whatever already completed.
#
# Env overrides:
#   RUN_ID      run id (default: local time stamp)
#   TIME_LIMIT  per-instance solver time limit in seconds (default: 900)
#   MAX_LEVELS  lex-descent depth per instance (default: t0_solve_instance.jl's 8)
#   DATA_DIR    directory holding the -net/-tm/-scenario.json files
#   JULIA       path to the julia binary (default: `julia` on PATH)

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

using Pkg
Pkg.activate(REPO_ROOT; io = devnull)

using Dates

# Number of leading instances (setA-01..10) to solve, all in parallel.
const instanceCount = 10

# Per-instance HiGHS thread allocation (hardcoded here, not an env knob), tiered by
# model size: the small instances (setA-01..05) solve fast on one core, so the freed
# cores go to the big MILPs where HiGHS's (sublinear) parallel branch-and-bound
# actually helps. All 10 run at once, so the total is the sum below (≈31 cores).
# Instances not listed fall back to defaultSolverThreads.
const solverThreadsByInstance = Dict(
    "setA-06" => 4, "setA-08" => 4, "setA-09" => 4,   # ~4.5–5.0M x-vars
    "setA-07" => 6,                                    # 7.9M x-vars
    "setA-10" => 8,                                    # 22.4M x-vars
)
const defaultSolverThreads = 1

# HiGHS threads for one instance's solve, from the size-tiered map above.
get_solverThreads_by_instance(name) = get(solverThreadsByInstance, name, defaultSolverThreads)

# Discover instance stems (e.g. "setA-01") from the -net.json files in dataDir.
function get_instances_from_dataDir(dataDir)
    instances = String[]
    for file in sort(readdir(dataDir))
        startswith(file, "-") && continue
        endswith(file, "-net.json") || continue
        push!(instances, file[1:(end - length("-net.json"))])
    end
    return instances
end

# Launch one solve as a detached subprocess, its output discarded (logs are not
# kept). Returns the running Process.
function launch_instance(juliaBin, name, resultsDir, dataDir, timeLimit, maxLevels)
    script = joinpath(REPO_ROOT, "scripts", "t0_solve_instance.jl")
    threads = get_solverThreads_by_instance(name)
    cmd = `$juliaBin --project=$REPO_ROOT $script $name --output $resultsDir --data-dir $dataDir --time-limit $timeLimit --threads $threads`
    # Only forward --max-levels when set, so an unset MAX_LEVELS keeps t0_solve_instance.jl's default.
    isempty(maxLevels) || (cmd = `$cmd --max-levels $maxLevels`)
    return run(pipeline(cmd; stdout = devnull, stderr = devnull); wait = false)
end

function main()
    dataDir    = get(ENV, "DATA_DIR", joinpath(REPO_ROOT, "data"))
    runId      = get(ENV, "RUN_ID", Dates.format(now(), "yyyymmdd-HHMMSS"))
    resultsDir = joinpath(REPO_ROOT, "t0_results", runId)
    timeLimit  = get(ENV, "TIME_LIMIT", "900")
    maxLevels  = get(ENV, "MAX_LEVELS", "")
    juliaBin   = get(ENV, "JULIA", "julia")

    mkpath(resultsDir)

    # Hardcoded to the first `instanceCount` instances, all launched in parallel.
    instances = get_instances_from_dataDir(dataDir)
    instances = instances[1:min(instanceCount, length(instances))]

    println("runId=$runId instances=$(length(instances)) (parallel) timeLimit=$(timeLimit)s maxLevels=$(isempty(maxLevels) ? "default" : maxLevels)")
    println("resultsDir=$resultsDir")
    for name in instances
        println("  $name (threads $(get_solverThreads_by_instance(name)))")
    end
    flush(stdout)

    # Launch every instance at once; a per-process @async task reports its completion
    # through the channel so we can count finishes and failures as they arrive.
    doneChannel = Channel{Any}(length(instances))
    for name in instances
        proc = launch_instance(juliaBin, name, resultsDir, dataDir, timeLimit, maxLevels)
        @async begin
            wait(proc)
            put!(doneChannel, (name = name, ok = success(proc)))
        end
        println("start $name")
        flush(stdout)
    end

    failures = 0
    for k in 1:length(instances)
        done = take!(doneChannel)
        println("done $(done.name)$(done.ok ? "" : " (failed)") ($k/$(length(instances)))")
        flush(stdout)
        if !done.ok
            failures += 1
            @warn "instance failed" done.name
            flush(stderr)
        end
    end

    count = length(filter(file -> endswith(file, ".json"), readdir(resultsDir)))
    println("done: $count instance result(s) written to $resultsDir")
    flush(stdout)
    return failures == 0 ? 0 : 1
end

try
    exit(main())
catch err
    @error "uncaught error" exception = (err, catch_backtrace())
    exit(1)
end
