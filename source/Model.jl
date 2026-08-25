module Model

# The logic-layer optimization model. Sits above the data layer: it consumes the
# graph, the split coefficients r, the demands, the capacities, and maxSeg, and
# assembles + solves the JuMP MILP. JuMP's own `Model` type is referred to as
# `JuMP.Model` to avoid clashing with this module's name.
#
# The model is assembled with a fluent builder, mirroring how a `JuMP.Model` is
# itself built: construct a default `AsrModelBuilder` (HiGHS optimizer, time
# limit, the λ variable and the `Min λ` objective already in place), mutate it
# step by step with the `set_*!` constraint blocks, then `build` it into an
# immutable `AsrModel`. The caller finally `solve!`s that model and takes the
# returned solution:
#
#     b = AsrModelBuilder()
#     set_variables!(b, demands, n)
#     set_flowConservation!(b, demands, n)
#     set_segmentCap!(b, demands, n, maxSeg)
#     set_loadBounds!(b, network, r, demands, capacities)
#     model    = build(b)
#     solution = solve!(model)
using JuMP
using HiGHS
using Graphs
using ..Graph: NetworkGraph

export AsrModelBuilder, AsrModel,
    set_variables!, set_flowConservation!, set_segmentCap!, set_loadBounds!,
    build, solve!, get_waypoints_by_solvedModel

# In-progress T-ASR model (period 0). Mutable, JuMP-style: the constructor seeds
# the data-free parts (the λ variable and the `Min λ` objective); the `set_*!`
# steps fill in the rest. `x` is `nothing` until `set_variables!` declares it.
mutable struct AsrModelBuilder
    model::JuMP.Model
    # λ: the maximum link utilization (MLU) being minimized.
    lambda::JuMP.VariableRef
    # x^{d,0}_{ij}: the segment decision variables; nothing until set_variables!.
    x::Any
end

# Frozen, solvable T-ASR model produced by `build`. Retains the variable handles
# so a later solution reader can decode the routing scheme from `x`.
struct AsrModel
    model::JuMP.Model
    lambda::JuMP.VariableRef
    x::Any
end

# Default builder: a HiGHS-backed JuMP model with the solver configured, the λ
# variable declared and the `Min λ` objective set. Everything data-dependent is
# added afterwards through the `set_*!` steps. Mirrors `JuMP.Model(HiGHS.Optimizer)`.
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

# Declare the segment decision variables x^{d,0}_{ij} (1 if demand d uses segment
# (i, j) at time 0). Required before any constraint block that references x.
function set_variables!(builder::AsrModelBuilder, demands, n)
    model = builder.model
    # x^{d,0}_{ij}: 1 if demand d uses segment (i, j) at time 0.
    @variable(model, x[d in demands, i in 1:n, j in 1:n; i != j], Bin)
    builder.x = x
    return builder
end

# (1) Flow conservation on segments, per demand: each demand is routed along one
# segment path from its source to its target.
function set_flowConservation!(builder::AsrModelBuilder, demands, n)
    model = builder.model
    x = builder.x
    for demand in demands, i in 1:n
        rhs = (i == demand.source) ? 1 : ((i == demand.target) ? -1 : 0)
        @constraint(model,
            sum(x[demand, i, j] for j in 1:n if i != j) -
            sum(x[demand, j, i] for j in 1:n if i != j) == rhs
        )
    end
    return builder
end

# (2) Segment cap maxSeg, per demand: at most maxSeg segments per segment path.
function set_segmentCap!(builder::AsrModelBuilder, demands, n, maxSeg)
    model = builder.model
    x = builder.x
    for demand in demands
        @constraint(model, sum(x[demand, i, j] for i in 1:n, j in 1:n if i != j) <= maxSeg)
    end
    return builder
end

# (3) Load on each arc a = (u, v): routed traffic <= λ · c(a).
function set_loadBounds!(builder::AsrModelBuilder, network::NetworkGraph, r, demands, capacities)
    model = builder.model
    x = builder.x
    lambda = builder.lambda
    graph = network.graph

    # Reverse index: arc (u, v) -> [(i, j, coef)] for every nonzero r(i, j, a).
    # r is sparse (an arc carries only the segment pairs whose shortest path uses
    # it), so summing over these pairs instead of all n² per arc avoids the
    # O(m·|D|·n²) term blowup that otherwise stalls model construction.
    splitByArc = Dict{Tuple{Int, Int}, Vector{Tuple{Int, Int, Float64}}}()
    for ((i, j, arc), coef) in r
        push!(get!(() -> Tuple{Int, Int, Float64}[], splitByArc, arc), (i, j, coef))
    end

    for edge in edges(graph)
        u, v = src(edge), dst(edge)
        # c(a): capacity of arc a
        c = capacities[(u, v)]
        # The segment pairs (and coefficients) whose flow traverses arc a.
        pairs = get(splitByArc, (u, v), Tuple{Int, Int, Float64}[])
        load = @expression(model, sum(
            # r(i, j, a) · φ(d, 0) · x^{d,0}_{ij}
            coef * demand.volumes[1] * x[demand, i, j]
            for (i, j, coef) in pairs for demand in demands
        ))
        @constraint(model, load <= lambda * c)
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

# Decode the period-0 routing scheme from a solved model: for each demand, the
# ordered waypoint list (JSON node ids) of its segment path. `x[d,i,j]=1` marks
# segment (i,j); by flow conservation (1) the active segments of a demand chain
# into one source→target path, whose interior nodes are its waypoints. Call only
# after solve! and before any re-optimize!; returns empty lists if the solve
# produced no primal point.
function get_waypoints_by_solvedModel(asrModel::AsrModel, network::NetworkGraph, demands)
    model = asrModel.model
    x = asrModel.x
    n = nv(network.graph)

    # No primal solution → nothing to decode.
    has_values(model) || return [Int[] for _ in demands]

    # Bulk-read x once, then a single pass over the stored (sparse) entries,
    # keeping only the active segments grouped into per-demand successor maps.
    vals = value.(x)
    # succ[d.id]: i -> j, the active segment leaving vertex i for that demand.
    succ = Dict{Int, Dict{Int, Int}}()
    for (key, val) in vals.data
        val > 0.5 || continue
        demand, i, j = key
        get!(() -> Dict{Int, Int}(), succ, demand.id)[i] = j
    end

    # Walk each demand's path source→target, dropping the endpoints, and
    # translate the interior vertices back to JSON node ids.
    waypointsByDemand = Vector{Vector{Int}}(undef, length(demands))
    for demand in demands
        segments = get(succ, demand.id, Dict{Int, Int}())
        waypoints = Int[]
        node = demand.source
        for _ in 1:n   # cap: a simple s→t path visits at most n vertices
            haskey(segments, node) || break
            node = segments[node]
            node == demand.target && break
            push!(waypoints, network.nodeData[node].jsonId)
        end
        waypointsByDemand[demand.id] = waypoints
    end

    return waypointsByDemand
end

end # module Model
