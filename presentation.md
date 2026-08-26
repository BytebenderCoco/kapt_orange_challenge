# Oral Presentation Plan & Task Distribution (15 min)

To make our 15-minute presentation as dynamic as possible, we will present **step-by-step**, switching speech naturally at each phase. For every step, we will cover **Theory → Implementation → Results/Key Takeaways**.

---

## Timing Overview

* **Intro (1 min):** Problem Context & Challenge Goals
* **Nominal Period $t=0$ (Steps 1 to 5) (~8 min):** Graph construction, ECMP, MILP formulation & Parallel benchmarks
* **Maintenance Period $t=1$ (Steps 6 to 8) (~5 min):** Degraded topology, budget constraints & coupled optimization
* **Conclusion & Q&A Transition (1 min):** Summary & future work (heuristics)

---

## Step-by-Step Breakdown: Who Says What & When

### 🔹 Introduction (1 min) — *Speaker 1 (Theory)*
* **Context:** Orange Research Challenge — $T$-Adaptive Segment Routing ($T$-ASR).
* **Objective:** Minimize the Maximum Link Utilization (MLU / $\lambda_{\max}$) using Segment Routing waypoints in both nominal ($t=0$) and maintenance ($t=1$) states.

---

### 🔹 Step 1 — Network Graph Construction ($G_0$)
* **Theory :** Graph $G=(V,A)$, arc metrics $\omega_a$, and bandwidth capacities $c_a$.
* **Implementation :** `source/Graph.jl` module, `get_graph_from_json`, and JSON validation with `is_jsonData_valid`.
* **Results & Key Finding :** Network scale (20 to 150 nodes)[cite: 17, 18, 19, 20, 24] and **our key finding that Multigraph instances (`"multigraph": true`) are rejected early** by design because `SimpleDiGraph` does not support parallel edges.

---

### 🔹 Step 2 — Shortest Paths & Split Coefficients ($r$)
* **Theory :** Calculating split coefficients $r(u,v,a)$ via Dijkstra and Equal-Cost Multi-Path (ECMP) flow splitting.
* **Implementation :** `source/SplitCoefficients.jl` module using direct `Graphs.jl` functions (`dijkstra_shortest_paths` with `allpaths=true`) for optimal execution speed.
* **Results :** Negligible execution time for path counting and coefficient matrix generation.

---

### 🔹 Steps 3, 4 & 5 — Nominal Model ($t=0$) & Benchmarking
* **Theory :** Binary decision variables $x_{ij}^d$, Flow Conservation (Eq. 1), `maxSeg` cap (Eq. 2), and Arc Load / MLU minimization objective (Eq. 3 & 5).
* **Implementation :** `source/Model.jl` using the **Builder Pattern** (`AsrModelBuilder`) and HiGHS solver. **Parallel execution infrastructure** via `scripts/run_parallel.sh` running concurrent instances on server cores.
* **Results :** Benchmark analysis on Set A. Fast optimal convergence (Gap 0%) on smaller instances (`setA-01` to `03`), but `TIME_LIMIT` reached on large instances (`setA-04`, `setA-09`) due to binary variable explosion.

---

### 🔹 Step 6 — Maintenance Scenario ($t=1$) & Degraded Graph ($G_1$)
* **Theory :** Link downtime scenario $q(1)$ resulting in degraded graph $G_1 = (V, A \setminus q(1))$ and recomputation of routing coefficients $r_1$.
* **Implementation :** `get_graph_by_downtimeLinks` in `source/Graph.jl` and feeding $G_1$ back into `SplitCoefficients.jl`.
* **Results :** Structural impact of link removals on shortest path topologies.

---

### 🔹 Steps 7 & 8 — Reconfiguration Budget ($\kappa_1$) & Multi-Period Solve
* **Theory :** Reconfiguration cost control via budget constraint $\text{dist}(P^0, P^1) \le \kappa_1$ (Eq. 4) to limit waypoint changes.
* **Implementation :** Multi-period builder in `source/Model.jl` with `add_budgetBounds!` using linearized auxiliary variables `segmentChange`.
* **Results :** Two-period coupled results (`t1_experiments.jl`), showing the trade-off between network load optimization and reconfiguration budget restrictions.

---

### 🔹 Conclusion & Q&A (1 min) — *Speaker 3 (Results)*
* **Summary:** Clean modular architecture in Julia, fully parallelized benchmarking pipeline.
* **Perspectives:** Need for metaheuristics to overcome exact MILP limits on large scale networks (`TIME_LIMIT`).

---

# Project Reference — Facts & Figures

*Auto-collected from the repository for quick lookup during Q&A. Keep in sync when results change.*

## Stack & Tooling

* **Language:** Julia `1.12` (via juliaup); project env in `Project.toml` + `Manifest.toml`.
* **Graphs:** `Graphs.jl` (~1.14) — `SimpleDiGraph` + `dijkstra_shortest_paths(allpaths=true)`.
* **Optimization:** `JuMP` (~1.31) + `HiGHS` (~1.24) MILP solver.
* **Data:** `JSON3` for the NetworkX-compatible instance JSONs.
* **Notebooks:** `Pluto` (`t0_experiments.jl`, `t1_experiments.jl`).
* **Visualization:** `Plots.jl` (`scripts/plot_results.jl` → `presentation/assets/plots/*.svg`).
* **Slides:** hand-rolled HTML/CSS + KaTeX ("Cartesian" style), fully offline.

## Repository Architecture

**Data layer (`source/`)** — one module per input file:

| Module | Consumes | Produces |
|--------|----------|----------|
| `Graph.jl` | `-net.json` | `NetworkGraph`, capacities, down-link removal (`get_graph_by_downtimeLinks`) |
| `TrafficMatrix.jl` | `-tm.json` | demands `(id, source, target, volumes)` |
| `Scenario.jl` | `-scenario.json` | `maxSeg`, downtime links `q(t)`, budget `β(t)` |
| `SplitCoefficients.jl` | graph | ECMP split coefficients `r(i,j,a)` |
| `Model.jl` | all above | `AsrModelBuilder` → `AsrModel` → `solve!` |
| `Result.jl` | — | result-document persistence (schema v1.3.0) |

**Orchestration (`scripts/`)** — headless, parallel, non-blocking:

| Script | Role |
|--------|------|
| `solve_instance.jl` | solve one instance → one result JSON (+ peak RSS) |
| `run_scheduler.jl` | RAM-aware work queue (`MAX_RAM_GB`, `MAX_PROCS`) |
| `run_parallel.sh` / `run_on_server.sh` | instantiate env + launch (`nohup` / `tmux`) |
| `collect_results.jl` | per-instance JSONs → `summary.csv` |
| `plot_results.jl` | run results → SVG charts |

Results land in `t0_results/<runId>/` (one JSON per instance, written as each finishes).

## Input Data — Set A

* **Scale:** 20 → 400 nodes · 80 → 2000 arcs · 40 → 6000 demands.
* **10 simple** instances (01, 02, 03, 04, 07, 09, 11, 15, 18, 20) — in scope.
* **10 multigraph** instances (05, 06, 08, 10, 12, 13, 14, 16, 17, 19) — out of scope (`SimpleDiGraph` cannot represent parallel arcs; multigraph support reverted, to be handled separately).
* Every scenario: `max_segments = 6`, exactly one intervention at `t = 1` (a single link down), and one budget `β(1)`.

**Budget β(1) per instance:** 01:51 · 02:63 · 03:53 · 04:44 · 05:1 · 06:13 · 07:90 · 08:13 · 09:18 · 10:1 · 11:89 · 12:13 · 13:12 · 14:13 · 15:54 · 16:13 · 17:1 · 18:89 · 19:13 · 20:90.

## Model — Key Equations

* Decision: $x^d_{ij}\in\{0,1\}$ — demand $d$ uses segment $(i,j)$.
* Flow conservation (Eq. 1), segment cap ≤ `maxSeg` (Eq. 2), arc load ≤ $\lambda\,c(a)$ (Eq. 3), budget $\text{dist}(P^0,P^1)\le\kappa_1$ (Eq. 4).
* Objective (Eq. 5): `lex min` of the sorted load vector $\lambda'(1)\ge\lambda'(2)\ge\dots$
* Split coefficients: $r(i,j,a)=\sigma_{iu}\,\sigma_{vj}/\sigma_{ij}$ (ECMP, from path counts $\sigma$).

## Algorithmic Details

* **Lexicographic min-max** as a descent: minimize $\lambda = S_1$ (the MLU), freeze it, then for $k=2,3,\dots$ minimize $S_k$ = sum of the $k$ largest loads via a **binary-free OWA gadget** ($S_k = k\,t_k + \sum_a d_a$, $d_a \ge \text{load}(a)/c(a) - t_k$). Warm-start each level from the previous solution; gap loosened to 5% for levels ≥ 2.
* **Unreachable segments** are fixed to 0 so a disconnected demand cannot be "routed" at zero load.
* **Budget linearization:** $|x^{d,1}_{ij}-x^{d,0}_{ij}|$ via a non-negative auxiliary `segmentChange`.
* **Solver config:** HiGHS, `mip_rel_gap = 0.01`, 900 s (t0) / 1800 s (t1) time limit.

## Benchmark Results (nominal t = 0, run `20260826-080344`)

| Instance | V | A | D | Status | MLU | Gap | CPU (s) |
|----------|---|---|---|--------|-----|-----|---------|
| setA-01 | 20 | 80 | 40 | OPTIMAL | 0.929 | 0% | 3.9 |
| setA-02 | 30 | 150 | 45 | OPTIMAL | 0.549 | 0% | 89 |
| setA-03 | 50 | 250 | 20 | OPTIMAL | 0.944 | 0.9% | 16.6 |
| setA-04 | 50 | 250 | 200 | TIME_LIMIT | — | — | 920 |
| setA-07 | 100 | 500 | 800 | TIME_LIMIT | — | — | 1175 |

*(Multigraph instances 05, 06, 08 also ran to TIME_LIMIT but are out of scope.)*

**Key finding:** small instances converge to proven optimality (gap ≈ 0%) in seconds; larger ones hit `TIME_LIMIT` because the binary-variable count (~ $|D|\cdot|V|^2$) explodes → motivates metaheuristics.

## Scope Decisions & Limitations

* Multigraph instances are **not solved** (deliberate scope limitation).
* The exact MILP is the baseline; **metaheuristics** (greedy / local search / GRASP) are the planned next step for large instances.
* **t = 1** two-period model is implemented and runs on setA-01 (`t1_experiments.jl`), but the full `t1_results` benchmark sweep is **pending**.

## Development Milestones (git)

* Fluent builder-pattern model + HiGHS; lexicographic descent (OWA gadget) + warm start; RAM-aware work-queue scheduler; result persistence (`Result.jl`); parallel runner; plotting + presentation.