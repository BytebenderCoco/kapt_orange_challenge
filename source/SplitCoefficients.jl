module SplitCoefficients

using Graphs
# Import only the specific names we need from the sibling Graph module, to avoid
# clashing with Graphs.jl (which exports a name `Graph` = SimpleGraph).
using ..Graph: NetworkGraph, get_edgeData_by_graph

export get_splitCoefficients_by_graph

# Arc-weight matrix: metricMatrix[u, v] = weight ω of a direct arc u->v, 0 on the
# diagonal, Inf where there is no direct arc. This is the weight matrix Dijkstra
# consumes.
function get_metricMatrix_by_graph(network::NetworkGraph)
    graph = network.graph
    n = nv(graph)

    metricMatrix = fill(Inf, n, n)

    for v in vertices(graph)
        metricMatrix[v, v] = 0.0
    end

    for edge in edges(graph)
        u, v = src(edge), dst(edge)
        # ω(a): weight of arc a = (u, v)
        omega = get_edgeData_by_graph(network, u, v).metric

        omega < 0 &&
            error("Dijkstra's algorithm requires non-negative metric values.")

        metricMatrix[u, v] = omega

        if !is_directed(graph)
            metricMatrix[v, u] = omega
        end
    end

    return metricMatrix
end

# All-pairs shortest-path distances d[i, j] and equal-cost path counts σ[i, j]
# (the number of equal-cost shortest paths), assembled by running the counting
# Dijkstra from every source. Both fall out of one Dijkstra sweep per source, so
# they are returned together.
function get_ecmpData_by_graph(graph, metricMatrix)
    n = nv(graph)
    d = fill(Inf, n, n)
    # σ[i, j]: number of equal-cost shortest i→j paths
    sigma = zeros(Float64, n, n)
    for i in vertices(graph)
        dijkstraState = dijkstra_shortest_paths(graph, i, metricMatrix; allpaths = true)
        d[i, :] .= dijkstraState.dists
        sigma[i, :] .= dijkstraState.pathcounts
    end
    return d, sigma
end

# The split coefficients r(i, j, a): the fraction of shortest-path i->j flow that
# traverses arc a=(u, v), as the path-count ratio σ_iu * σ_vj / σ_ij for arcs
# that lie on a shortest i->j path (and 0 otherwise).
function get_splitCoefficients_by_graph(network::NetworkGraph)
    graph = network.graph
    n = nv(graph)
    metricMatrix = get_metricMatrix_by_graph(network)
    d, sigma = get_ecmpData_by_graph(graph, metricMatrix)

    r = Dict{Tuple{Int, Int, Tuple{Int, Int}}, Float64}()

    for i in 1:n, j in 1:n
        if i == j || !isfinite(d[i, j]) || sigma[i, j] == 0
            continue
        end
        for edge in edges(graph)
            u, v = src(edge), dst(edge)
            # ω(a): weight of arc a = (u, v)
            omega = metricMatrix[u, v]

            # Arc-on-shortest-path test: d_iu + ω + d_vj == d_ij.
            if isapprox(d[i, u] + omega + d[v, j], d[i, j]; atol=1e-6)
                # r(i, j, a) = σ_iu · σ_vj / σ_ij
                r[(i, j, (u, v))] = (sigma[i, u] * sigma[v, j]) / sigma[i, j]
            end
        end
    end
    return r
end

end # module SplitCoefficients
