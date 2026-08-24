# Naming conventions

Conventions for naming things in this project. This is a living document — it
grows as we hit cases the rules don't cover yet.

> **The meta-rule:** if a name isn't covered by any rule below, **stop and ask**
> for a rule. Don't invent an ad-hoc name — decide the convention first, then
> apply it. New rules get written down here.

## Functions

A function name is built from two kinds of tokens:

- **action / relation words** — lowercase `snake_case` connectors that describe
  *what the function does* and *how its parts relate*: `get`, `by`, `from`,
  `is`, …
- **WHAT** — the subject(s): the thing produced, consumed, or tested. Written in
  `camelCase` so multi-word subjects read as one unit and stand out from the
  action words (e.g. `splitCoefficients`, `edgeData`).

`camelCase` on WHAT is the **default, not a requirement** — a single-word WHAT
is just lowercase (`graph`), and `snake_case` or a camel/snake mix inside a WHAT
is fine when it reads better. The goal is that action words and subjects stay
visually separable.

### Patterns

#### `get_WHAT_by_WHAT` — produce output from input

Derive an output WHAT from an input WHAT, where the input is something
**abstract / already in memory** (a data structure, not an external source).

```julia
get_splitCoefficients_by_graph(net)   # the r(i,j,a) coefficients, from a graph
get_edgeData_by_graph(net, u, v)      # the edge record, from a graph
```

#### `get_WHAT_from_WHERE` — load data from an external source

Same shape, but `from` signals the data comes from **outside** the program — a
file, a JSON document, the network, disk.

```julia
get_networkGraph_from_json(path)      # load a graph from a JSON file
```

#### `is_WHAT_ATTRIBUTE` — boolean predicate

Test whether some **local data** WHAT has (or lacks) an ATTRIBUTE. Returns a
`Bool`.

```julia
is_arc_directed(net, u, v)            # does this arc have direction?
```

### Multiple outputs → one umbrella WHAT

When a function produces several tightly-coupled outputs of a *shared*
computation, keep it as one function named with an **umbrella WHAT** rather than
splitting it — splitting would redo the shared work. Split only when the outputs
come from genuinely separate computations.

```julia
get_ecmpData_by_graph(graph, metricMatrix)  # returns distances + path counts
                                            # from one Dijkstra sweep per source
```

## Variables

Two tiers.

### Tier 1 — spec quantities → their symbol

If a variable holds something the README/spec names with a symbol, name it after
that symbol.

- **Greek symbols are spelled out** in Latin (`sigma`, `omega`). Julia allows
  Unicode identifiers, but spelled names read and type better.
- The real symbol/formula goes in a **comment directly above the declaration**,
  so the code stays checkable against the spec.
- **Never reuse a spec symbol for something it doesn't mean.** A name that
  matches the wrong spec quantity is worse than a neutral name.

```julia
# σ[i, j]: number of equal-cost shortest i→j paths
sigma = zeros(Float64, n, n)

# r(i, j, a) = σ_iu · σ_vj / σ_ij
r[(i, j, (u, v))] = (sigma[i, u] * sigma[v, j]) / sigma[i, j]
```

Symbols currently in use:

| Variable | Symbol / formula (goes in the comment) |
| -------- | -------------------------------------- |
| `r`      | `r(i,j,a)` split coefficients |
| `sigma`  | `σ` — equal-cost shortest-path counts |
| `omega`  | `ω(a)` — arc weight (shortest-path metric) |
| `d`      | `d[i,j]` — shortest-path distances |
| `i`, `j` | source / target nodes |
| `u`, `v` | arc endpoints, arc `a = (u,v)` |
| `n`      | node count |
| `x`      | `x^{dt}_{ij}` — segment decision variable |
| `lambda` | `λ` — max link utilization (MLU), the objective |
| `mlu`    | `λ*` — the optimized MLU value returned by the solve |

### Tier 2 — everything else → descriptive `camelCase`

Containers, intermediate structures, and plumbing the spec doesn't symbolize get
a readable name in `camelCase` (matching the function-WHAT casing).

| Name            | What it is |
| --------------- | ---------- |
| `graph`         | the graph |
| `network`       | the `NetworkGraph` |
| `metricMatrix`  | the ω-weight matrix Dijkstra consumes |
| `capacities`    | the `c(a)` capacity map (arc → capacity), keyed like `edgeData` |
| `demands`       | the traffic-matrix demands (`(id, source, target, volumes)` each) |
| `edge`          | current edge |
| `dijkstraState` | Dijkstra result object |

A container holding a spec quantity is Tier 2, not Tier 1: `capacities` maps arcs
to `c(a)` but is named descriptively, exactly as `metricMatrix` holds `ω` values
without being called `omega`. The symbol goes in a comment; the container gets a
readable name.

## Types, modules, and fields

- **Types and modules → `PascalCase`** (`NetworkGraph`, `module Graph`), matching
  Julia's own idiom.
- **A module groups things by a shared *domain*, not by a project step.** One
  module = one cohesive concept, typically one input source: `Graph` (net.json),
  `TrafficMatrix` (tm.json), `Scenario` (scenario.json). A "step" from the
  README (e.g. Step 3's *Data section*) is a **notebook section** that *assembles*
  parameters by calling into those modules — it is not itself a module. Don't
  create step-shaped catch-alls like `InstanceData`. "Only one module uses it" is
  not a reason to merge: the data-layer modules (`Graph`, `TrafficMatrix`,
  `Scenario`) are each consumed only by the model layer, yet stay separate because
  parsing an input file is a different concern from building the model.
- **Struct fields and NamedTuple keys → descriptive `camelCase`** (Tier-2 rules),
  e.g. `nodeData`, `jsonToVertex`, `edgeData`, `jsonId`. A field and its accessor
  must agree — `get_edgeData_by_graph` reads `network.edgeData`, not
  `network.edge_data`. This holds **even when the spec has a symbol for the
  field**: a demand's endpoints are `s`/`t` in the spec, but the fields are
  `source`/`target` — descriptive, and it avoids colliding with `t` = time.

## Validation

A predicate that answers "is this well-formed?" follows the `is_WHAT_ATTRIBUTE`
pattern and **returns a `Bool`** — it does not throw. It may `@warn` the first
problem it finds so failures stay diagnosable; the caller decides whether to
`error()`.

```julia
is_jsonData_valid(json) || error("Invalid network JSON: $net_file")
```
