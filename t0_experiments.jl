### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# ╔═╡ b0000000-0000-4000-8000-000000000002
begin
    using JSON3
    include(joinpath(@__DIR__, "source", "Graph.jl"))
    using .Graph
end

# ╔═╡ b0000000-0000-4000-8000-000000000001
md"""
# Step 1 — Load the network graph
"""

# ╔═╡ b0000000-0000-4000-8000-000000000003
begin
    net_file = joinpath(@__DIR__, "data", "setA-01-net.json")
    json = JSON3.read(read(net_file, String))

    graph = try
        check_json_data(json)   # throws a descriptive error if invalid
        get_graph_from_json(json)
    catch err
        rethrow(err)
    end
end

# ╔═╡ Cell order:
# ╟─b0000000-0000-4000-8000-000000000001
# ╠═b0000000-0000-4000-8000-000000000002
# ╠═b0000000-0000-4000-8000-000000000003
