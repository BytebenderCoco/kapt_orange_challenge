# RAM-aware work-queue scheduler for the t0 experiments.
#
# Replaces the barrier "waves" of run_parallel.sh: instead of launching a fixed
# number of processes, waiting for ALL of them, then launching the next wave, it
# starts the next instance as soon as a running process finishes (a slot frees).
# Admission is gated by two budgets, whichever is tighter:
#
#   * MAX_RAM_GB  (required) — total memory budget. Each instance gets a static
#     peak-RAM estimate (linear in the model size, see
#     get_ramEstimateBytes_by_modelSize) and a new instance is only started when
#     sum(running estimates) + estimate(next) fits under the budget.
#   * MAX_PROCS   (default: detected logical cores) — CPU ceiling, so many tiny
#     instances don't oversubscribe the cores.
#
# Instances are queued largest-estimate-first so the heavy instances start early
# while the small ones backfill the leftover budget.
#
# Env overrides:
#   MAX_RAM_GB  required, fixed RAM budget in GiB
#   MAX_PROCS   max concurrent solves (default: Sys.CPU_THREADS)
#   RUN_ID      run id (default: local time stamp)
#   TIME_LIMIT  per-instance solver time limit in seconds (default: 900)
#   DATA_DIR    directory holding the -net/-tm/-scenario.json files
#   JULIA       path to the julia binary (default: `julia` on PATH)

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

using Pkg
Pkg.activate(REPO_ROOT; io = devnull)

using JSON3
using Dates

# ---------------------------------------------------------------------------
# RAM-estimate calibration constants (linear model, bytes):
#   estimate = ramBaseBytes
#            + ramBytesPerVariable * nVars
#            + ramBytesPerNonzero  * nnz
#
# TODO(calibrate): fit these against the real peak RSS printed by
# solve_instance.jl (Sys.maxrss) on a few representative instances before
# trusting the scheduler on a new machine. Current values are rough defaults.
# ---------------------------------------------------------------------------
const ramBaseBytes         = 900 * 1024^2   # Julia runtime + HiGHS overhead (measured ~0.9 GiB on im-kigs)
const ramBytesPerVariable  = 200.0          # per binary variable (JuMP + HiGHS col)
const ramBytesPerNonzero   = 24.0           # per constraint-matrix nonzero (row+col)

# Model-size proxy for one instance: the vertex/link/demand counts read from the
# JSON files, plus the two quantities that drive solver memory:
#   nVars = D * n * (n - 1)          # x^{d,0}_{ij} binary variables (i != j)
#   nnz   = m * nVars                # nonzeros in the load-bound block (dominant)
function get_modelSize_from_instance(dataDir, instanceName)
    net = JSON3.read(read(joinpath(dataDir, "$instanceName-net.json"), String))
    tm  = JSON3.read(read(joinpath(dataDir, "$instanceName-tm.json"), String))
    n = length(net.nodes)
    m = length(net.links)
    demands = length(tm.demands)
    nVars = demands * n * (n - 1)
    return (
        vertices = n,
        links    = m,
        demands  = demands,
        nVars    = nVars,
        nnz      = m * nVars,
    )
end

# Static peak-RAM estimate (bytes) for the period-0 HiGHS solve, derived from an
# already-computed model size.
function get_ramEstimateBytes_by_modelSize(size)
    return ramBaseBytes +
           ramBytesPerVariable * size.nVars +
           ramBytesPerNonzero * size.nnz
end

# Fixed RAM budget in bytes, read from the required MAX_RAM_GB env var (GiB).
function get_ramBudgetBytes()
    value = get(ENV, "MAX_RAM_GB", "")
    isempty(value) && error("MAX_RAM_GB is required (fixed RAM budget in GiB).")
    return parse(Float64, value) * 1024^3
end

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

# Launch one solve as a detached subprocess, its output discarded (matches the
# old run_parallel.sh: logs are not kept). Returns the running Process.
function launch_instance(juliaBin, name, resultsDir, dataDir, timeLimit)
    script = joinpath(REPO_ROOT, "scripts", "solve_instance.jl")
    cmd = `$juliaBin --project=$REPO_ROOT $script $name --output $resultsDir --data-dir $dataDir --time-limit $timeLimit`
    return run(pipeline(cmd; stdout = devnull, stderr = devnull); wait = false)
end

function main()
    dataDir      = get(ENV, "DATA_DIR", joinpath(REPO_ROOT, "data"))
    runId        = get(ENV, "RUN_ID", Dates.format(now(), "yyyymmdd-HHMMSS"))
    resultsDir   = joinpath(REPO_ROOT, "t0_results", runId)
    timeLimit    = get(ENV, "TIME_LIMIT", "900")
    juliaBin     = get(ENV, "JULIA", "julia")
    maxProcs     = begin
        value = get(ENV, "MAX_PROCS", "")
        isempty(value) ? Sys.CPU_THREADS : parse(Int, value)
    end
    ramBudgetBytes = get_ramBudgetBytes()

    mkpath(resultsDir)

    # Per-instance RAM estimate, queued largest-first.
    instances = [(name = name,
                  estBytes = get_ramEstimateBytes_by_modelSize(
                      get_modelSize_from_instance(dataDir, name)))
                 for name in get_instances_from_dataDir(dataDir)]
    sort!(instances; by = item -> item.estBytes, rev = true)

    println("runId=$runId maxProcs=$maxProcs ramBudget=$(round(ramBudgetBytes / 2^30; digits = 1))GiB timeLimit=$(timeLimit)s")
    println("resultsDir=$resultsDir")
    for item in instances
        println("  $(item.name): est $(round(item.estBytes / 2^30; digits = 2)) GiB")
    end
    flush(stdout)

    # Work queue: one entry per running process (name -> estimate), plus a channel
    # that receives a message whenever any process finishes.
    runningEst = Dict{String, Float64}()
    sumRunning = 0.0
    doneChannel = Channel{Any}(32)

    failures = 0
    finished = 0
    i = 1
    n = length(instances)

    while i <= n || !isempty(runningEst)
        # Start as many queued instances as both budgets allow.
        while i <= n
            name     = instances[i].name
            estBytes = instances[i].estBytes

            length(runningEst) >= maxProcs && break
            if !isempty(runningEst) && sumRunning + estBytes > ramBudgetBytes
                break
            end
            if isempty(runningEst) && estBytes > ramBudgetBytes
                @warn "skipping $name: estimate $(round(estBytes / 2^30; digits = 1)) GiB exceeds the $(round(ramBudgetBytes / 2^30; digits = 1)) GiB budget"
                flush(stderr)
                failures += 1
                i += 1
                continue
            end

            proc = launch_instance(juliaBin, name, resultsDir, dataDir, timeLimit)
            runningEst[name] = estBytes
            sumRunning += estBytes
            @async begin
                wait(proc)
                put!(doneChannel, (name = name, estBytes = estBytes, ok = success(proc)))
            end
            println("start $name (est $(round(estBytes / 2^30; digits = 2)) GiB, running $(length(runningEst)))")
            flush(stdout)
            i += 1
        end

        isempty(runningEst) && break

        done = take!(doneChannel)
        delete!(runningEst, done.name)
        sumRunning -= done.estBytes
        finished += 1
        println("done $(done.name)$(done.ok ? "" : " (failed)") ($finished/$n)")
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
