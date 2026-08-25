module Graph

using Graphs

export NetworkGraph, get_graph_from_json, is_jsonData_valid, get_edgeData_by_graph,
    get_capacities_by_graph, get_vertex_by_jsonId

struct NetworkGraph{G<:AbstractGraph}
    graph::G

    # One entry per Julia vertex.
    # nodeData[v] = (jsonId = ..., name = ...)
    nodeData::Vector{NamedTuple{(:jsonId, :name), Tuple{Int, String}}}

    # Translation from JSON node id to Graphs.jl vertex number.
    jsonToVertex::Dict{Int, Int}

    # Edge attributes indexed by Julia endpoints (u,v).
    edgeData::Dict{
        Tuple{Int, Int},
        NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}
    }
end

# Build a NetworkGraph from already-parsed JSON data (e.g. the result of
# JSON3.read). No validation is performed on `data`; it is assumed to have the
# expected fields (directed, nodes, links, ...).
function get_graph_from_json(data)
    n = length(data.nodes)

    # Map JSON ids to Julia vertices 1,...,n.
    jsonToVertex = Dict{Int, Int}()
    nodeData = Vector{
        NamedTuple{(:jsonId, :name), Tuple{Int, String}}
    }(undef, n)

    for (v, node) in enumerate(data.nodes)
        id = Int(node.id)
        jsonToVertex[id] = v
        nodeData[v] = (
            jsonId = id,
            name = String(node.name),
        )
    end

    # Directed or undirected graph according to the JSON field.
    graph = Bool(data.directed) ? SimpleDiGraph(n) : SimpleGraph(n)

    edgeData = Dict{
        Tuple{Int, Int},
        NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}
    }()

    for link in data.links
        u = jsonToVertex[Int(link.from)]
        v = jsonToVertex[Int(link.to)]

        key = Bool(data.directed) ? (u, v) : minmax(u, v)

        add_edge!(graph, u, v)

        edgeData[key] = (
            id       = Int(link.id),
            metric   = Float64(link.metric),
            capacity = Float64(link.capacity),
        )
    end

    return NetworkGraph(graph, nodeData, jsonToVertex, edgeData)
end

# Return `true` if already-parsed JSON network data is well-formed for
# get_graph_from_json, `false` otherwise. A `@warn` describes the first problem
# found so failures stay diagnosable.
function is_jsonData_valid(data)
    for field in (:directed, :multigraph, :nodes, :links)
        if !hasproperty(data, field)
            @warn "Missing JSON field: $field"
            return false
        end
    end

    # Note: the `multigraph` flag only declares that parallel arcs are *allowed*;
    # the setA instances set it to true without actually containing any parallel
    # arcs. We therefore accept the flag and instead reject only real parallel
    # arcs (below), which SimpleGraph/SimpleDiGraph genuinely cannot represent.

    # Collect node ids, checking for duplicates.
    ids = Set{Int}()
    for node in data.nodes
        id = Int(node.id)
        if id in ids
            @warn "Duplicate node id in JSON: $id"
            return false
        end
        push!(ids, id)
    end

    # Check links: endpoints must be known nodes, no repeated endpoint pair
    # (actual parallel arcs are unsupported by SimpleGraph/SimpleDiGraph).
    seen = Set{Tuple{Int, Int}}()
    for link in data.links
        fromId = Int(link.from)
        toId   = Int(link.to)

        if !(fromId in ids)
            @warn "Unknown node id in link: $fromId"
            return false
        end
        if !(toId in ids)
            @warn "Unknown node id in link: $toId"
            return false
        end

        key = Bool(data.directed) ? (fromId, toId) : minmax(fromId, toId)
        if key in seen
            @warn "Multiple links between the same endpoints are not supported (uses SimpleGraph/SimpleDiGraph)."
            return false
        end
        push!(seen, key)
    end

    return true
end

# Look up an arc's stored attributes (id, metric, capacity) by its endpoints.
# The key convention must match how get_graph_from_json stored the edge:
# (u,v) for directed graphs, minmax(u,v) for undirected.
function get_edgeData_by_graph(network::NetworkGraph, u::Integer, v::Integer)
    key = is_directed(network.graph) ? (Int(u), Int(v)) : minmax(Int(u), Int(v))
    return network.edgeData[key]
end

# Translate a JSON node id to its Julia vertex number (inverse of the
# nodeData[v].jsonId mapping recorded by get_graph_from_json).
function get_vertex_by_jsonId(network::NetworkGraph, id::Integer)
    return network.jsonToVertex[Int(id)]
end

# Arc capacities c(a): a map from each arc (keyed by its endpoints, same
# convention as get_edgeData_by_graph) to the capacity stored in edgeData.
function get_capacities_by_graph(network::NetworkGraph)
    graph = network.graph
    # c(a): capacity of arc a = (u, v)
    capacities = Dict{Tuple{Int, Int}, Float64}()
    for edge in edges(graph)
        u, v = src(edge), dst(edge)
        key = is_directed(graph) ? (Int(u), Int(v)) : minmax(Int(u), Int(v))
        capacities[key] = get_edgeData_by_graph(network, u, v).capacity
    end
    return capacities
end

end # module Graph
