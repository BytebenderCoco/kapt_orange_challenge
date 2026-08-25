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

Then open `t0_experiments.jl` in the browser that Pluto opens.

> `t0_experiments.jl` is the current entry point (steps 1–5). It reads the data
> from `data/` and the modules from `source/`. The older `orange_challenge.jl`
> notebook references a `summer-school-ISIMA-OTH/project/setA/` path that no
> longer exists and is kept only for reference.

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
json = JSON3.read(read(joinpath(dataDir, "setA-01-net.json"), String))
graph = get_graph_from_json(json)
r = get_splitCoefficients_by_graph(graph)
capacities = get_capacities_by_graph(graph)
tm = JSON3.read(read(joinpath(dataDir, "setA-01-tm.json"), String))
demands = get_demands_from_json(tm, graph)
sc = JSON3.read(read(joinpath(dataDir, "setA-01-scenario.json"), String))
maxSeg = get_maxSegments_from_json(sc)
sol = get_solution_by_graph(graph, r, demands, capacities, maxSeg; timeLimitSec = 900)
println(sol)
'
```

## Repository layout

- `source/` — the Julia modules (Graph, SplitCoefficients, TrafficMatrix,
  Scenario, Model).
- `data/` — the `setA` instances (`-net.json`, `-tm.json`, `-scenario.json`).
- `t0_experiments.jl` — the Pluto notebook implementing steps 1–5.
- `project/` — challenge subject, notes, and the original instance data.
