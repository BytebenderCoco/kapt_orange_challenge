# KAPT — Mathematical Programming with Julia

Coursework directory for the **KAPT** course (operations research / mathematical
optimization, taught in French, using **Julia**). It contains two parts: lecture
exercise materials and a main project built around the **ROADEF 2026 "Challenge
Orange."**

## Structure

### Course materials (root + `lecture3/`, `lecture4/`)

- `julia_lesson1_summary_en.pdf`, `lecture2.pdf`,
  `lecture3/Mathematical-Programming-with-Julia.pdf` — lecture notes on
  mathematical programming with Julia
- `lecture4/lecture4.pdf` — **MILP modeling tricks with integer variables**
  (Summer school ISIMA, V. H. Nguyen): logic and activation constraints,
  fixed-charge costs, semicontinuous variables, big-M indicator constraints,
  disjunctions, and linearization of logical AND/OR. Directly useful for
  formulating the project's model.
- `exemple_vector.jl`, `lecture3/incredible_chair1.jl`,
  `lecture3/vaccine_data.jl`, `lecture3/ProjectScheduling1_data.jl` — example
  Julia scripts (classic optimization exercises: furniture/chair LP, vaccine
  allocation, project scheduling)

### Main project (`project/`)

- `Challenge_Orange_ROADEF_2026_Subject.pdf` — the challenge specification (a
  telecom network-optimization problem from the ROADEF 2026 competition,
  sponsored by Orange)
- `calculating_r.pdf` — instructions for computing the `r[i,j,a,t]` parameter
  (distilled into [`calculate-r.md`](calculate-r.md): path-counting Dijkstra +
  the `σ_iu·σ_vj / σ_ij` decomposition)
- `scripts/json_to_graph_pluto_v3_all_shortest_paths.jl` — a **Pluto.jl**
  notebook that reads the JSON network files into a `Graphs.jl` graph and
  computes all shortest paths
- `setA/` — 20 problem instances, each with three JSON files:
  - `*-net.json` — the network (directed graph: nodes + links with `metric` and
    `capacity`)
  - `*-tm.json` — the traffic matrix (demands with source `s`, target `t`, and
    per-time-slot volume `v`)
  - `*-scenario.json` — scenario data (`max_segments`, per-period `budget`, and
    `interventions`)

## The problem: T-Adaptive Segment Routing (T-ASR)

The project is built on the **EURO/ROADEF 2026 Challenge**, sponsored by Orange
("Keep The Flow!"). It is a **network traffic-engineering** problem: given an
IP/MPLS backbone and a forecast of traffic, decide how to route each traffic
demand so the network stays uncongested — even when links are taken down for
scheduled maintenance.

The full problem definition — network model, segment routing, ECMP, the `r`
split coefficients, load and MLU, the decision variables `x^{dt}_{ij}`,
constraints (1)–(4), and the lexicographic min-max objective (5) — is specified
in
[`the_challenge/Challenge_Orange_ROADEF_2026_Subject.md`](the_challenge/Challenge_Orange_ROADEF_2026_Subject.md).
That document is canonical; this file does not restate it.

## Project task

The `project/readme` lays out an 8-step plan to build this model as a **MILP**
(likely with JuMP), as a simplified, staged version of T-ASR:

1. Use the Pluto script to build graph *G* at time period 0
2. Compute the parameter `r[i,j,a,0]` per `calculating_r.pdf`
3. Build a **Data** section deriving model parameters from the 3 JSON files
   (`r` and link cost `c(a)` from net, demand `v(d,0)` from tm, `MaxSeg` from
   scenario)
4. Implement the model for **time period 0 only** (no budget constraints)
5. Run numerical experiments on all setA instances (900 s time limit),
   tabulating vertices, links, demands, objective value, CPU time, and solver
   status/gap
6. Build the graph at time period 1 and compute its parameters
7. Extend the model to **time period 1**, adding the **budget constraints**
8. Re-run numerical experiments on the setA instances (1800 s time limit),
   reporting the same table columns

Steps 1–5 implement **period 0 only** (constraints 1–3; the budget constraint 4
is irrelevant with a single period), and steps 6–8 add period 1 together with
the linking **budget constraint (4)**. In short: a Julia-based
**segment-routing / traffic-engineering optimization project** for the ROADEF
2026 telecom challenge, with lecture materials on the side.
