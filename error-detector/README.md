# Code Linter (`tcode.errordetector`)

First extension with **real Lua logic** for tcode (scripting backend,
gopher-lua). Lints the active buffer on save or `alt+shift+e`:

- **Bracket balance** `() [] {}` with string awareness → severity `error`
  (gutter `!`, red)
- **Scope analysis** — used-but-undefined variables and unused imports →
  severity `warning` (gutter `?`, amber), marked **inline at the right of
  the line**: supports **Go, JS/TS (Angular rides on TS) and Python**
- HTML and Docker: balance only in v1 (no scope analysis — documented limit)

## Installation

```sh
tcode --install-extension <git-url-or-local-path-of-this-repo>
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes diagnostics |
| `alt+shift+e` | On-demand check |

No issues: clears markers, `Code Linter: no issues found`. With issues:
markers per line (error/warning colors + inline message at the right).

## How it works

The command `tcode.errordetector.check` is declared with `"script":
"main.lua"` and `"fn": "check"`. The script uses the `tcode.*` host API:

- `tcode.buffer()` → path and content of the active buffer
- `tcode.diagnostics.set({ {line, message, severity}, … })` → gutter + inline markers (line 1-indexed; severity `error|warning|info`)
- `tcode.diagnostics.clear()` → removes the markers
- `tcode.message(msg)` → status bar

Language detection is path-extension based (`*.go`, `*.{js,jsx,ts,tsx}`,
`*.py`, `*.html`, `Dockerfile`). The host exposes only base/table/string/math
(no `io`/`os`): the analysis is **pure Lua over the content**, structural and
heuristic. **Convention: all messages are English.**

## Scope rules (v1)

- **Definitions**: go `var/const/type` (single + block), `:=`, func name,
  params + named returns + receiver, imports (aliased included; `import .`
  disables undefined checks); js/ts `let/const/var` (+ simple destructuring),
  function/class/arrows, import bindings; py any assignment, `def`/`class`,
  `import`/`from ... import`, lambda/for/with-as params.
- **Usage**: identifiers outside comments/strings; `pkg.Fn`/`obj.attr` chains
  check only the base name. Keywords and per-language builtins are ignored.
- **Findings** (all `warning`): `undefined 'x'`, `unused import 'x'`.

## Honest limits (v1)

- No type analysis; struct field names in Go bodies and TS generics may
  false-positive.
- py uses a single file scope (no indentation); forward references in py can
  warn (`def g(): return missing` where `missing` is defined later).
- js/ts: a plain `x = v` assignment is treated as an implicit definition
  (common style); single-param arrows are detected at boundaries, so a
  `a >= b` comparison never defines its operand (documented).
- html/docker: balance only. Angular uses the TS rules.
- The detector message replaces the "saved" message in the status bar.