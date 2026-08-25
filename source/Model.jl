module Model

# The logic-layer optimization model. Sits above the data layer: it consumes the
# per-period inputs (a NetworkGraph and its split coefficients r, bundled per
# period), the demands and maxSeg, and assembles + solves the JuMP MILP. JuMP's own
# `Model` type is referred to as `JuMP.Model` to avoid clashing with this module.
#
# The model spans a set of `periods` (0-based). With `periods = 0:0` it is the
# period-0-only model of steps 1–5; with `periods = 0:1` it is the two-period model
# of steps 6–8, where the optional `add_budgetBounds!` step links the periods with
# the reconfiguration budget β(t). A single λ bounds link utilization across all
# arcs in all periods (the plain MLU; the spec's lexicographic min-max is reduced to
# this first level, exactly as in step 5).
#
# The model is assembled with a fluent builder, mirroring how a `JuMP.Model` is
# itself built: construct a default `AsrModelBuilder` (HiGHS optimizer, time limit,
# the λ variable and the `Min λ` objective already in place), mutate it step by step
# with the `set_*!` (required) and `add_*!` (optional) steps, then `build` it into an
# immutable `AsrModel`. The caller finally `solve!`s that model and takes the
# returned solution:
#
#     periods     = 0:1
#     periodInputs = Dict(0 => (graph = g0, r = r0), 1 => (graph = g1, r = r1))
#     b = AsrModelBuilder(; timeLimitSec)
#     set_variables!(b, demands, n, periods)
#     set_flowConservation!(b, demands, n, periods)
#     set_segmentCap!(b, demands, n, maxSeg, periods)
#     set_loadBounds!(b, periodInputs, demands, periods)
#     add_budgetBounds!(b, demands, n, Dict(1 => beta1), periods)   # optional
#     model    = build(b)
#     solution = solve!(model)
using JuMP
using HiGHS
using Graphs
using ..Graph: NetworkGraph, get_edgeData_by_graph

export AsrModelBuilder, AsrModel,
    set_variables!, set_flowConservation!, set_segmentCap!, set_loadBounds!,
    add_budgetBounds!, build, solve!, get_waypoints_by_solvedModel

# In-progress T-ASR model. Mutable, JuMP-style: the constructor seeds the data-free
# parts (the λ variable and the `Min λ` objective); the `set_*!`/`add_*!` steps fill
# in the rest. `x` is `nothing` until `set_variables!` declares it.
mutable struct AsrModelBuilder
    model::JuMP.Model
    # λ: the maximum link utilization (MLU) being minimized.
    lambda::JuMP.VariableRef
    # x^{d,t}_{ij}: the segment decision variables; nothing until set_variables!.
    x::Any
end

# Frozen, solvable T-ASR model produced by `build`. Retains the variable handles so
# a later solution reader can decode the per-period routing scheme from `x`.
struct AsrModel
    model::JuMP.Model
    lambda::JuMP.VariableRef
    x::Any
end

# Default builder: a HiGHS-backed JuMP model with the solver configured, the λ
# variable declared and the `Min λ` objective set. Everything data-dependent is
# added afterwards through the `set_*!`/`add_*!` steps. Mirrors `JuMP.Model(HiGHS.Optimizer)`.
function AsrModelBuilder(; timeLimitSec = 900)
    model = JuMP.Model(HiGHS.Optimizer)
    set_time_limit_sec(model, timeLimitSec)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)  # stop at 1% gap
    set_silent(model)

    # λ: the maximum link utilization (MLU) being minimized.
    @variable(model, lambda >= 0)
    @objective(model, Min, lambda)

    return AsrModelBuilder(model, lambda, nothing)
end

# Declare the segment decision variables x^{d,t}_{ij} (1 if demand d uses segment
# (i, j) at period t). Required before any constraint block that references x.
function set_variables!(builder::AsrModelBuilder, demands, n, periods)
    model = builder.model
    # x^{d,t}_{ij}: 1 if demand d uses segment (i, j) at period t.
    @variable(model, x[d in demands, t in periods, i in 1:n, j in 1:n; i != j], Bin)
    builder.x = x
    return builder
end

# (1) Flow conservation on segments, per demand and per period: each demand is
# routed along one segment path from its source to its target in every period.
function set_flowConservation!(builder::AsrModelBuilder, demands, n, periods)
    model = builder.model
    x = builder.x
    for t in periods, demand in demands, i in 1:n
        rhs = (i == demand.source) ? 1 : ((i == demand.target) ? -1 : 0)
        @constraint(model,
            sum(x[demand, t, i, j] for j in 1:n if i != j) -
            sum(x[demand, t, j, i] for j in 1:n if i != j) == rhs
        )
    end
    return builder
end

# (2) Segment cap maxSeg, per demand and per period: at most maxSeg segments per
# segment path.
function set_segmentCap!(builder::AsrModelBuilder, demands, n, maxSeg, periods)
    model = builder.model
    x = builder.x
    for t in periods, demand in demands
        @constraint(model, sum(x[demand, t, i, j] for i in 1:n, j in 1:n if i != j) <= maxSeg)
    end
    return builder
end

# (3) Load on each arc a = (u, v) in each period t: routed traffic <= λ · c(a).
# `periodInputs[t]` is the (graph, r) bundle for period t — the graph G_t (with its
# down-links already removed) and its split coefficients r_t. Capacities are derived
# from each period's graph. A segment (i, j) that carries ECMP flow at period t has
# at least one r_t entry; a segment whose endpoints are disconnected in G_t has
# none, so those decision vars are fixed to 0 — otherwise a disconnected demand
# could be "routed" at zero load, hiding real infeasibility.
function set_loadBounds!(builder::AsrModelBuilder, periodInputs, demands, periods)
    model = builder.model
    x = builder.x
    lambda = builder.lambda
    for t in periods
        network = periodInputs[t].graph
        r = periodInputs[t].r
        graph = network.graph
        n = nv(graph)

        # Invert r once: arc a=(u,v) → [(i, j, r(i,j,a))], its nonzero split
        # coefficients. This lets each arc's load sum only its nonzero terms rather
        # than scanning all (i,j) and looking up a mostly-zero r. reachable = the
        # segments (i,j) that carry any ECMP flow in G_t (⇔ have an r entry).
        arcSegments = Dict{Tuple{Int, Int}, Vector{Tuple{Int, Int, Float64}}}()
        reachable = Set{Tuple{Int, Int}}()
        for ((i, j, a), coeff) in r
            push!(get!(() -> Tuple{Int, Int, Float64}[], arcSegments, a), (i, j, coeff))
            push!(reachable, (i, j))
        end

        # A segment (i, j) with no r_t entry has j unreachable from i in G_t. Fix
        # those decision vars to 0 (computed once, applied to every demand) so a
        # disconnected demand cannot be "routed" at zero load, hiding infeasibility.
        unreachable = [(i, j) for i in 1:n for j in 1:n if i != j && !((i, j) in reachable)]
        for demand in demands, (i, j) in unreachable
            fix(x[demand, t, i, j], 0; force = true)
        end

        for edge in edges(graph)
            u, v = src(edge), dst(edge)
            # c(a): capacity of arc a
            c = get_edgeData_by_graph(network, u, v).capacity
            segments = get(arcSegments, (Int(u), Int(v)), Tuple{Int, Int, Float64}[])
            if isempty(segments)
                # No split coefficient references this arc → it carries no flow;
                # 0 ≤ λ·c(a), same trivially-satisfied constraint as the dense form.
                @constraint(model, 0 <= lambda * c)
            else
                load = @expression(model, sum(
                    # r(i, j, a) · φ(d, t) · x^{d,t}_{ij}   (φ(d, t) = volumes[t + 1])
                    coeff * demand.volumes[t + 1] * x[demand, t, i, j]
                    for demand in demands for (i, j, coeff) in segments
                ))
                @constraint(model, load <= lambda * c)
            end
        end
    end
    return builder
end

# (4) Reconfiguration budget β(t): cap the total rerouting between consecutive
# periods. Optional (`add_`): only a period t whose predecessor t-1 is also in
# `periods` and that has a budget β(t) in `budgets` gets a constraint; a missing or
# `nothing` budget is skipped (never coerced to 0, which would forbid all rerouting).
#
# |x^{d,t}_{ij} − x^{d,t-1}_{ij}| is linearized with a nonnegative auxiliary
# `segmentChange` that lower-bounds both signed differences. It appears only in the
# `Σ ≤ β(t)` constraint (not the objective), so at the optimum the solver keeps it at
# its lower bound = the absolute difference. `budgets` is a period → β(t) map.
function add_budgetBounds!(builder::AsrModelBuilder, demands, n, budgets, periods)
    model = builder.model
    x = builder.x
    for t in periods
        (t - 1) in periods || continue
        # β(t): the reconfiguration budget linking period t-1 to t.
        beta = get(budgets, t, nothing)
        beta === nothing && continue

        # segmentChange[d,i,j] ≥ |x^{d,t}_{ij} − x^{d,t-1}_{ij}|
        segmentChange = @variable(model, [d in demands, i in 1:n, j in 1:n; i != j], lower_bound = 0)
        for demand in demands, i in 1:n, j in 1:n
            i == j && continue
            @constraint(model, segmentChange[demand, i, j] >= x[demand, t, i, j] - x[demand, t - 1, i, j])
            @constraint(model, segmentChange[demand, i, j] >= x[demand, t - 1, i, j] - x[demand, t, i, j])
        end
        @constraint(model,
            sum(segmentChange[demand, i, j] for demand in demands, i in 1:n, j in 1:n if i != j) <= beta)
    end
    return builder
end

# Freeze a fully-configured builder into an immutable, solvable AsrModel.
function build(builder::AsrModelBuilder)
    return AsrModel(builder.model, builder.lambda, builder.x)
end

# Run the solver on an assembled model, mutating it with the solve result, and
# return the solve outcome as (status, mlu, lowerBound, gap, cpuTime).
function solve!(asrModel::AsrModel)
    model = asrModel.model

    startTime = time()
    optimize!(model)
    cpuTime = time() - startTime

    primalStatus = primal_status(model)
    # mlu = λ*: the optimized MLU, or Inf if no feasible point was found.
    mlu = (primalStatus == FEASIBLE_POINT || primalStatus == NEARLY_FEASIBLE_POINT) ?
        objective_value(model) : Inf

    # Lower bound may be unavailable for some statuses; fall back to 0.0.
    lowerBound = try
        objective_bound(model)
    catch
        0.0
    end

    gap = (isfinite(mlu) && mlu > 0) ? max(0.0, 1.0 - (lowerBound / mlu)) : 0.0

    return (
        status     = termination_status(model),
        mlu        = mlu,
        lowerBound = lowerBound,
        gap        = gap,
        cpuTime    = cpuTime,
    )
end

# Decode the routing scheme from a solved model: for each period, a per-demand list
# of the ordered waypoints (JSON node ids) of its segment path. `x[d,t,i,j]=1` marks
# segment (i,j) at period t; by flow conservation (1) the active segments of a demand
# chain into one source→target path per period, whose interior nodes are its
# waypoints. Returns a Dict period → per-demand waypoint lists; call only after
# solve! and before any re-optimize!. Empty lists (per period, per demand) if the
# solve produced no primal point.
function get_waypoints_by_solvedModel(asrModel::AsrModel, periodInputs, demands, periods)
    model = asrModel.model
    x = asrModel.x

    # No primal solution → per-period empty waypoint lists.
    if !has_values(model)
        return Dict(t => [Int[] for _ in demands] for t in periods)
    end

    # Bulk-read x once, then a single pass over the stored (sparse) entries, keeping
    # only the active segments grouped into per-period, per-demand successor maps.
    vals = value.(x)
    # succ[t][d.id]: i -> j, the active segment leaving vertex i for demand d at period t.
    succ = Dict{Int, Dict{Int, Dict{Int, Int}}}(t => Dict{Int, Dict{Int, Int}}() for t in periods)
    for (key, val) in vals.data
        val > 0.5 || continue
        demand, t, i, j = key
        get!(() -> Dict{Int, Int}(), succ[t], demand.id)[i] = j
    end

    # Walk each demand's path source→target per period, dropping the endpoints, and
    # translate the interior vertices back to JSON node ids.
    waypointsByPeriod = Dict{Int, Vector{Vector{Int}}}()
    for t in periods
        network = periodInputs[t].graph
        n = nv(network.graph)
        perDemand = Vector{Vector{Int}}(undef, length(demands))
        for demand in demands
            segments = get(succ[t], demand.id, Dict{Int, Int}())
            waypoints = Int[]
            node = demand.source
            for _ in 1:n   # cap: a simple s→t path visits at most n vertices
                haskey(segments, node) || break
                node = segments[node]
                node == demand.target && break
                push!(waypoints, network.nodeData[node].jsonId)
            end
            perDemand[demand.id] = waypoints
        end
        waypointsByPeriod[t] = perDemand
    end

    return waypointsByPeriod
end

end # module Model
