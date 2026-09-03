# Orange ROADEF 2026: Segment Routing Optimizer

Solution to the [Orange ROADEF 2026 challenge](documentation/challenge/Challenge_Orange_ROADEF_2026_Subject.md): minimize unsatisfied traffic demand in a segment-routing network using MILP.

---

## Setup

Requires **Julia 1.12+** and **Pluto**.

```bash
# Install dependencies
julia --project -e 'using Pkg; Pkg.instantiate()'
```

---

## How to Use

Open one of the two experiment notebooks in Pluto:

```julia
using Pluto; Pluto.run()
```

| Notebook | What it does |
| --- | --- |
| `t0_experiments.jl` | Period 0 — solves all instances (900 s each) |
| `t1_experiments.jl` | Periods 0 + 1 — extended solve (1800 s each) |

To run headless (e.g. on a server), use the scripts:

Solve all instances in parallel (period 0):
```bash
bash scripts/t0_execution.sh
```

Solve all instances in parallel (periods 0 + 1):
```bash
bash scripts/t1_execution.sh
```

Solve a single instance manually:
```bash
julia --project=. scripts/t0_solve_instance.jl setA-01 --output t0_results/my-run
```

Collect results into a summary CSV after a run:
```bash
julia --project=. scripts/collect_results.jl
```

---

## File Structure

```
t0_experiments.jl       # Period 0 Pluto notebook (main deliverable)
t1_experiments.jl       # Period 0+1 Pluto notebook (main deliverable)
source/                 # Julia modules (Graph, Model, Result, …)
scripts/                # Headless + parallel execution
  t0_solve_instance.jl  # Solve one instance (period 0)
  t1_solve_instance.jl  # Solve one instance (period 0+1)
  t0_execution.sh       # Launch parallel run
  collect_results.jl    # Create summary.csv
data/                   # Instances (setA-01 … setA-20)
t0_results/
t1_results/
documentation/
```

---

## Further Documentation

These files are intended as detailed references. These can be long as they are mainly intended to be used as context for AI assistants working in this repo.

- [Architecture](documentation/architecture.md) — module responsibilities, notebook roles, result schema
- [Naming conventions](documentation/naming.md) — variable and file naming rules
- [Challenge spec](documentation/challenge/Challenge_Orange_ROADEF_2026_Subject.md) — full problem definition
