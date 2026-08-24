module Model

# The logic-layer optimization model. Sits above the data layer: it consumes the
# graph, the split coefficients r, the demands, the capacities, and maxSeg, and
# builds + solves the JuMP MILP. JuMP's own `Model` type is referred to as
# `JuMP.Model` to avoid clashing with this module's name.
using JuMP
using HiGHS
using Graphs
using ..Graph: NetworkGraph

export get_solution_by_graph

# Build and solve the period-0 MILP (T-ASR, time period 0 only): choose a segment
# path x^{d,0}_{ij} for every demand so that the maximum link utilization (MLU, λ)
# is minimized, subject to (1) flow conservation, (2) the segment cap maxSeg, and
# (3) the load constraint on every arc. Returns the solve results as
# (status, mlu, lowerBound, gap, cpuTime).
function get_solution_by_graph(network::NetworkGraph, r, demands, capacities, maxSeg;
                               timeLimitSec = 900)
    graph = network.graph
    n = nv(graph)
    edgeList = collect(edges(graph))

    model = JuMP.Model(HiGHS.Optimizer)
    set_time_limit_sec(model, timeLimitSec)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)  # stop at 1% gap
    set_silent(model)

    # x^{d,0}_{ij}: 1 if demand d uses segment (i, j) at time 0.
    @variable(model, x[d in demands, i in 1:n, j in 1:n; i != j], Bin)

    # λ: the maximum link utilization (MLU) being minimized.
    @variable(model, lambda >= 0)

    # (1) Flow conservation on segments, per demand.
    for demand in demands, i in 1:n
        rhs = (i == demand.source) ? 1 : ((i == demand.target) ? -1 : 0)
        @constraint(model,
            sum(x[demand, i, j] for j in 1:n if i != j) -
            sum(x[demand, j, i] for j in 1:n if i != j) == rhs
        )
    end

    # (2) Segment cap maxSeg, per demand.
    for demand in demands
        @constraint(model, sum(x[demand, i, j] for i in 1:n, j in 1:n if i != j) <= maxSeg)
    end

    # (3) Load on each arc a = (u, v): routed traffic <= λ · c(a).
    for edge in edgeList
        u, v = src(edge), dst(edge)
        # c(a): capacity of arc a
        c = capacities[(u, v)]
        load = @expression(model, sum(
            # r(i, j, a) · φ(d, 0) · x^{d,0}_{ij}
            get(r, (i, j, (u, v)), 0.0) * demand.volumes[1] * x[demand, i, j]
            for demand in demands, i in 1:n, j in 1:n if i != j
        ))
        @constraint(model, load <= lambda * c)
    end

    @objective(model, Min, lambda)

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

end # module Model
