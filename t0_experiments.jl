### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# ╔═╡ b0000000-0000-4000-8000-000000000002
begin
    using JSON3
    using Dates
    using Graphs
    using JuMP
    using HiGHS
    using ProgressLogging
    include(joinpath(@__DIR__, "source", "Graph.jl"))
    using .Graph
    include(joinpath(@__DIR__, "source", "SplitCoefficients.jl"))
    using .SplitCoefficients
    include(joinpath(@__DIR__, "source", "TrafficMatrix.jl"))
    using .TrafficMatrix
    include(joinpath(@__DIR__, "source", "Scenario.jl"))
    using .Scenario
    include(joinpath(@__DIR__, "source", "Model.jl"))
    using .Model
    include(joinpath(@__DIR__, "source", "Result.jl"))
    using .Result
end

# ╔═╡ b0000000-0000-4000-8000-000000000001
md"""
# Step 1 — Load the network graph
"""

# ╔═╡ b0000000-0000-4000-8000-00000000000b
dataDir = joinpath(@__DIR__, "data")

# ╔═╡ b0000000-0000-4000-8000-00000000000c
# Load and validate the network graph from one instance's -net.json.
function get_graph_from_instance(dataDir, instanceName)
    net_file = joinpath(dataDir, "$instanceName-net.json")
    json = JSON3.read(read(net_file, String))
    is_jsonData_valid(json) ||
        error("Invalid network JSON: $net_file")
    return get_graph_from_json(json)
end

# ╔═╡ b0000000-0000-4000-8000-000000000003
graph = get_graph_from_instance(dataDir, "setA-01")

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

# ╔═╡ b0000000-0000-4000-8000-00000000000d
# φ(d, t): demand volumes, loaded and validated from one instance's -tm.json.
function get_demands_from_instance(dataDir, instanceName, graph)
    tm_file = joinpath(dataDir, "$instanceName-tm.json")
    tm = JSON3.read(read(tm_file, String))
    is_tmData_valid(tm) ||
        error("Invalid traffic-matrix JSON: $tm_file")
    return get_demands_from_json(tm, graph)
end

# ╔═╡ b0000000-0000-4000-8000-00000000000e
# maxSeg: loaded and validated from one instance's -scenario.json.
function get_maxSegments_from_instance(dataDir, instanceName)
    scenario_file = joinpath(dataDir, "$instanceName-scenario.json")
    scenario = JSON3.read(read(scenario_file, String))
    is_scenarioData_valid(scenario) ||
        error("Invalid scenario JSON: $scenario_file")
    return get_maxSegments_from_json(scenario)
end

# ╔═╡ b0000000-0000-4000-8000-000000000007
# c(a): capacity of every arc, read from the graph's edge data.
capacities = get_capacities_by_graph(graph)

# ╔═╡ b0000000-0000-4000-8000-00000000000f
demands = get_demands_from_instance(dataDir, "setA-01", graph)

# ╔═╡ b0000000-0000-4000-8000-000000000010
maxSeg = get_maxSegments_from_instance(dataDir, "setA-01")

# ╔═╡ b0000000-0000-4000-8000-000000000008
md"""
# Step 4 — Period-0 model (MLU minimization)

Build and solve the MILP for time period 0: pick a segment path for every demand
so the maximum link utilization `λ` (MLU) is minimized, subject to flow
conservation, the `maxSeg` cap, and the per-arc load constraint.
"""

# ╔═╡ b0000000-0000-4000-8000-00000000001b
# maxLevels: depth of the lexicographic descent (objective 5) that solve! runs —
# minimize the MLU (level 1), then flatten the sorted load vector below it. 1 = MLU
# only; higher flattens more of the profile. Edit and re-run to sweep depth. See
# Model.solve!.
maxLevels = 8

# ╔═╡ b0000000-0000-4000-8000-000000000009
begin
    # Assemble the period-0 model with the fluent builder, then hand the caller a
    # solvable AsrModel — nothing is solved until `solve!` below. The model is
    # period-aware; for steps 1–5 the period set is just {0} (no budget step).
    n = nv(graph.graph)
    periods = 0:0
    # periodInputs[t] = (graph = G_t, r = r_t): here only the nominal period 0.
    periodInputs = Dict(0 => (graph = graph, r = r))
    builder = AsrModelBuilder(; timeLimitSec = 900)
    set_variables!(builder, demands, n, periods)
    set_flowConservation!(builder, demands, n, periods)
    set_segmentCap!(builder, demands, n, maxSeg, periods)
    set_loadBounds!(builder, periodInputs, demands, periods)
    model = build(builder)
end

# ╔═╡ b0000000-0000-4000-8000-00000000001a
solution = solve!(model; maxLevels)

# ╔═╡ b0000000-0000-4000-8000-00000000000a
(
    status  = solution.status,
    mlu     = solution.mlu,
    gap     = solution.gap,
    cpuTime = solution.cpuTime,
)

# ╔═╡ b0000000-0000-4000-8000-000000000011
md"""
# Step 5 — Numerical experiments on all setA instances

Run the period-0 pipeline over every instance found in `data/` (900 s solve limit
each) and tabulate vertices, links, demands, and the solve outcome (MLU, gap,
status, CPU time). Every stage reuses the same functions as the single-instance
walkthrough above — nothing is duplicated.
"""

# ╔═╡ b0000000-0000-4000-8000-000000000012
# Instance stems (e.g. "setA-01") discovered from the -net.json files in `data/`.
get_instanceNames_from_dir(dataDir) =
    sort([replace(f, "-net.json" => "")
          for f in readdir(dataDir) if endswith(f, "-net.json")])

# ╔═╡ b0000000-0000-4000-8000-000000000013
# One result row for a single instance: run the whole period-0 pipeline and return its
# graph metadata plus the solve outcome, recording each pipeline step into `events`.
function get_experimentRow_from_instance(dataDir, instanceName, events; timeLimitSec = 900, maxLevels = 8)
    record_event!(events, "loading instance data")
    graph      = get_graph_from_instance(dataDir, instanceName)
    record_event!(events, "graph calculated")
    r          = get_splitCoefficients_by_graph(graph)
    demands    = get_demands_from_instance(dataDir, instanceName, graph)
    maxSeg     = get_maxSegments_from_instance(dataDir, instanceName)
    record_event!(events, "parameters built")
    record_event!(events, "building model")
    n          = nv(graph.graph)
    periods    = 0:0
    periodInputs = Dict(0 => (graph = graph, r = r))
    builder    = AsrModelBuilder(; timeLimitSec)
    set_variables!(builder, demands, n, periods)
    set_flowConservation!(builder, demands, n, periods)
    set_segmentCap!(builder, demands, n, maxSeg, periods)
    set_loadBounds!(builder, periodInputs, demands, periods)
    model      = build(builder)
    record_event!(events, "solving model")
    # Lexicographic descent (objective 5); maxLevels caps the depth. See Model.solve!.
    solution   = solve!(model; maxLevels)
    record_event!(events, "model solved")
    # Decode the routing scheme: per-demand waypoint lists (JSON node ids) for the
    # only period here, 0. Empty for a demand routed on shortest paths, or for the
    # whole run if infeasible.
    waypoints  = get_waypoints_by_solvedModel(model, periodInputs, demands, periods)[0]
    record_event!(events, "waypoints decoded")
    return (
        instance   = instanceName,
        vertices   = nv(graph.graph),
        links      = ne(graph.graph),
        demands    = length(demands),
        status     = solution.status,
        mlu        = solution.mlu,
        lowerBound = solution.lowerBound,
        gap        = solution.gap,
        cpuTime    = solution.cpuTime,
        waypoints  = waypoints,
        events     = events,
    )
end

# ╔═╡ b0000000-0000-4000-8000-000000000015
md"""
## Persist the results

The sweep writes each instance to `t0_results/<timestamp>/<index>.json` **as it
finishes**, not in one final batch — so cancelling the notebook keeps every instance
that already completed. Each file holds the instance's index, whether the run
succeeded, the solve metrics, the per-demand routing `waypoints`, and an `events` log
recording each pipeline step (and any failure).

The document shape and the write itself live in the shared `Result` module — the same
`get_resultDoc_by_experimentRow` / `save_resultDoc_to_json` used by the headless
`scripts/solve_instance.jl`, so both paths emit one schema. This is the write-side
mirror of the `get_*_from_instance` readers.
"""

# ╔═╡ b0000000-0000-4000-8000-000000000016
t0ResultsDir = joinpath(@__DIR__, "t0_results")

# ╔═╡ b0000000-0000-4000-8000-000000000014
let
    # One run directory per sweep, minted once and reused; each instance's file lands here
    # the moment it finishes (the directory is created lazily by the first save), so
    # cancelling the notebook keeps whatever already completed.
    runDir = get_runDir_by_timestamp(t0ResultsDir)
    @progress for instanceName in get_instanceNames_from_dir(dataDir)
        events = NamedTuple[]
        row = try
            get_experimentRow_from_instance(dataDir, instanceName, events; maxLevels)
        catch err
            # Keep one bad instance from aborting the whole sweep: record the failure, log
            # it, and emit a same-schema row so the saved file stays on-schema (missing
            # metrics, status = :error as the sentinel).
            record_event!(events, sprint(showerror, err); level = :error)
            @warn "Experiment failed for instance" instanceName exception = (err, catch_backtrace())
            (
                instance = instanceName,
                vertices = missing, links = missing, demands = missing,
                status = :error,
                mlu = missing, lowerBound = missing, gap = missing, cpuTime = missing,
                waypoints = missing, events = events,
            )
        end
        save_resultDoc_to_json(get_resultDoc_by_experimentRow(row), runDir)
    end
    runDir
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
Graphs = "86223c79-3864-5bf0-83f7-82e725a168b6"
HiGHS = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
JSON3 = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
ProgressLogging = "33c8b6b6-d38a-422a-b730-caa89a2f386c"

[compat]
Graphs = "~1.14.0"
HiGHS = "~1.24.1"
JSON3 = "~1.14.3"
JuMP = "~1.31.2"
ProgressLogging = "~0.1.6"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.12.6"
manifest_format = "2.0"
project_hash = "1bb48eebd1ff683a93250de9fac39ac3887bd126"

[[deps.ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "d57bd3762d308bded22c3b82d033bff85f6195c6"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.4.0"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1b96ea4a01afe0ea4090c5c8039690672dd13f2e"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.9+0"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "TranscodingStreams"]
git-tree-sha1 = "84990fa864b7f2b4901901ca12736e45ee79068c"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.8.5"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "970758a3d591a2a5c2a907c53f2e2f8c1b1d3537"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.9"

[[deps.CommonSubexpressions]]
deps = ["MacroTools"]
git-tree-sha1 = "cda2cfaebb4be89c9084adaca7dd7333369715c5"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.1"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.3.0+1"

[[deps.DataStructures]]
deps = ["OrderedCollections"]
git-tree-sha1 = "b0bc6d2cad1fed8b7fd59a1551a991cb3d2809e6"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.19.6"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "79a2aca180a85c690c58a020d47b426954b590f8"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.16.0"

[[deps.DocStringExtensions]]
git-tree-sha1 = "7442a5dfe1ebb773c29cc2962a8980f47221d76c"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.5"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "1b86cca764a61dcac4fef4c5e16e378e5ed6953c"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "1.4.5"
weakdeps = ["StaticArrays"]

    [deps.ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

[[deps.Graphs]]
deps = ["ArnoldiMethod", "DataStructures", "Inflate", "LinearAlgebra", "Random", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "7eb45fe833a5b7c51cf6d89c5a841d5967e44be3"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.14.0"

    [deps.Graphs.extensions]
    GraphsSharedArraysExt = "SharedArrays"

    [deps.Graphs.weakdeps]
    Distributed = "8ba89e20-285c-5b6f-9357-94700520ee1b"
    SharedArrays = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.HiGHS]]
deps = ["HiGHS_jll", "LinearAlgebra", "MathOptIIS", "MathOptInterface", "OpenBLAS32_jll", "PrecompileTools", "SparseArrays"]
git-tree-sha1 = "01a5241985559c08a5baadbcebd6d87daaf84a84"
uuid = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
version = "1.24.1"

[[deps.HiGHS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Zlib_jll", "libblastrampoline_jll"]
git-tree-sha1 = "2d9747b79d17c4320fe48048a3a768fe6d6d82de"
uuid = "8fd58aa0-07eb-5a78-9b36-339c94fd15ea"
version = "1.15.1+1"

[[deps.Inflate]]
git-tree-sha1 = "d1b1b796e47d94588b3757fe84fbf65a5ec4a80d"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.5"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "b2d91fe939cae05960e760110b328288867b5758"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.6"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7204148362dafe5fe6a273f855b8ccbe4df8173e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.8.0"

[[deps.JSON]]
deps = ["Dates", "Logging", "Parsers", "PrecompileTools", "StructUtils", "UUIDs", "Unicode"]
git-tree-sha1 = "c7345ab1a7ca4dc8a02c9f6510da0d9857bbe513"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "1.7.1"

    [deps.JSON.extensions]
    JSONArrowExt = ["ArrowTypes"]

    [deps.JSON.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

[[deps.JSON3]]
deps = ["Dates", "Mmap", "Parsers", "PrecompileTools", "StructTypes", "UUIDs"]
git-tree-sha1 = "411eccfe8aba0814ffa0fdf4860913ed09c34975"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.14.3"

    [deps.JSON3.extensions]
    JSON3ArrowExt = ["ArrowTypes"]

    [deps.JSON3.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

[[deps.JuMP]]
deps = ["LinearAlgebra", "MacroTools", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays"]
git-tree-sha1 = "4f27b21df3b47e8c08a83ead049afb621b2f5b3c"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.31.2"

    [deps.JuMP.extensions]
    JuMPDimensionalDataExt = "DimensionalData"

    [deps.JuMP.weakdeps]
    DimensionalData = "0703355e-b756-11e9-17c0-8b28908087d0"

[[deps.JuliaSyntaxHighlighting]]
deps = ["StyledStrings"]
uuid = "ac6e5ff7-fb65-4e79-a425-ec3bc9c03011"
version = "1.12.0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.12.0"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "bba2d9aa057d8f126415de240573e86a8f39d2a1"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "1.0.1"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.MacroTools]]
git-tree-sha1 = "1e0228a030642014fe5cfe68c2c0a818f9e3f522"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.16"

[[deps.Markdown]]
deps = ["Base64", "JuliaSyntaxHighlighting", "StyledStrings"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.MathOptIIS]]
deps = ["MathOptInterface"]
git-tree-sha1 = "3b3d69130d8ab8c39d5fa4d30e20a8e6428c9d37"
uuid = "8c4f8055-bd93-4160-a86b-a0c04941dbff"
version = "0.2.0"

[[deps.MathOptInterface]]
deps = ["CodecBzip2", "CodecZlib", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays", "SpecialFunctions", "Test"]
git-tree-sha1 = "d10ba577e0b5a0481fab01dfd31fb20af3326954"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.53.0"

    [deps.MathOptInterface.extensions]
    MathOptInterfaceBenchmarkToolsExt = "BenchmarkTools"
    MathOptInterfaceCliqueTreesExt = "CliqueTrees"

    [deps.MathOptInterface.weakdeps]
    BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
    CliqueTrees = "60701a23-6482-424a-84db-faee86b9b1f8"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"
version = "1.11.0"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "dc5b2c4c111c46bc79ac4405eeb563523b39c004"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.8.0"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "dbd2e8cd2c1c27f0b584f6661b4309609c5a685e"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.1.4"

[[deps.OpenBLAS32_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "libblastrampoline_jll"]
git-tree-sha1 = "30870d0f2dc0b2dba76b10df1c58c7f018413e56"
uuid = "656ef2d0-ae68-5445-9ca0-591084a874a2"
version = "0.3.34+0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.29+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.7+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1346c9208249809840c91b26703912dff463d335"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.6+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "05f45c2e0de6259db764adbfd2f1dc6d3f8de13c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "2.0.1"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "3de8f5e6e90ebfa8d6d1f86997d6cdcd6a912ff3"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.7"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "edbeefc7a4889f528644251bdb5fc9ab5348bc2c"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.3.4"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "8b770b60760d4451834fe79dd483e318eee709c4"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.5.2"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.ProgressLogging]]
deps = ["Logging", "SHA", "UUIDs"]
git-tree-sha1 = "f0803bc1171e455a04124affa9c21bba5ac4db32"
uuid = "33c8b6b6-d38a-422a-b730-caa89a2f386c"
version = "0.1.6"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "7ddb0b49c109481b046972c0e4ab02b2127d6a75"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.6"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.12.0"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "429071b23f4c9a13fb6582f807cc2ef454082408"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.9.0"

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

    [deps.SpecialFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "PrecompileTools", "Random", "StaticArraysCore"]
git-tree-sha1 = "fac51faf3bb96e8bc0bf6f9f39ca4955652776bb"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.9.19"

    [deps.StaticArrays.extensions]
    StaticArraysChainRulesCoreExt = "ChainRulesCore"
    StaticArraysStatisticsExt = "Statistics"

    [deps.StaticArrays.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6ab403037779dae8c514bad259f32a447262455a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.4"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "ae3bb1eb3bba077cd276bc5cfc337cc65c3075c0"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.1"
weakdeps = ["SparseArrays"]

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

[[deps.StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "159331b30e94d7b11379037feeb9b690950cace8"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.11.0"

[[deps.StructUtils]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "2d0fc55c61321ba245c47be599570d11bac50303"
uuid = "ec057cc2-7a8d-4b58-b3b3-92acb9f63b42"
version = "2.8.5"

    [deps.StructUtils.extensions]
    StructUtilsMeasurementsExt = ["Measurements"]
    StructUtilsStaticArraysCoreExt = ["StaticArraysCore"]
    StructUtilsTablesExt = ["Tables"]

    [deps.StructUtils.weakdeps]
    Measurements = "eff96d63-e80a-5855-80a2-b1b0885c5ab7"
    StaticArraysCore = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
    Tables = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"

[[deps.StyledStrings]]
uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
version = "1.11.0"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.8.3+2"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.TranscodingStreams]]
git-tree-sha1 = "0c45878dcfdcfa8480052b6ab162cdd138781742"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.11.3"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.3.1+2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.15.0+0"
"""

# ╔═╡ Cell order:
# ╟─b0000000-0000-4000-8000-000000000001
# ╠═b0000000-0000-4000-8000-000000000002
# ╠═b0000000-0000-4000-8000-00000000000b
# ╠═b0000000-0000-4000-8000-00000000000c
# ╠═b0000000-0000-4000-8000-000000000003
# ╟─b0000000-0000-4000-8000-000000000004
# ╠═b0000000-0000-4000-8000-000000000005
# ╟─b0000000-0000-4000-8000-000000000006
# ╠═b0000000-0000-4000-8000-00000000000d
# ╠═b0000000-0000-4000-8000-00000000000e
# ╠═b0000000-0000-4000-8000-000000000007
# ╠═b0000000-0000-4000-8000-00000000000f
# ╠═b0000000-0000-4000-8000-000000000010
# ╟─b0000000-0000-4000-8000-000000000008
# ╠═b0000000-0000-4000-8000-00000000001b
# ╠═b0000000-0000-4000-8000-000000000009
# ╠═b0000000-0000-4000-8000-00000000001a
# ╠═b0000000-0000-4000-8000-00000000000a
# ╟─b0000000-0000-4000-8000-000000000011
# ╠═b0000000-0000-4000-8000-000000000012
# ╠═b0000000-0000-4000-8000-000000000013
# ╟─b0000000-0000-4000-8000-000000000015
# ╠═b0000000-0000-4000-8000-000000000016
# ╠═b0000000-0000-4000-8000-000000000014
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
