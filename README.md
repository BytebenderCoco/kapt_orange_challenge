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

## Run on a server (headless, non-blocking, parallel)

The `scripts/` folder runs the experiments without Pluto, in the background, and
extracts results incrementally so you can pull them as each instance finishes.

Results and logs land in `runs/<runId>/`, keyed by a run id (the local server
time, e.g. `20260825-134512`), and are committed so contributors can see them:

```
runs/<runId>/
  results/setA-01.json … setA-20.json   # one JSON per instance, written as it finishes
  results/summary.csv                   # aggregate table (from collect_results.jl)
  logs/run.log                          # master log
  logs/run.pid                          # PID of the detached launcher
  logs/setA-01.log …                    # per-instance log
```

### One-time setup on the server

```bash
# install Julia 1.12 (juliaup) and clone the repo, then:
rsync -avz ./ user@host:/path/to/gp_orange_challenge/   # or git clone/pull
```

### Launch the run (does not block your terminal)

```bash
bash scripts/run_on_server.sh            # detached via nohup (survives disconnect)
# or
bash scripts/run_on_server.sh tmux       # inside a tmux session you can reattach
```

`run_on_server.sh` instantiates the environment and starts all 20 instances in
parallel (bounded by `MAX_PROCS`, default `min(8, detected cores)`).

### Monitor and pull results incrementally

```bash
tail -f runs/<runId>/logs/run.log                    # live progress
ls runs/<runId>/results/*.json | wc -l               # finished instances (20 = done)

# from your local machine, sync results as they land:
rsync -avz user@host:/path/to/gp_orange_challenge/runs/ ./runs/
```

### Build the aggregate table (Step-5 table)

```bash
julia --project=. scripts/collect_results.jl [runId]   # runId optional (latest by default)
```

writes `runs/<runId>/results/summary.csv`.

### Scripts

- `scripts/solve_instance.jl` — solve one instance, write one result JSON.
- `scripts/run_parallel.sh` — run all instances in parallel with bounded concurrency.
- `scripts/run_on_server.sh` — non-blocking launcher (`nohup` or `tmux`).
- `scripts/collect_results.jl` — aggregate per-instance JSONs into `summary.csv`.

## Repository layout

- `source/` — the Julia modules (Graph, SplitCoefficients, TrafficMatrix,
  Scenario, Model).
- `data/` — the `setA` instances (`-net.json`, `-tm.json`, `-scenario.json`).
- `scripts/` — headless runner + parallel/launcher/aggregation scripts.
- `runs/` — per-run results and logs (committed).
- `t0_experiments.jl` — the Pluto notebook implementing steps 1–5.
- `project/` — challenge subject, notes, and the original instance data.
