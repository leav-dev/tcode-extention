# Fix: undefined-vars must support multiline imports (all languages)

## User report
Parenthesized / multiline imports still warn as undefined. Multiline import
exists in every supported language, so the fix must cover all of them, not
just Python.

## Current gaps (traced in undefined-vars/main.lua)
- **py `from`**: handler breaks on `(` / `nl`, so `from .models import (
  A, B, )` multiline defines nothing and the names inside are flagged.
- **py `import`**: handler breaks on `,`, so `import os, sys` only defines
  `os`. Backslash-continued `import A, \n B` breaks on `nl`.
- **js/ts `import`**: depth-tracked `{}` loop probably handles multiline, but
  has no regression lock. Verify; fix only if broken.
- **go `import`**: `(...)` block handler exists. Verify with multiline block
  + alias; fix only if broken.

## Fix scope
1. py `handlePy` `from`: skip `(`, `)`, `nl` inside the imported name list;
   keep `as` alias handling (define alias, not original); keep breaking on
   `;`/real end. Single-line behavior unchanged.
2. py `handlePy` `import`: accept `,` separators (define each name / alias);
   skip `nl` after `,` or `\` continuation.
3. js/ts + go: add multiline regression cases first; fix only what fails.
4. No other scope/branch changes. The member-chain reorder from
   undefined-vars-member-chain.md stays as is.

## Verification
- `undefined-vars/harness` new cases (all must PASS, pre-existing stay green):
  - py: `from .models import (\n A,\n B,\n)` then use A, B -> no findings.
  - py: `from .models import A, B` single line -> no findings (lock).
  - py: `from x import y as z` then use z -> no findings.
  - py: `import os, sys` then use both -> no findings.
  - js/ts: multiline `import {\n A,\n B\n} from "m"` then use A, B -> no findings.
  - go: multiline `import (\n "fmt"\n alias "x/y"\n)` -> fmt, alias defined.
  - Negative: truly undefined name still flags.
- Run `cd undefined-vars/harness && GOFLAGS=-mod=mod GOPROXY=off go run .` -> 0 failures.

## Tasks
1. [x] Feature doc + gaps.
2. [x] Multiline import fix in `undefined-vars/main.lua` (py fixed; js/ts/go verified OK as-is).
3. [x] Harness regression cases + green run (51/51).
4. [x] Verified + closed (verify agent, read-only).
