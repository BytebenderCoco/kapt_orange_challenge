module Graph

using Graphs

export NetworkGraph, get_graph_from_json, check_json_data, get_edgeData_by_graph

struct NetworkGraph{G<:AbstractGraph}
    graph::G

    # One entry per Julia vertex.
    # node_data[v] = (json_id = ..., name = ...)
    node_data::Vector{NamedTuple{(:json_id, :name), Tuple{Int, String}}}

    # Translation from JSON node id to Graphs.jl vertex number.
    json_to_vertex::Dict{Int, Int}

    # Edge attributes indexed by Julia endpoints (u,v).
    edge_data::Dict{
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
    json_to_vertex = Dict{Int, Int}()
    node_data = Vector{
        NamedTuple{(:json_id, :name), Tuple{Int, String}}
    }(undef, n)

    for (v, node) in enumerate(data.nodes)
        id = Int(node.id)
        json_to_vertex[id] = v
        node_data[v] = (
            json_id = id,
            name = String(node.name),
        )
    end

    # Directed or undirected graph according to the JSON field.
    g = Bool(data.directed) ? SimpleDiGraph(n) : SimpleGraph(n)

    edge_data = Dict{
        Tuple{Int, Int},
        NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}
    }()

    for link in data.links
        u = json_to_vertex[Int(link.from)]
        v = json_to_vertex[Int(link.to)]

        key = Bool(data.directed) ? (u, v) : minmax(u, v)

        add_edge!(g, u, v)

        edge_data[key] = (
            id       = Int(link.id),
            metric   = Float64(link.metric),
            capacity = Float64(link.capacity),
        )
    end

    return NetworkGraph(g, node_data, json_to_vertex, edge_data)
end

# Validate already-parsed JSON network data. Throws an error describing the
# first problem found; returns `nothing` if the data is well-formed for
# get_graph_from_json.
function check_json_data(data)
    hasproperty(data, :directed) ||
        error("Missing JSON field: directed")
    hasproperty(data, :multigraph) ||
        error("Missing JSON field: multigraph")
    hasproperty(data, :nodes) ||
        error("Missing JSON field: nodes")
    hasproperty(data, :links) ||
        error("Missing JSON field: links")

    Bool(data.multigraph) &&
        error("This notebook uses SimpleGraph/SimpleDiGraph and therefore does not support multigraph=true.")

    # Collect node ids, checking for duplicates.
    ids = Set{Int}()
    for node in data.nodes
        id = Int(node.id)
        (id in ids) &&
            error("Duplicate node id in JSON: $id")
        push!(ids, id)
    end

    # Check links: endpoints must be known nodes, no repeated endpoint pair.
    seen = Set{Tuple{Int, Int}}()
    for link in data.links
        from_id = Int(link.from)
        to_id   = Int(link.to)

        (from_id in ids) ||
            error("Unknown node id in link: $from_id")
        (to_id in ids) ||
            error("Unknown node id in link: $to_id")

        key = Bool(data.directed) ? (from_id, to_id) : minmax(from_id, to_id)
        (key in seen) &&
            error("Multiple links between the same endpoints are not supported when multigraph=false.")
        push!(seen, key)
    end

    return nothing
end

# Look up an arc's stored attributes (id, metric, capacity) by its endpoints.
# The key convention must match how get_graph_from_json stored the edge:
# (u,v) for directed graphs, minmax(u,v) for undirected.
function get_edgeData_by_graph(net::NetworkGraph, u::Integer, v::Integer)
    key = is_directed(net.graph) ? (Int(u), Int(v)) : minmax(Int(u), Int(v))
    return net.edge_data[key]
end

end # module Graph
