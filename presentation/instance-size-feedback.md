# setA is too large for a 2-week course

- **Binaries grow as n²:** `B = |D|·n·(n-1)` → setA-10 has **22 M** binaries in one period
- **RAM:** setA-10 needs **~45 GB** just to store the model
- **Runtime scales ~B^1.85** (10× size ≈ 70× time): setA-06 **~2 days**, setA-10 **~40 days**
- Only setA-01/02/03 solved to optimality (**4–17 s**); setA-04+ hit the limit

**Takeaway:** need **smaller instances** or a **reduced formulation** (fewer candidate waypoints, since B ∝ n²·|D|)
