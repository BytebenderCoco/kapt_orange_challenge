# Orange Challenge — ROADEF 2026

Julia + Pluto notebook implementation of the Orange ROADEF 2026 challenge.
It models the Traffic-ASR segment-routing problem as a MILP (JuMP + HiGHS) and
minimizes the maximum link utilization (MLU) across the `setA` instances.

## Requirements

- [Julia](https://julialang.org/downloads/) `1.12` (installed via
  [juliaup](https://github.com/JuliaLang/juliaup) recommended).

## Setup

Julia uses **project environments** (`Project.toml` + `Manifest.toml`) instead
of virtual environments. The dependencies are already pinned in this repo, so
you just need to instantiate them once:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

This downloads and precompiles all packages (Graphs, JuMP, HiGHS, JSON3, …)
into the project environment.

## Run the notebook (Pluto)

```bash
julia --project=. -e 'using Pluto; Pluto.run()'
```

Then open `t0_experiments.jl` (steps 1–5) or `t1_experiments.jl` (steps 6–8) in
the browser that Pluto opens.

> `t0_experiments.jl` implements steps 1–5: the **period-0** model (MLU
> minimization, 900 s limit), writing to `t0_results/`. `t1_experiments.jl`
> implements steps 6–8: the **two-period** model (periods 0 and 1, with the
> reconfiguration budget `β(1)`, 1800 s limit), writing to `t1_results/`. Both
> read the data from `data/` and share the modules in `source/`. The older
> `orange_challenge.jl` notebook references a `summer-school-ISIMA-OTH/project/setA/`
> path that no longer exists and is kept only for reference.

## Run the pipeline directly (no notebook)

```bash
julia --project=. -e '
using JSON3, Graphs, JuMP, HiGHS
include("source/Graph.jl");          using .Graph
include("source/SplitCoefficients.jl"); using .SplitCoefficients
include("source/TrafficMatrix.jl");  using .TrafficMatrix
include("source/Scenario.jl");       using .Scenario
include("source/Model.jl");          using .Model

dataDir = joinpath(pwd(), "data")
net = JSON3.read(read(joinpath(dataDir, "setA-01-net.json"), String))
graph = get_graph_from_json(net)                 # G₀
r = get_splitCoefficients_by_graph(graph)        # r₀
tm = JSON3.read(read(joinpath(dataDir, "setA-01-tm.json"), String))
demands = get_demands_from_json(tm, graph)
sc = JSON3.read(read(joinpath(dataDir, "setA-01-scenario.json"), String))
maxSeg = get_maxSegments_from_json(sc)

# Period 1: drop the down-links, recompute r on G₁, read the budget β(1).
graph1 = get_graph_by_downtimeLinks(graph, get_downtimeLinks_from_json(sc, 1))
r1 = get_splitCoefficients_by_graph(graph1)
budget1 = get_budget_from_json(sc, 1)

# Assemble the two-period model with the fluent builder and solve.
n = nv(graph.graph)
periods = 0:1
periodInputs = Dict(0 => (graph = graph, r = r), 1 => (graph = graph1, r = r1))
b = AsrModelBuilder(; timeLimitSec = 1800)
set_variables!(b, demands, n, periods)
set_flowConservation!(b, demands, n, periods)
set_segmentCap!(b, demands, n, maxSeg, periods)
set_loadBounds!(b, periodInputs, demands, periods)
add_budgetBounds!(b, demands, n, Dict(1 => budget1), periods)   # omit for period 0 only
model = build(b)
sol = solve!(model)
println(sol)
println(get_waypoints_by_solvedModel(model, periodInputs, demands, periods))
'
```

## Repository layout

- `source/` — the Julia modules (Graph, SplitCoefficients, TrafficMatrix,
  Scenario, Model).
- `data/` — the `setA` instances (`-net.json`, `-tm.json`, `-scenario.json`).
- `t0_experiments.jl` — the Pluto notebook implementing steps 1–5 (period 0).
- `t1_experiments.jl` — the Pluto notebook implementing steps 6–8 (periods 0 and
  1, with the budget).
- `t0_results/`, `t1_results/` — per-run, per-instance JSON outputs of the sweeps.
- `project/` — challenge subject, notes, and the original instance data.
