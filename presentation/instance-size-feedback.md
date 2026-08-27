# setA is too large to solve in a 2-week course — feedback

## 1. How big are the instances (in binary variables)

The model has one binary `x[d,i,j]` per **(demand, ordered node pair)** — a yes/no
"does demand *d* use segment *(i,j)*?". So the number of binaries is:

```
B = |D| · n · (n-1)     =   demands  ×  possible segments
```

It grows with **n²**, so it explodes on the larger topologies:

| instance | nodes n | demands \|D\| | binaries B |
|----------|--------:|-----------:|-----------:|
| setA-01  |   20 |   40 |     15 200 |
| setA-03  |   50 |   20 |     49 000 |
| setA-04  |   50 |  200 |    490 000 |
| setA-05  |  100 |  100 |    990 000 |
| setA-06  |  100 |  500 |  4 950 000 |
| setA-07  |  100 |  800 |  7 920 000 |
| setA-08  |  150 |  200 |  4 470 000 |
| setA-10  |  150 | 1000 | 22 350 000 |

setA-10 has **22 million binary variables** in a single period.

## 2. How big in RAM

RAM to *store the model* scales roughly linearly with B (~2 KB/binary at scale).
Measured (RSS while running / recorded maxrss):

| instance | binaries B | RAM |
|----------|-----------:|------:|
| setA-01  |     15 200 | 0.8 GB |
| setA-04  |    490 000 | 3.1 GB |
| setA-06  |  4 950 000 | ~17 GB |
| setA-08  |  4 470 000 | ~19 GB |
| setA-10  | 22 350 000 | **~45 GB** |

setA-10 needs ~45 GB just to hold the problem — before any real search.

## 3. How we estimate runtime

The big instances get stuck in the solver's **root LP / presolve phase**
(single-threaded, and the time limit can't interrupt it there). That phase scales
as a power of B. Fitting `log T = log α + β·log B` on the three instances that
actually solved to optimality (setA-01/02/03):

```
T_first-solve  ≈  9e-8 · B^1.85    seconds
```

**β ≈ 1.85** → every 10× in size ≈ 70× in time. Predictions:

| instance | binaries B | est. first-solve | measured |
|----------|-----------:|-----------------:|----------|
| setA-01  |     15 200 |   5 s  | 4 s (optimal)   |
| setA-03  |     49 000 |  42 s  | 17 s (optimal)  |
| setA-04  |    490 000 | ~50 min| hit 15 min limit|
| setA-05  |    990 000 | ~3 h   | —               |
| setA-06  |  4 950 000 | ~2 days| —               |
| setA-07  |  7 920 000 | ~6 days| —               |
| setA-10  | 22 350 000 | ~40 days| —              |

## Takeaway (feedback)

Even the ~2-day estimates × several instances are **not realistic to solve inside a
2-week course**. The full-size setA instances need either **smaller test instances**
or a **reduced formulation** (e.g. restricting candidate waypoints to shrink B,
since B ∝ n²·|D|).
