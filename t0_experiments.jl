### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# ╔═╡ b0000000-0000-4000-8000-000000000002
begin
    using JSON3
    include(joinpath(@__DIR__, "source", "Graph.jl"))
    using .Graph
    include(joinpath(@__DIR__, "source", "SplitCoefficients.jl"))
    using .SplitCoefficients
    include(joinpath(@__DIR__, "source", "TrafficMatrix.jl"))
    using .TrafficMatrix
    include(joinpath(@__DIR__, "source", "Scenario.jl"))
    using .Scenario
end

# ╔═╡ b0000000-0000-4000-8000-000000000001
md"""
# Step 1 — Load the network graph
"""

# ╔═╡ b0000000-0000-4000-8000-000000000003
begin
    net_file = joinpath(@__DIR__, "data", "setA-01-net.json")
    json = JSON3.read(read(net_file, String))

    is_jsonData_valid(json) ||
        error("Invalid network JSON: $net_file")

    graph = get_graph_from_json(json)
end

# ╔═╡ b0000000-0000-4000-8000-000000000004
md"""
# Step 2 — Compute the split coefficients `r`
"""

# ╔═╡ b0000000-0000-4000-8000-000000000005
r = get_splitCoefficients_by_graph(graph)

# ╔═╡ b0000000-0000-4000-8000-000000000006
md"""
# Step 3 — Derive the model parameters (Data section)

Assemble the parameters the model consumes from the three input files: link
capacities `c(a)` from the net (Step 1), the split coefficients `r` (Step 2),
the demands `φ(d, t)` from the traffic matrix, and `maxSeg` from the scenario.
"""

# ╔═╡ b0000000-0000-4000-8000-000000000007
# c(a): capacity of every arc, read from the graph's edge data.
capacities = get_capacities_by_graph(graph)

# ╔═╡ b0000000-0000-4000-8000-000000000008
begin
    tm_file = joinpath(@__DIR__, "data", "setA-01-tm.json")
    tm = JSON3.read(read(tm_file, String))

    demands = get_demands_from_json(tm, graph)
end

# ╔═╡ b0000000-0000-4000-8000-000000000009
begin
    scenario_file = joinpath(@__DIR__, "data", "setA-01-scenario.json")
    scenario = JSON3.read(read(scenario_file, String))

    maxSeg = get_maxSegments_from_json(scenario)
end

# ╔═╡ Cell order:
# ╟─b0000000-0000-4000-8000-000000000001
# ╠═b0000000-0000-4000-8000-000000000002
# ╠═b0000000-0000-4000-8000-000000000003
# ╟─b0000000-0000-4000-8000-000000000004
# ╠═b0000000-0000-4000-8000-000000000005
# ╟─b0000000-0000-4000-8000-000000000006
# ╠═b0000000-0000-4000-8000-000000000007
# ╠═b0000000-0000-4000-8000-000000000008
# ╠═b0000000-0000-4000-8000-000000000009
