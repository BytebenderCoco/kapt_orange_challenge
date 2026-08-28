# Architecture

How the project is organized. See [`task.md`](task.md) for the 8-step assignment
and [`the_challenge/`](the_challenge) for the problem spec.

## Two goal notebooks

Steps 5 and 8 are "experiments" — each sums up the steps before it, so they are
our two deliverables. Each is a Pluto notebook:

- [`t0_experiments.jl`](t0_experiments.jl) — **step 5**: steps 1–4 for period 0,
  then the sweep over all `data/` instances (900 s each).
- [`t1_experiments.jl`](t1_experiments.jl) — **step 8**: steps 6–7 add period 1
  (build `G₁`, recompute `r₁`, budget `β(1)`), then the sweep (1800 s each).

The notebooks are orchestration + IO: they read the three JSON files per instance
and hand them to the `source/` modules as input, then tabulate the results.

## `source/` modules

The other steps are modularized here, grouped by responsibility. The notebooks
feed files in; the modules do the work.

| Module | Responsibility |
| --- | --- |
| `Graph` | build the graph `G` from `-net.json` |
| `SplitCoefficients` | compute the `r` coefficients from a graph (calculate-r) |
| `TrafficMatrix` | parse demands `φ(d,t)` from `-tm.json` |
| `Scenario` | parse `maxSeg`, budget `β`, interventions `q` from `-scenario.json` |
| `Model` | build + solve the MILP (`AsrModelBuilder` → `build` → `solve!`) |
| `Result` | shared output schema + per-row JSON write |

`Model` is a fluent builder: `set_*!`/`add_*!` steps, `build` freezes it, `solve!`
runs the lexicographic descent (objective 5). `Result` is reused by both the
notebooks and the headless script so every run emits one schema.

## `scripts/` — headless / parallel path

Runs the same `source/` pipeline outside Pluto to solve instances in parallel
over SSH on a remote server.

- `t0_solve_instance.jl` — solve one instance headless (period 0), emitting the `Result` schema.
- `t1_solve_instance.jl` — solve one instance headless (periods 0–1, with budget β(1)), emitting the v2 `Result` schema.
- `run_scheduler.jl` — launch the first 10 instances in parallel (period 0).
- `t0_execution.sh` / `run_on_server.sh` — launch the parallel run / remote run.
- `collect_results.jl` — gather the per-instance result files.

## Results

Each sweep writes `t0_results/<timestamp>/<index>.json` (and `t1_results/…`) **as
each instance finishes**, so a cancelled run keeps whatever already completed.
Every file carries the same schema (instance index, `succeeded` flag, solve
metrics, per-(period-)demand `waypoints`, and an `events` log).
