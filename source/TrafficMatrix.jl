module TrafficMatrix

# Depends only on the Graph module, for the NetworkGraph type and the JSON-id →
# vertex translation. Parsing of tm.json stays in the notebook, so we take
# already-parsed data (like Graph.get_graph_from_json) and need no JSON3 here.
using ..Graph: NetworkGraph, get_vertex_by_jsonId

export get_demands_from_json

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

end # module TrafficMatrix
