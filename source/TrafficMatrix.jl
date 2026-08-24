module TrafficMatrix

# Depends only on the Graph module, for the NetworkGraph type and the JSON-id →
# vertex translation. Parsing of tm.json stays in the notebook, so we take
# already-parsed data (like Graph.get_graph_from_json) and need no JSON3 here.
using ..Graph: NetworkGraph, get_vertex_by_jsonId

export get_demands_from_json, is_tmData_valid

# The traffic demands from an already-parsed tm.json document. Each demand is a
# source→target flow with its per-time-slot volumes:
#
#   (id, source, target, volumes)
#
# `source`/`target` are Julia vertex numbers, translated from the JSON node ids
# via `network`. `volumes[t + 1]` = φ(d, t): the volume of demand d in time slot
# t (the whole traffic matrix is loaded, so t=0 and t=1 are both available).
function get_demands_from_json(data, network::NetworkGraph)
    demands = Vector{
        NamedTuple{(:id, :source, :target, :volumes),
                   Tuple{Int, Int, Int, Vector{Float64}}}
    }(undef, length(data.demands))

    for (id, demand) in enumerate(data.demands)
        source = get_vertex_by_jsonId(network, demand.s)
        target = get_vertex_by_jsonId(network, demand.t)
        # φ(d, t): per-time-slot volume vector v from the JSON
        volumes = Float64.(demand.v)

        demands[id] = (
            id      = id,
            source  = source,
            target  = target,
            volumes = volumes,
        )
    end

    return demands
end

# Return `true` if already-parsed tm.json data is well-formed for
# get_demands_from_json, `false` otherwise. A `@warn` describes the first problem
# found so failures stay diagnosable; the caller decides whether to error().
function is_tmData_valid(data)
    if !hasproperty(data, :demands)
        @warn "Missing JSON field: demands"
        return false
    end

    # If the number of time slots is declared, every volume vector must match it.
    slots = hasproperty(data, :num_time_slots) ? Int(data.num_time_slots) : nothing

    for (id, demand) in enumerate(data.demands)
        for field in (:s, :t, :v)
            if !hasproperty(demand, field)
                @warn "Demand $id is missing JSON field: $field"
                return false
            end
        end

        if !(demand.v isa AbstractVector) || isempty(demand.v)
            @warn "Demand $id has an empty or non-array volume vector v."
            return false
        end

        if slots !== nothing && length(demand.v) != slots
            @warn "Demand $id has $(length(demand.v)) volumes but num_time_slots = $slots."
            return false
        end
    end

    return true
end

end # module TrafficMatrix
