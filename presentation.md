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