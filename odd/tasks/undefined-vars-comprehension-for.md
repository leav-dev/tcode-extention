# Fix: undefined-vars flags comprehension vars used before `for` (py)

## User report (Django, Python)
```python
missing_ids = [
    str(i['institucion_id'])      # <- warns undefined 'i' HERE
    for i in instituciones
    if i.get('institucion_id') and not i.get('institucion_dane')
]
```
`i` is not defined above the comprehension (correct Python). Error points at
`str(i[` — the value expression, textually BEFORE the `for i in ...` clause.

## Root cause
`analyzeScope` is single-pass, top-down. The value expression of a
comprehension (`str(i[...])`) is visited before the `for i in ...` clause
that defines `i`, so it reports a forward reference (a documented py limit:
"forward references in py can warn"). Same for dict/set comprehensions and
generator expressions: `{k: f(v) for k, v in items}` flags `k`/`v` in `f(v)`.

Python semantics note: `for`-statement targets leak into the enclosing scope,
and py analysis already uses a single file scope, so pre-defining `for`
targets up front matches the existing model.

## Fix
Add a py-only pre-scan (mirroring Go's `preScanPackageLevel`): before the
main loop, walk all tokens once; on every `for` keyword collect the target
ids up to the matching `in` on the same logical line (same rule as the
`handlePy` `for` branch: ids that are not keywords, stop at `nl`) and
`define` them in global. Then the main loop stays untouched.

Do NOT change: member-chain order, import handling, any js/ts/go path.

## Verification
- `undefined-vars/harness` new cases (all must PASS, pre-existing stay green):
  - py: the exact user snippet (list comprehension, use-before-for) -> no findings.
  - py: dict comprehension `{k: v for k, v in items}` -> no findings.
  - py: generator `sum(x for x in items)` -> no findings.
  - py: regular loop still fine + true undefined still flags
    (`print(nope)` with no def -> `undefined 'nope'`).
- Run `cd undefined-vars/harness && GOFLAGS=-mod=mod GOPROXY=off go run .` -> 0 failures.

## Tasks
1. [x] Feature doc + root cause.
2. [x] Pre-scan `for` targets in `undefined-vars/main.lua` (py only).
3. [x] Harness regression cases + green run (55/55).
4. [x] Verified + closed (verify agent, exact user snippet clean). Version 1.0.6.
